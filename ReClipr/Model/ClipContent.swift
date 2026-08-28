//
//  ClipContent.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
//  Schema v2. Every v1 record — .text, .image(hash), .image(inline data) and
//  .file(url) — still decodes; see init(from:). Encoding always writes v2, so
//  history.json is rewritten on the first save after upgrading.
//

import AppKit
import UniformTypeIdentifiers

/// Coarse classification used by the UI to pick an icon and a preview treatment.
enum ClipKind: String, Sendable {
    case text, richText, image, pdf, audio, video, files, other
}

enum ClipContent: Codable, Equatable, Sendable {
    case text(String)
    /// Kept distinct from .blob so row rendering stays a pattern match rather than a
    /// UTType conformance check on every pass.
    case image(BlobRef)
    /// Pasteboard-only payloads: PDF, RTF, audio, or any other declared type.
    case blob(BlobRef)
    /// One or more files, each either copied into the store or left in place.
    case files([ClipAttachment])

    enum CodingKeys: String, CodingKey {
        // v1 — retained for reading. Never remove these.
        case type, text, imageHash, imageData, fileURL
        // v2
        case v, blob, files
    }

    private enum ContentType: String {
        case text, image, file, blob, files
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .type)

        // An unrecognised type throws so Persistence can drop the single row rather
        // than losing the whole file.
        guard let type = ContentType(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown clip content type '\(raw)'")
        }

        switch type {
        case .text:
            self = .text(try c.decode(String.self, forKey: .text))

        case .image:
            if let ref = try? c.decode(BlobRef.self, forKey: .blob) {
                self = .image(ref)                                  // v2
            } else if let hash = try? c.decode(String.self, forKey: .imageHash) {
                self = .image(Self.pngRef(hash: hash))              // v1 hash
            } else if let data = try? c.decode(Data.self, forKey: .imageData) {
                // v1 inline bytes: move them into the blob store on first load.
                self = .image(BlobStore.shared.save(data, uti: .png))
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .blob, in: c,
                    debugDescription: "Image clip has no blob, imageHash or imageData")
            }

        case .file:
            // v1 stored a single bare path. It becomes a reference attachment —
            // never an inline copy, which at decode time would mean unbounded I/O
            // on launch and would resurrect files the user had deleted.
            let url = try c.decode(URL.self, forKey: .fileURL)
            self = .files([.reference(FileRef(url: url))])

        case .blob:
            self = .blob(try c.decode(BlobRef.self, forKey: .blob))

        case .files:
            self = .files(try c.decode([ClipAttachment].self, forKey: .files))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(2, forKey: .v)
        switch self {
        case .text(let text):
            try c.encode(ContentType.text.rawValue, forKey: .type)
            try c.encode(text, forKey: .text)
        case .image(let ref):
            try c.encode(ContentType.image.rawValue, forKey: .type)
            try c.encode(ref, forKey: .blob)
            // Written for one release so a downgrade still finds its image.
            try c.encode(ref.hash, forKey: .imageHash)
        case .blob(let ref):
            try c.encode(ContentType.blob.rawValue, forKey: .type)
            try c.encode(ref, forKey: .blob)
        case .files(let attachments):
            try c.encode(ContentType.files.rawValue, forKey: .type)
            try c.encode(attachments, forKey: .files)
        }
    }

    /// A v1 image record carries only a hash. Size is left at the unknown sentinel;
    /// the garbage collector stats the file rather than trusting it.
    nonisolated private static func pngRef(hash: String) -> BlobRef {
        BlobRef(hash: hash, uti: UTType.png.identifier, ext: "png", byteCount: 0)
    }
}

// MARK: - Equality

extension ClipContent {
    nonisolated static func == (lhs: ClipContent, rhs: ClipContent) -> Bool {
        switch (lhs, rhs) {
        case let (.text(a), .text(b)):
            return a == b
        case let (.image(a), .image(b)):
            return a.hash == b.hash      // O(64) instead of O(n·bytes)
        case let (.blob(a), .blob(b)):
            return a.hash == b.hash
        case let (.files(a), .files(b)):
            // Order-sensitive, which is correct: copying the same files in a
            // different order is a different clip.
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Search

extension ClipContent {
    nonisolated var searchableText: String {
        switch self {
        case .text(let text):
            return text
        case .image(let ref):
            return ref.filename ?? "[image]"
        case .blob(let ref):
            return [ref.filename, ref.ext].compactMap { $0 }.joined(separator: " ")
        case .files(let attachments):
            return attachments.map(\.filename).joined(separator: " ")
        }
    }
}

// MARK: - UI

extension ClipContent {
    nonisolated var kind: ClipKind {
        switch self {
        case .text:
            return .text
        case .image:
            return .image
        case .blob(let ref):
            return Self.kind(forUTI: ref.uti)
        case .files(let attachments):
            guard attachments.count == 1, let only = attachments.first else { return .files }
            return Self.kind(forUTI: only.uti)
        }
    }

    nonisolated private static func kind(forUTI uti: String) -> ClipKind {
        guard let type = UTType(uti) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .rtf) || type.conforms(to: .rtfd) { return .richText }
        if type.conforms(to: .plainText) { return .text }
        return .other
    }

    /// Icon shown when no thumbnail is available yet, or at all.
    nonisolated var symbolName: String {
        switch kind {
        case .text:     return "text.alignleft"
        case .richText: return "doc.richtext"
        case .image:    return "photo"
        case .pdf:      return "doc.text"
        case .audio:    return "waveform"
        case .video:    return "film"
        case .files:    return "doc.on.doc"
        case .other:    return "doc"
        }
    }

    nonisolated var displayTitle: String {
        switch self {
        case .text(let text):
            return text.count > 400 ? String(text.prefix(400)) + "…" : text
        case .image:
            return "[Image]"
        case .blob(let ref):
            return ref.filename ?? (UTType(ref.uti)?.localizedDescription ?? "Data")
        case .files(let attachments):
            if attachments.count == 1 { return attachments[0].filename }
            return "\(attachments.count) files"
        }
    }

    /// Secondary line: type and size, or a file count for multi-file clips.
    nonisolated var subtitle: String? {
        switch self {
        case .text:
            return nil
        case .image(let ref), .blob(let ref):
            let type = UTType(ref.uti)?.localizedDescription ?? ref.ext.uppercased()
            guard ref.byteCount > 0 else { return type }
            return "\(type) · \(Self.formatBytes(ref.byteCount))"
        case .files(let attachments):
            let total = attachments.reduce(0) { $0 + $1.byteCount }
            let count = attachments.count == 1
                ? (UTType(attachments[0].uti)?.localizedDescription ?? "File")
                : "\(attachments.count) files"
            guard total > 0 else { return count }
            return "\(count) · \(Self.formatBytes(total))"
        }
    }

    /// True when the payload can no longer be produced — a referenced original that
    /// was moved or deleted, or a blob missing from the store. Rows in this state
    /// must not be copyable: putting a dead URL on the pasteboard is worse than
    /// refusing.
    nonisolated var isResourceMissing: Bool {
        switch self {
        case .text:
            return false
        case .image(let ref), .blob(let ref):
            return !BlobStore.shared.exists(ref)
        case .files(let attachments):
            return attachments.contains(where: \.isMissing)
        }
    }

    /// Hashes of every blob this clip owns — the single source of truth for
    /// reference counting during garbage collection.
    nonisolated var blobHashes: [String] {
        switch self {
        case .text:
            return []
        case .image(let ref), .blob(let ref):
            return [ref.hash]
        case .files(let attachments):
            return attachments.compactMap {
                if case .inline(let ref) = $0 { return ref.hash }
                return nil
            }
        }
    }

    /// True when the clip points at files it does not own. Pasting one of these in
    /// Finder copies the original — and ⌥⌘V *moves* it — so the UI must say so
    /// rather than letting it look like a self-contained clip.
    nonisolated var hasLinkedFiles: Bool {
        guard case .files(let attachments) = self else { return false }
        return attachments.contains {
            if case .reference = $0 { return true }
            return false
        }
    }

    /// Paths of files left in place, used for the missing-original badge.
    nonisolated var referencedPaths: [String] {
        guard case .files(let attachments) = self else { return [] }
        return attachments.compactMap {
            if case .reference(let ref) = $0 { return ref.path }
            return nil
        }
    }

    /// Disk cost inside ReClipr's own store. References cost nothing.
    nonisolated var storedByteCount: Int64 {
        switch self {
        case .text:
            return 0
        case .image(let ref), .blob(let ref):
            return ref.byteCount
        case .files(let attachments):
            return attachments.reduce(0) {
                if case .inline(let ref) = $1 { return $0 + ref.byteCount }
                return $0
            }
        }
    }

    var image: NSImage? {
        switch self {
        case .image(let ref):
            return ImageCache.shared.image(for: ref.hash)
        case .blob(let ref):
            guard UTType(ref.uti)?.conforms(to: .image) == true else { return nil }
            return ImageCache.shared.image(for: ref.hash)
        default:
            return nil
        }
    }

    nonisolated private static func formatBytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
