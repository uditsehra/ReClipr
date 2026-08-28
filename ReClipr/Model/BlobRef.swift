//
//  BlobRef.swift
//  ReClipr
//
//  A reference to bytes held in ReClipr's own content-addressed store.
//  Identity is the SHA-256 of the content, so identical payloads share one file
//  and equality is a 64-character string compare rather than a byte-for-byte scan.
//

import Foundation
import UniformTypeIdentifiers

struct BlobRef: Codable, Equatable, Hashable, Sendable {
    /// SHA-256 hex of the stored bytes.
    let hash: String
    /// Uniform type identifier, e.g. "public.png", "com.adobe.pdf", "public.mp3".
    let uti: String
    /// Filename extension, stored so building a path never needs a UTType lookup.
    let ext: String
    /// Size in bytes. Zero is a legal "unknown" sentinel for records migrated from v1.
    let byteCount: Int64
    /// Original display name where one was available.
    let filename: String?

    nonisolated init(hash: String, uti: String, ext: String, byteCount: Int64, filename: String? = nil) {
        self.hash = hash
        self.uti = uti
        self.ext = ext
        self.byteCount = byteCount
        self.filename = filename
    }

    /// Equality intentionally ignores metadata: two records naming the same bytes are
    /// the same blob even if one was captured with a filename and the other was not.
    nonisolated static func == (lhs: BlobRef, rhs: BlobRef) -> Bool { lhs.hash == rhs.hash }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(hash) }

    nonisolated var type: UTType? { UTType(uti) }

    /// Name to use when handing this blob to another app, which must never be the
    /// bare `<sha256>.<ext>` the store uses on disk.
    nonisolated var exportFilename: String {
        if let filename, !filename.isEmpty { return filename }
        return "clip.\(ext.isEmpty ? "dat" : ext)"
    }
}
