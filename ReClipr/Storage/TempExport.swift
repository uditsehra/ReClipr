//
//  TempExport.swift
//  ReClipr
//
//  Blobs are stored as <sha256>.<ext>, so handing one straight to Finder would paste
//  a file literally named "a3f9c1…png". This materialises a copy under the name the
//  user expects, hard-linked where possible so it costs no extra disk.
//
//  The staging directory is cleared at launch; anything the OS misses it reaps from
//  /var/folders on its own schedule.
//

import Foundation
import OSLog

final class TempExport {
    nonisolated static let shared = TempExport()

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "TempExport")

    private let root: URL

    private init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReClipr", isDirectory: true)
    }

    /// Removes staged files left behind by a previous run.
    nonisolated func purge() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Returns a URL naming `ref`'s bytes with a human filename, or nil if the blob
    /// is missing. Repeated calls for the same blob reuse the staged file.
    nonisolated func materialize(_ ref: BlobRef) -> URL? {
        let source = BlobStore.shared.url(for: ref)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let dir = root.appendingPathComponent(ref.hash, isDirectory: true)
        let target = dir.appendingPathComponent(ref.exportFilename)
        if FileManager.default.fileExists(atPath: target.path) { return target }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // A hard link is free within a volume; fall back to a copy across one.
            do {
                try FileManager.default.linkItem(at: source, to: target)
            } catch {
                try FileManager.default.copyItem(at: source, to: target)
            }
            return target
        } catch {
            Self.logger.error("Could not stage blob for export: \(error, privacy: .public)")
            return nil
        }
    }
}
