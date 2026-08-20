//
//  ClipboardStore.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
import Combine
import SwiftUI

final class ClipboardStore: ObservableObject {
    @AppStorage("maxHistoryCount") private var maxHistoryCount: Int = 200

    private var saveTask: Task<Void, Never>?

    // Prevents scheduleSave() from firing during init when items are first loaded
    private var isInitializing = true

    @Published private(set) var items: [ClipItem] = [] {
        didSet {
            guard !isInitializing else { return }
            scheduleSave()
        }
    }

    @AppStorage("duplicatePolicy")
    private var duplicatePolicyRaw: String = DuplicatePolicy.none.rawValue
    @AppStorage("duplicateInterval")
    private var duplicateInterval: Double = 300

    @AppStorage("ignoredApps")
    private var ignoredAppsRaw: String = "com.apple.keychainaccess"

    private var ignoredApps: Set<String> {
        Set(
            ignoredAppsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    @Published var searchQuery: String = ""

    private var duplicatePolicy: DuplicatePolicy {
        DuplicatePolicy(rawValue: duplicatePolicyRaw) ?? .none
    }

    private let monitor = ClipboardMonitor()

    init() {
        items = Persistence.shared.load()
        isInitializing = false

        // Wire callback before starting so no events are missed.
        // The timer fires on RunLoop.main so this closure always runs on the main thread.
        monitor.onNewCopy = { [weak self] content, webMeta in
            guard let self else { return }
            if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               self.ignoredApps.contains(bundleID) {
                return
            }
            self.addItem(content, webMeta: webMeta)
        }
        monitor.start()
    }

    deinit {
        monitor.stop()
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

    private func addItem(_ content: ClipContent, webMeta: ClipWebMeta) {
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
                        sourcePageTitle: webMeta.pageTitle
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
                    sourcePageTitle: webMeta.pageTitle
                ), at: 0)
            }
        } else {
            let source = currentSourceApp()
            items.insert(ClipItem(
                content: content,
                sourceBundleID: source.bundleID,
                sourceAppName: source.name,
                sourcePageURL: webMeta.sourceURL,
                sourcePageTitle: webMeta.pageTitle
            ), at: 0)
        }

        if items.count > maxHistoryCount {
            let dropped = Array(items.suffix(items.count - maxHistoryCount))
            items = Array(items.prefix(maxHistoryCount))
            for item in dropped {
                if case .image(let hash) = item.content { cleanupImageIfOrphaned(hash) }
            }
        }
    }

    func copyToClipboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.content {
        case .text(let text):
            pb.setString(text, forType: .string)
        case .image(let hash):
            if let data = ImageStore.shared.load(hash), let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
        case .file(let url):
            pb.writeObjects([url as NSURL])
        }
        // Prevent the monitor from re-detecting this programmatic write
        monitor.syncChangeCount()
    }

    func deleteItem(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        if case .image(let hash) = item.content {
            cleanupImageIfOrphaned(hash)
        }
    }

    func clearAll() {
        items.removeAll()
        ImageStore.shared.deleteAll()
        ImageCache.shared.invalidateAll()
    }

    // Deletes the image file only when no remaining item references the same hash.
    private func cleanupImageIfOrphaned(_ hash: String) {
        let stillReferenced = items.contains {
            if case .image(let h) = $0.content { return h == hash }
            return false
        }
        guard !stillReferenced else { return }
        ImageStore.shared.delete(hash)
        ImageCache.shared.invalidate(hash)
    }

    // Debounced save — coalesces rapid writes into one disk operation
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            Persistence.shared.save(snapshot)
        }
    }
}
