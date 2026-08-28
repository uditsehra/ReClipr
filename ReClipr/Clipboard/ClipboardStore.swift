//
//  ClipboardStore.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
import Combine
import SwiftUI

final class ClipboardStore: ObservableObject {
    private let settings: AppSettings

    private var saveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var midnightTimer: Timer?

    // Prevents scheduleSave() from firing during init when items are first loaded
    private var isInitializing = true

    @Published private(set) var items: [ClipItem] = [] {
        didSet {
            availableDateFilters = DateFilter.available(for: items)
            guard !isInitializing else { return }
            scheduleSave()
        }
    }

    /// Date buckets that actually contain something. Recomputed when history changes
    /// rather than on every render — the overlay re-renders on each keystroke, and
    /// this walks the whole history.
    @Published private(set) var availableDateFilters: [DateFilter] = []

    @Published var searchQuery: String = ""

    private var maxHistoryCount: Int { settings.maxHistoryCount }
    private var blobBudgetBytes: Int64 { Int64(settings.blobBudgetBytes) }
    private var duplicateInterval: Double { settings.duplicateInterval }
    private var ignoredApps: Set<String> { settings.ignoredApps }
    private var duplicatePolicy: DuplicatePolicy { settings.duplicatePolicy }

    private let monitor = ClipboardMonitor()
    private let persistence: Persistence
    private let screenshotWatcher = ScreenshotWatcher()

    // AppSettings.shared is resolved inside the body, not as a default argument:
    // default-argument expressions are evaluated in the caller's isolation, which
    // is not guaranteed to be the main actor.
    /// `persistence` and `startsMonitoring` exist for tests. A test that used the
    /// real singleton would read the user's live history and, on any delete, write an
    /// empty file back over it.
    init(settings: AppSettings? = nil,
         persistence: Persistence? = nil,
         startsMonitoring: Bool = true) {
        self.settings = settings ?? .shared
        self.persistence = persistence ?? .shared
        items = self.persistence.load()
        availableDateFilters = DateFilter.available(for: items)
        isInitializing = false

        // "Today" and "Yesterday" would otherwise go stale in a long-running app.
        // Timer callbacks are delivered on the main run loop, so this is a safe
        // assertion rather than a hop — and it avoids the Task capture that would
        // otherwise cross an isolation boundary.
        midnightTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.availableDateFilters = DateFilter.available(for: self.items)
            }
        }

        // Wire callback before starting so no events are missed.
        // The timer fires on RunLoop.main so this closure always runs on the main thread.
        monitor.onNewCopy = { [weak self] content, webMeta, sidecarText in
            guard let self else { return }
            if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               self.ignoredApps.contains(bundleID) {
                return
            }
            self.addItem(content, webMeta: webMeta, sidecarText: sidecarText)
        }
        if startsMonitoring { monitor.start() }

        // Watch only the value that matters. The previous
        // UserDefaults.didChangeNotification observer re-ran this on every defaults
        // write anywhere in the app, including each keystroke in Preferences.
        self.settings.$maxHistoryCount
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.enforceHistoryLimit() }
            .store(in: &cancellables)

        self.settings.$blobBudgetBytes
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.enforceStorageBudget() }
            .store(in: &cancellables)

        screenshotWatcher.onScreenshot = { [weak self] ref, url in
            self?.ingestScreenshot(ref, fileURL: url)
        }
        if startsMonitoring { applyScreenshotWatchSetting() }

        self.settings.$watchScreenshots
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyScreenshotWatchSetting() }
            .store(in: &cancellables)

        scheduleOrphanSweep()
    }

    // MARK: - Screenshots

    /// Set when watching is enabled but the folder could not be read, which on a
    /// stock system means the Files-and-Folders prompt was declined.
    @Published private(set) var screenshotAccessDenied = false

    /// Live state for the Capture tab, so a watcher that never started is visible
    /// rather than silently doing nothing.
    @Published private(set) var screenshotFolderPath: String = ""
    @Published private(set) var screenshotIsWatching = false
    @Published private(set) var lastScreenshotCaptured: Date?

    /// On by default: capturing screenshots is a headline feature, and leaving it
    /// off meant ⇧⌘4 silently did nothing until the user found the toggle. The cost
    /// is a Files-and-Folders prompt on first launch; a refusal is not fatal, it
    /// surfaces in the Capture tab with a link to Privacy settings.
    func applyScreenshotWatchSetting() {
        let config = ScreenshotWatcher.currentConfig()
        screenshotFolderPath = config.directory.path

        guard settings.watchScreenshots, FeatureGate.isUnlocked(.screenshotWatch) else {
            screenshotWatcher.stop()
            screenshotAccessDenied = false
            screenshotIsWatching = false
            return
        }
        let started = screenshotWatcher.start(config: config)
        screenshotAccessDenied = !started
        screenshotIsWatching = started
    }

    /// Re-reads the screenshot location, which macOS changes without notifying anyone.
    func refreshScreenshotWatch() {
        applyScreenshotWatchSetting()
    }

    /// Files a new screenshot into history and, when enabled, makes it the current
    /// clipboard contents so ⌘V works without opening ReClipr at all.
    private func ingestScreenshot(_ ref: BlobRef, fileURL: URL) {
        let source = currentSourceApp()
        addItemDirectly(ClipItem(
            content: .image(ref),
            sourceBundleID: source.bundleID,
            sourceAppName: source.name))

        lastScreenshotCaptured = Date()

        guard settings.copyScreenshotToClipboard else { return }
        monitor.writeToPasteboard { pb in
            let pbItem = NSPasteboardItem()
            // Both representations: Finder pastes the file, Mail and Slack paste the
            // image. Either is what "⌘V works" has to mean, depending on the target.
            pbItem.setString(fileURL.absoluteString, forType: .fileURL)
            if let png = BlobStore.shared.load(ref) {
                pbItem.setData(png, forType: .png)
            }
            pb.writeObjects([pbItem])
        }
    }

    /// Inserts a pre-built item, honouring the history limit and storage budget but
    /// bypassing duplicate policy — a new screenshot is always a new capture.
    private func addItemDirectly(_ item: ClipItem) {
        items.insert(item, at: 0)
        enforceHistoryLimit()
        enforceStorageBudget()
    }

    /// Reclaims blobs written just before a crash, when the debounced save never
    /// ran. Deferred so it never competes with launch, and detached because walking
    /// the store off the main actor is the whole point.
    private func scheduleOrphanSweep() {
        let live = Set(items.flatMap(\.content.blobHashes))
        Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(2))
            _ = BlobGarbageCollector.sweepOrphans(liveHashes: live)
        }
    }

    deinit {
        monitor.stop()
        screenshotWatcher.stop()
        midnightTimer?.invalidate()
    }

    var filteredItems: [ClipItem] {
        guard !searchQuery.isEmpty else { return items }
        let q = searchQuery.lowercased()
        return items.filter { item in
            if item.content.searchableText.lowercased().contains(q) { return true }
            if let name = item.sourceAppName?.lowercased(), name.contains(q) { return true }
            if let title = item.sourcePageTitle?.lowercased(), title.contains(q) { return true }
            if let url = item.sourcePageURL?.absoluteString.lowercased(), url.contains(q) { return true }
            return false
        }
    }

    private func currentSourceApp() -> (bundleID: String?, name: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return (nil, nil) }
        return (app.bundleIdentifier, app.localizedName)
    }

    private func addItem(_ content: ClipContent, webMeta: ClipWebMeta, sidecarText: String? = nil) {
        let now = Date()

        if let existingIndex = items.firstIndex(where: { $0.content == content }) {
            let existingItem = items[existingIndex]

            switch duplicatePolicy {
            case .none:
                items.remove(at: existingIndex)
                items.insert(existingItem, at: 0)

            case .timed:
                let elapsed = now.timeIntervalSince(existingItem.date)
                if elapsed >= duplicateInterval {
                    let source = currentSourceApp()
                    items.insert(ClipItem(
                        content: content,
                        sourceBundleID: source.bundleID,
                        sourceAppName: source.name,
                        sourcePageURL: webMeta.sourceURL,
                        sourcePageTitle: webMeta.pageTitle,
                        sidecarText: sidecarText
                    ), at: 0)
                } else {
                    items.remove(at: existingIndex)
                    items.insert(existingItem, at: 0)
                }

            case .always:
                let source = currentSourceApp()
                items.insert(ClipItem(
                    content: content,
                    sourceBundleID: source.bundleID,
                    sourceAppName: source.name,
                    sourcePageURL: webMeta.sourceURL,
                    sourcePageTitle: webMeta.pageTitle,
                    sidecarText: sidecarText
                ), at: 0)
            }
        } else {
            let source = currentSourceApp()
            items.insert(ClipItem(
                content: content,
                sourceBundleID: source.bundleID,
                sourceAppName: source.name,
                sourcePageURL: webMeta.sourceURL,
                sourcePageTitle: webMeta.pageTitle,
                sidecarText: sidecarText
            ), at: 0)
        }

        enforceHistoryLimit()
        enforceStorageBudget()
    }

    /// Inserts a clip directly, bypassing the pasteboard. Exists so selection and
    /// key handling can be exercised without a running pasteboard monitor.
    func debugInsertForTesting(_ content: ClipContent) {
        items.insert(ClipItem(content: content), at: 0)
    }

    func copyToClipboard(_ item: ClipItem) {
        // A clip whose payload has gone must never reach the pasteboard: a dead
        // file URL pastes as a broken alias, which is worse than refusing.
        guard !item.content.isResourceMissing else { return }

        monitor.writeToPasteboard { pb in
            switch item.content {
            case .text(let text):
                pb.setString(text, forType: .string)

            case .image(let ref), .blob(let ref):
                let pbItem = NSPasteboardItem()
                if let data = BlobStore.shared.load(ref) {
                    pbItem.setData(data, forType: .init(ref.uti))
                }
                // Also offer the bytes as a file, so receivers that only accept
                // files (Finder) work as well as those that want content (Mail).
                if let url = TempExport.shared.materialize(ref) {
                    pbItem.setString(url.absoluteString, forType: .fileURL)
                }
                if let text = item.sidecarText {
                    pbItem.setString(text, forType: .string)
                }
                pb.writeObjects([pbItem])

            case .files(let attachments):
                // One NSPasteboardItem per file — a single item carrying several
                // file URLs is not how Finder or anything else reads a multi-file
                // copy.
                let items = attachments.compactMap(Self.pasteboardItem(for:))
                if !items.isEmpty { pb.writeObjects(items) }
            }
        }
    }

    /// Puts only the plain text of a clip on the pasteboard, dropping formatting,
    /// file references and every other representation.
    ///
    /// The common case is pasting a styled snippet into a document that would
    /// otherwise inherit its fonts and colours.
    func copyAsPlainText(_ item: ClipItem) {
        guard let text = item.plainText else { return }
        monitor.writeToPasteboard { pb in
            pb.setString(text, forType: .string)
        }
    }

    /// Builds the pasteboard representation of one attachment. Inline bytes are
    /// staged under their real filename; references point at the original, which is
    /// what makes ⌘V copy and ⌥⌘V move in Finder.
    nonisolated private static func pasteboardItem(for attachment: ClipAttachment) -> NSPasteboardItem? {
        let pbItem = NSPasteboardItem()
        switch attachment {
        case .inline(let ref):
            guard let url = TempExport.shared.materialize(ref) else { return nil }
            pbItem.setString(url.absoluteString, forType: .fileURL)
            if let data = BlobStore.shared.load(ref) {
                pbItem.setData(data, forType: .init(ref.uti))
            }
        case .reference(let ref):
            guard ref.exists else { return nil }
            pbItem.setString(ref.url.absoluteString, forType: .fileURL)
        }
        return pbItem
    }

    /// Pins or unpins a clip. Pinned clips are re-sorted to the top and survive both
    /// the history limit and the storage budget.
    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.date > rhs.date
        }
    }

    func deleteItem(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        cleanupOrphanedBlobs(from: [item])
    }

    func clearAll() {
        items.removeAll()
        BlobStore.shared.deleteAll()
        ImageCache.shared.invalidateAll()
        ThumbnailProvider.shared.invalidateAll()
    }

    // Trims items to maxHistoryCount. Called after every add and when the limit changes.
    private func enforceHistoryLimit() {
        guard items.count > maxHistoryCount else { return }

        // Pinned clips do not count toward the limit and are never dropped.
        var kept: [ClipItem] = []
        var dropped: [ClipItem] = []
        var unpinnedKept = 0
        for item in items {
            if item.isPinned {
                kept.append(item)
            } else if unpinnedKept < maxHistoryCount {
                kept.append(item)
                unpinnedKept += 1
            } else {
                dropped.append(item)
            }
        }
        guard !dropped.isEmpty else { return }
        items = kept
        cleanupOrphanedBlobs(from: dropped)
    }

    /// Drops the oldest disk-backed clips once the store exceeds the configured
    /// budget. Text and referenced-file clips are never chosen: evicting them would
    /// shrink history without freeing anything.
    private func enforceStorageBudget() {
        let budget = blobBudgetBytes
        guard budget > 0 else { return }

        let doomed = BlobGarbageCollector.itemsToEvict(from: items, budget: budget)
        guard !doomed.isEmpty else { return }

        let removed = items.filter { doomed.contains($0.id) }
        items.removeAll { doomed.contains($0.id) }
        cleanupOrphanedBlobs(from: removed)
    }

    /// Deletes blobs that no surviving clip references. One pass over the remaining
    /// items builds the live set, rather than rescanning history per hash — which
    /// matters now that a single clip can own many blobs.
    private func cleanupOrphanedBlobs(from removed: [ClipItem]) {
        let candidates = Set(removed.flatMap(\.content.blobHashes))
        guard !candidates.isEmpty else { return }
        let live = Set(items.flatMap(\.content.blobHashes))
        for hash in candidates.subtracting(live) {
            BlobStore.shared.delete(hash: hash)
            ImageCache.shared.invalidate(hash)
            ThumbnailProvider.shared.invalidate(hash)
        }
    }

    // Debounced save — coalesces rapid writes into one disk operation
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self.persistence.save(snapshot)
        }
    }
}
