//
//  ScreenshotWatcher.swift
//  ReClipr
//
//  ⌃⇧⌘4 puts a screenshot on the pasteboard, so the ordinary monitor already sees it.
//  Plain ⇧⌘3 / ⇧⌘4 do not: screencapture writes the file and never touches the
//  pasteboard, which is why those screenshots have never appeared in history.
//
//  This watches the screenshot folder and, when a new capture lands, files it into
//  history and puts it on the pasteboard so ⌘V works immediately.
//

import AppKit
import CoreServices
import Foundation
import OSLog
import UniformTypeIdentifiers

struct ScreenshotConfig: Sendable {
    let directory: URL
    let namePrefix: String
    let fileExtension: String
}

final class ScreenshotWatcher {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "ScreenshotWatcher")

    /// Called on the main actor with the imported screenshot.
    var onScreenshot: (@MainActor (BlobRef, URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var known: Set<String> = []
    private var config: ScreenshotConfig?
    private let queue = DispatchQueue(label: "com.budda.ReClipr.screenshot-watcher")

    private(set) var isWatching = false

    deinit { stopWatching() }

    // MARK: - Configuration

    /// macOS stores the screenshot location in com.apple.screencapture, but the key
    /// is simply absent until the user changes it — verified on a stock system — so
    /// the Desktop fallback is required, not defensive.
    nonisolated static func currentConfig() -> ScreenshotConfig {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")

        let fallback = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")

        var directory = fallback
        if let location = defaults?.string(forKey: "location"),
           !location.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (location as NSString).expandingTildeInPath
            let candidate = URL(fileURLWithPath: expanded).standardizedFileURL

            // A configured location that no longer exists — an unmounted volume, a
            // folder the user deleted — must not silently disable capture. Fall back
            // to the Desktop, which is where screencapture itself reverts to.
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                directory = candidate
            }
        }

        // `name` and `type` may be set to an empty string, which screencapture
        // ignores; treat those as unset too.
        let name = defaults?.string(forKey: "name").flatMap { $0.isEmpty ? nil : $0 } ?? "Screenshot"
        let type = defaults?.string(forKey: "type").flatMap { $0.isEmpty ? nil : $0 } ?? "png"

        return ScreenshotConfig(directory: directory, namePrefix: name, fileExtension: type)
    }

    // MARK: - Lifecycle

    /// Returns false when the folder cannot be read, which on a stock system means
    /// the Files-and-Folders permission was declined. The caller surfaces that.
    @discardableResult
    func start() -> Bool {
        start(config: Self.currentConfig())
    }

    /// Watches an explicit folder. `start()` resolves the system screenshot location;
    /// this overload exists so a caller can point the watcher elsewhere.
    @discardableResult
    func start(config: ScreenshotConfig) -> Bool {
        stop()

        guard FileAccess.canRead(directory: config.directory) else {
            Self.logger.error("Cannot read the screenshot folder; permission likely denied")
            return false
        }
        self.config = config

        // Baseline the folder so existing files are never imported — only captures
        // taken from now on.
        known = Self.filenames(in: config.directory)

        descriptor = open(config.directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue)
        src.setEventHandler { [weak self] in self?.directoryChanged() }
        src.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        src.resume()
        source = src
        isWatching = true
        return true
    }

    func stop() { stopWatching() }

    private func stopWatching() {
        source?.cancel()
        source = nil
        isWatching = false
        known.removeAll()
    }

    // MARK: - Detection

    private func directoryChanged() {
        guard let config else { return }

        // screencapture writes then renames, and interactive captures leave dot-files
        // behind while in progress. A short debounce lets the folder settle.
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let current = Self.filenames(in: config.directory)
            let added = current.subtracting(self.known)
            self.known = current

            for name in added where Self.isPlausibleScreenshot(name, config: config) {
                self.ingest(config.directory.appendingPathComponent(name))
            }
        }
    }

    nonisolated private static func filenames(in directory: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    /// Cheap name-based prefilter. The authoritative check is Spotlight's
    /// kMDItemIsScreenCapture, applied once the file has stopped changing.
    nonisolated private static func isPlausibleScreenshot(_ name: String, config: ScreenshotConfig) -> Bool {
        guard !name.hasPrefix("."), !name.contains(".sb-") else { return false }
        return (name as NSString).pathExtension.lowercased() == config.fileExtension.lowercased()
    }

    // MARK: - Import

    private func ingest(_ url: URL) {
        let callback = onScreenshot
        Task.detached(priority: .utility) {
            guard await Self.waitUntilStable(url) else {
                Self.logger.error("Screenshot never settled: \(url.lastPathComponent, privacy: .public)")
                return
            }
            guard Self.isScreenCapture(url) else { return }
            guard let ref = try? BlobStore.shared.importFile(at: url) else { return }
            await MainActor.run { callback?(ref, url) }
        }
    }

    /// The rename can be observed before the bytes are flushed, so wait for size and
    /// modification date to hold steady and for the file to actually open.
    nonisolated private static func waitUntilStable(_ url: URL) async -> Bool {
        var previous: (Int64, Date?)?
        for _ in 0..<10 {
            guard let meta = FileAccess.metadata(of: url) else { return false }
            let current = (meta.byteCount, meta.modified)
            if let previous,
               previous.0 == current.0, previous.1 == current.1,
               current.0 > 0,
               (try? FileHandle(forReadingFrom: url)) != nil {
                return true
            }
            previous = current
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    /// screencapture tags its output in Spotlight, which is the authoritative signal.
    ///
    /// A positive tag is conclusive. Anything else — the attribute missing, or present
    /// but still false because indexing has not caught up with the rename — falls
    /// through to a name-and-recency heuristic rather than rejecting outright. Trusting
    /// a `false` here would silently drop real screenshots on exactly the timing the
    /// stability gate exists to tolerate, and would drop every screenshot on volumes
    /// where Spotlight is disabled.
    nonisolated private static func isScreenCapture(_ url: URL) -> Bool {
        // The constant is not bridged into Swift, so the attribute is named directly.
        if let item = MDItemCreate(nil, url.path as CFString),
           let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool,
           flag {
            return true
        }
        let config = currentConfig()
        let name = url.lastPathComponent
        let matchesName = name.hasPrefix(config.namePrefix)
            || name.hasPrefix("Screenshot")
            || name.hasPrefix("Screen Shot")
        guard matchesName else { return false }
        guard let modified = FileAccess.metadata(of: url)?.modified else { return false }
        return Date().timeIntervalSince(modified) < 30
    }
}
