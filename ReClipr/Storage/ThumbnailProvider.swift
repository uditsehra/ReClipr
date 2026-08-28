//
//  ThumbnailProvider.swift
//  ReClipr
//
//  ImageCache is the right tool for an image clip and the wrong one for everything
//  else — a 200-page PDF is not an NSImage. QuickLook renders a preview for any type
//  the system understands; this caches the result on disk so scrolling a long
//  history never re-renders, and hands back an instant type icon in the meantime.
//
//  Generation is always off the main actor: QLThumbnailGenerator on a couple of
//  hundred rows will visibly stutter otherwise.
//

import AppKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

final class ThumbnailProvider {
    nonisolated static let shared = ThumbnailProvider()

    nonisolated private static let pixelSize: CGFloat = 256

    nonisolated(unsafe) private let memory: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    private let directory: URL

    private init() {
        directory = FileAccess.appSupportDirectory().appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Type icons

    /// Available immediately, so a row never renders empty while QuickLook works.
    nonisolated static func icon(forUTI uti: String) -> NSImage {
        if let type = UTType(uti) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    // MARK: - Thumbnails

    nonisolated func cached(for key: String) -> NSImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let url = directory.appendingPathComponent("\(key).png")
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    /// Renders a preview of a stored blob. Images are already handled by ImageCache,
    /// so this is for PDFs, audio, video and documents.
    nonisolated func thumbnail(for ref: BlobRef) async -> NSImage? {
        if let hit = cached(for: ref.hash) { return hit }
        let source = BlobStore.shared.url(for: ref)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        return await generate(from: source, key: ref.hash)
    }

    /// Renders a preview of a file left in place. Keyed by path and modification
    /// date, so replacing the file produces a fresh preview rather than a stale one.
    nonisolated func thumbnail(for ref: FileRef) async -> NSImage? {
        guard ref.exists else { return nil }
        let stamp = ref.modified.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        let key = Self.digest("\(ref.path)-\(stamp)")
        if let hit = cached(for: key) { return hit }
        return await generate(from: ref.url, key: key)
    }

    nonisolated private func generate(from url: URL, key: String) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: Self.pixelSize, height: Self.pixelSize),
            scale: 2,
            representationTypes: .thumbnail)

        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }

        let image = rep.nsImage
        memory.setObject(image, forKey: key as NSString)

        // Persist so a relaunch does not re-render the whole history.
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("\(key).png"), options: .atomic)
        }
        return image
    }

    // MARK: - Invalidation

    nonisolated func invalidate(_ key: String) {
        memory.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(key).png"))
    }

    nonisolated func invalidateAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    nonisolated private static func digest(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return String(hash, radix: 16)
    }
}
