//
//  FileRef.swift
//  ReClipr
//
//  A file left where the user put it, recorded by path plus enough metadata to
//  render a row without touching the disk. Used for anything at or above the
//  inline-size threshold, and for files that could not be read at capture time.
//
//  Pasting one of these puts the real URL on the pasteboard: ⌘V in Finder copies
//  the original, ⌥⌘V moves it. That is why the UI marks these rows as links.
//

import Foundation
import UniformTypeIdentifiers

struct FileRef: Codable, Equatable, Sendable {
    let path: String
    let filename: String
    let uti: String
    let byteCount: Int64
    let modified: Date?
    /// Always nil while the app runs unsandboxed. The field exists so the persisted
    /// schema is already correct if the App Sandbox is ever switched back on.
    let bookmark: Data?

    nonisolated init(path: String,
                     filename: String,
                     uti: String,
                     byteCount: Int64,
                     modified: Date? = nil,
                     bookmark: Data? = nil) {
        self.path = path
        self.filename = filename
        self.uti = uti
        self.byteCount = byteCount
        self.modified = modified
        self.bookmark = bookmark
    }

    nonisolated init(url: URL) {
        let standardized = url.standardizedFileURL
        let meta = FileAccess.metadata(of: standardized)
        self.init(path: standardized.path,
                  filename: standardized.lastPathComponent,
                  uti: meta?.uti ?? FileAccess.utiForExtension(standardized.pathExtension),
                  byteCount: meta?.byteCount ?? 0,
                  modified: meta?.modified,
                  bookmark: FileAccess.bookmark(for: standardized))
    }

    nonisolated var url: URL { URL(fileURLWithPath: path) }

    nonisolated var type: UTType? { UTType(uti) }

    /// Whether the original still exists. Checked lazily at render time — a missing
    /// file is never grounds for deleting the clip, since the volume may simply be
    /// unmounted.
    nonisolated var exists: Bool { FileManager.default.fileExists(atPath: path) }

    nonisolated static func == (lhs: FileRef, rhs: FileRef) -> Bool { lhs.path == rhs.path }
}

/// One file within a clip. A single copy can carry several.
enum ClipAttachment: Codable, Equatable, Sendable {
    /// Bytes copied into ReClipr's store — survives the original being deleted.
    case inline(BlobRef)
    /// Bytes left in place — cheap, but dies with the original.
    case reference(FileRef)

    private enum CodingKeys: String, CodingKey { case kind, blob, file }
    private enum Kind: String, Codable { case inline, reference }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .inline:    self = .inline(try c.decode(BlobRef.self, forKey: .blob))
        case .reference: self = .reference(try c.decode(FileRef.self, forKey: .file))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inline(let ref):
            try c.encode(Kind.inline, forKey: .kind)
            try c.encode(ref, forKey: .blob)
        case .reference(let ref):
            try c.encode(Kind.reference, forKey: .kind)
            try c.encode(ref, forKey: .file)
        }
    }

    nonisolated var filename: String {
        switch self {
        case .inline(let r):    return r.exportFilename
        case .reference(let r): return r.filename
        }
    }

    nonisolated var uti: String {
        switch self {
        case .inline(let r):    return r.uti
        case .reference(let r): return r.uti
        }
    }

    nonisolated var byteCount: Int64 {
        switch self {
        case .inline(let r):    return r.byteCount
        case .reference(let r): return r.byteCount
        }
    }

    /// True only for references whose original has gone. Inline attachments own
    /// their bytes and cannot go missing this way.
    nonisolated static func == (lhs: ClipAttachment, rhs: ClipAttachment) -> Bool {
        switch (lhs, rhs) {
        case let (.inline(a), .inline(b)):       return a.hash == b.hash
        case let (.reference(a), .reference(b)): return a.path == b.path
        default:                                 return false
        }
    }

    nonisolated var isMissing: Bool {
        switch self {
        case .inline(let r):    return !BlobStore.shared.exists(r)
        case .reference(let r): return !r.exists
        }
    }
}
