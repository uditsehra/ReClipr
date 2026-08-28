//
//  BlobStore.swift
//  ReClipr
//
//  Content-addressable storage for every kind of clip payload — images, PDFs, audio,
//  and the bytes of small copied files. Generalises the original PNG-only ImageStore.
//
//  Files live at blobs/<hash[0..2]>/<hash>.<ext>. The two-character shard keeps
//  directory enumeration cheap once history holds thousands of blobs, which the old
//  flat images/ directory would not have.
//
//  Blobs written by earlier versions still live in images/<hash>.png. Rather than
//  bulk-moving them at launch — unbounded I/O, unrecoverable if interrupted —
//  url(for:) falls back to that location, and the old directory drains naturally as
//  items age out.
//

import CryptoKit
import Foundation
import OSLog
import UniformTypeIdentifiers

struct BlobUsage: Sendable {
    let hash: String
    let url: URL
    let byteCount: Int64
    let modified: Date?

    nonisolated init(hash: String, url: URL, byteCount: Int64, modified: Date?) {
        self.hash = hash
        self.url = url
        self.byteCount = byteCount
        self.modified = modified
    }
}

final class BlobStore {
    nonisolated static let shared = BlobStore()

    // Isolated to no actor: every I/O method here runs off the main thread.
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "BlobStore")

    private let blobsDir: URL
    private let legacyImagesDir: URL

    private init() {
        let base = FileAccess.appSupportDirectory()
        blobsDir = base.appendingPathComponent("blobs", isDirectory: true)
        legacyImagesDir = base.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
    }

    // MARK: - Writing

    /// Stores `data` and returns a reference to it. Writing the same bytes twice is a
    /// no-op that returns the same hash.
    nonisolated func save(_ data: Data, uti: UTType, filename: String? = nil) -> BlobRef {
        let hash = Self.sha256(data)
        let ext = Self.fileExtension(for: uti, filename: filename)
        let ref = BlobRef(hash: hash, uti: uti.identifier, ext: ext,
                          byteCount: Int64(data.count), filename: filename)

        let target = blobURL(hash: hash, ext: ext)
        guard !FileManager.default.fileExists(atPath: target.path) else { return ref }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            Self.logger.error("Failed to write blob: \(error, privacy: .public)")
        }
        return ref
    }

    /// Copies a file into the store in a single streaming pass, hashing as it goes so
    /// the bytes are never held in memory twice. The write lands on a temporary name
    /// and is renamed only once the final hash is known, so an interrupted import can
    /// never leave a partial file under a valid hash.
    nonisolated func importFile(at url: URL) throws -> BlobRef {
        let meta = FileAccess.metadata(of: url)
        let uti = UTType(meta?.uti ?? "public.data") ?? .data
        let ext = url.pathExtension.isEmpty
            ? Self.fileExtension(for: uti, filename: nil)
            : url.pathExtension

        try FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        let temp = blobsDir.appendingPathComponent(".tmp-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temp.path, contents: nil)

        guard let reader = try? FileHandle(forReadingFrom: url),
              let writer = try? FileHandle(forWritingTo: temp) else {
            try? FileManager.default.removeItem(at: temp)
            throw CocoaError(.fileReadNoSuchFile)
        }
        defer { try? reader.close(); try? writer.close() }

        var hasher = SHA256()
        var total: Int64 = 0
        while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            try writer.write(contentsOf: chunk)
            total += Int64(chunk.count)
        }
        try? writer.close()

        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let target = blobURL(hash: hash, ext: ext)

        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: temp)   // identical bytes already stored
        } else {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: temp, to: target)
        }

        return BlobRef(hash: hash, uti: uti.identifier, ext: ext,
                       byteCount: total, filename: url.lastPathComponent)
    }

    // MARK: - Reading

    /// Resolves to the sharded location, falling back to the pre-shard images/
    /// directory for PNGs written by earlier versions.
    nonisolated func url(for ref: BlobRef) -> URL {
        let primary = blobURL(hash: ref.hash, ext: ref.ext)
        if FileManager.default.fileExists(atPath: primary.path) { return primary }
        let legacy = legacyImagesDir.appendingPathComponent("\(ref.hash).png")
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return primary
    }

    nonisolated func load(_ ref: BlobRef) -> Data? {
        try? Data(contentsOf: url(for: ref))
    }

    nonisolated func exists(_ ref: BlobRef) -> Bool {
        FileManager.default.fileExists(atPath: url(for: ref).path)
    }

    // MARK: - Deleting

    nonisolated func delete(_ ref: BlobRef) {
        try? FileManager.default.removeItem(at: blobURL(hash: ref.hash, ext: ref.ext))
        try? FileManager.default.removeItem(at: legacyImagesDir.appendingPathComponent("\(ref.hash).png"))
    }

    /// Deletes by hash when the extension is unknown — the garbage-collection path,
    /// which only ever learns which hashes are unreferenced.
    nonisolated func delete(hash: String) {
        let shard = blobsDir.appendingPathComponent(Self.shard(for: hash), isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: shard.path) {
            for entry in entries where entry.hasPrefix(hash) {
                try? FileManager.default.removeItem(at: shard.appendingPathComponent(entry))
            }
        }
        try? FileManager.default.removeItem(at: legacyImagesDir.appendingPathComponent("\(hash).png"))
    }

    nonisolated func deleteAll() {
        for dir in [blobsDir, legacyImagesDir] {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            entries.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        try? FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
    }

    // MARK: - Accounting

    /// Every stored blob across both the sharded and legacy directories.
    nonisolated func inventory() -> [BlobUsage] {
        var result: [BlobUsage] = []
        for dir in [blobsDir, legacyImagesDir] {
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
            guard let walker = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: keys) else { continue }
            for case let fileURL as URL in walker {
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                let name = fileURL.deletingPathExtension().lastPathComponent
                guard !name.hasPrefix(".tmp-") else { continue }
                result.append(BlobUsage(hash: name,
                                        url: fileURL,
                                        byteCount: Int64(values?.fileSize ?? 0),
                                        modified: values?.contentModificationDate))
            }
        }
        return result
    }

    /// Total bytes on disk. Walks the tree, so callers must invoke it off the main actor.
    nonisolated func directorySize() -> Int64 {
        inventory().reduce(0) { $0 + $1.byteCount }
    }

    // MARK: - Private

    nonisolated private func blobURL(hash: String, ext: String) -> URL {
        blobsDir
            .appendingPathComponent(Self.shard(for: hash), isDirectory: true)
            .appendingPathComponent(ext.isEmpty ? hash : "\(hash).\(ext)")
    }

    nonisolated private static func shard(for hash: String) -> String {
        String(hash.prefix(2))
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func fileExtension(for uti: UTType, filename: String?) -> String {
        if let filename, !filename.isEmpty {
            let ext = (filename as NSString).pathExtension
            if !ext.isEmpty { return ext }
        }
        return uti.preferredFilenameExtension ?? "dat"
    }
}

// MARK: - PNG-by-hash lookup
//
// ImageCache is keyed by bare hash, since a cached NSImage does not need the rest
// of the reference. Legacy images/<hash>.png resolve through the same fallback.

extension BlobStore {
    nonisolated func loadPNG(hash: String) -> Data? {
        load(BlobRef(hash: hash, uti: UTType.png.identifier, ext: "png", byteCount: 0))
    }
}
