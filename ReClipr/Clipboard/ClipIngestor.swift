//
//  ClipIngestor.swift
//  ReClipr
//
//  Turns a classified copy into stored content. This is where the size rule lives:
//  below the threshold a file's bytes are copied into ReClipr's store so the clip
//  survives the original being deleted; at or above it, only a reference is kept.
//
//  Runs entirely off the main thread — hashing and copying must never block the
//  pasteboard poll.
//

import Foundation
import OSLog
import UniformTypeIdentifiers

enum ClipIngestor {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "ClipIngestor")

    /// Read straight from UserDefaults: @AppStorage is a SwiftUI property wrapper and
    /// cannot be used from a nonisolated context.
    nonisolated static var inlineLimitBytes: Int64 {
        let stored = UserDefaults.standard.integer(forKey: AppSettings.Key.largeFileThresholdBytes)
        return stored > 0 ? Int64(stored) : 10_000_000
    }

    nonisolated static func makeContent(from classified: ClassifiedCopy) -> (ClipContent, String?)? {
        switch classified {
        case .ignored, .none:
            return nil

        case .text(let text):
            return (.text(text), nil)

        case .image(let png):
            return (.image(BlobStore.shared.save(png, uti: .png)), nil)

        case .data(let data, let uti, let name, let sidecar):
            let type = UTType(uti) ?? .data
            let ref = BlobStore.shared.save(data, uti: type, filename: name)
            return (type.conforms(to: .image) ? .image(ref) : .blob(ref), sidecar)

        case .fileURLs(let urls):
            let attachments = urls.compactMap(attachment(for:))
            guard !attachments.isEmpty else { return nil }
            return (.files(attachments), nil)
        }
    }

    /// Small, readable files are copied in; everything else is referenced. A file we
    /// cannot read is referenced too, so the clip still points somewhere useful.
    nonisolated static func attachment(for url: URL) -> ClipAttachment? {
        let standardized = url.standardizedFileURL
        guard let meta = FileAccess.metadata(of: standardized) else { return nil }

        // Directories are always referenced: copying a tree into the blob store is
        // not what "copy this file" means, and the size is unbounded.
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory)

        guard !isDirectory.boolValue,
              meta.isReadable,
              meta.byteCount > 0,
              meta.byteCount < inlineLimitBytes
        else {
            return .reference(FileRef(url: standardized))
        }

        do {
            return .inline(try BlobStore.shared.importFile(at: standardized))
        } catch {
            logger.error("Falling back to a reference for \(standardized.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            return .reference(FileRef(url: standardized))
        }
    }
}
