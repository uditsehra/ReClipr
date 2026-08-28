//
//  FileAccess.swift
//  ReClipr
//
//  The single seam through which all filesystem access outside Persistence flows.
//  Keeping it in one place is what makes re-enabling the App Sandbox a one-file
//  change: the security-scoped variants slot in here and nothing else moves.
//

import Foundation
import UniformTypeIdentifiers

struct FileMetadata: Sendable {
    let byteCount: Int64
    let uti: String
    let modified: Date?
    let isReadable: Bool
}

enum FileAccess {

    /// True when running inside an App Sandbox container. The app currently ships
    /// unsandboxed, but the checks below stay honest if that is ever reversed.
    nonisolated static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// ~/Library/Application Support/ReClipr — the real path when unsandboxed,
    /// the container-redirected path when not.
    nonisolated static func appSupportDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("ReClipr", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Unsandboxed this is a straight passthrough. Sandboxed it would bracket the
    /// body in start/stopAccessingSecurityScopedResource.
    nonisolated static func withReadAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T {
        try body(url)
    }

    /// Returns nil while unsandboxed — FileRef.bookmark exists so the persisted
    /// schema is already correct if the sandbox is re-enabled later.
    nonisolated static func bookmark(for url: URL) -> Data? {
        guard isSandboxed else { return nil }
        return try? url.bookmarkData(options: .withSecurityScope,
                                     includingResourceValuesForKeys: nil,
                                     relativeTo: nil)
    }

    nonisolated static func resolve(bookmark: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: bookmark,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale)
    }

    nonisolated static func metadata(of url: URL) -> FileMetadata? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentTypeKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return FileMetadata(
            byteCount: Int64(values.fileSize ?? 0),
            uti: values.contentType?.identifier ?? utiForExtension(url.pathExtension),
            modified: values.contentModificationDate,
            isReadable: FileManager.default.isReadableFile(atPath: url.path)
        )
    }

    /// Probe used to detect a denied Files-and-Folders TCC grant before showing UI
    /// that depends on it.
    nonisolated static func canRead(directory: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) != nil
    }

    nonisolated static func utiForExtension(_ ext: String) -> String {
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return "public.data" }
        return type.identifier
    }
}
