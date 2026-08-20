//
//  ImageCache.swift
//  ReClipr
//
//  NSImage LRU cache backed by NSCache. Loads from ImageStore on miss.
//  NSCache is thread-safe, so all methods are nonisolated.
//

import AppKit

final class ImageCache {
    static let shared = ImageCache()

    // NSCache is documented thread-safe — nonisolated(unsafe) removes actor isolation
    // while preserving Sendable correctness for the reference type.
    nonisolated(unsafe) private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 50 * 1024 * 1024  // 50 MB cap
        return c
    }()

    private init() {}

    nonisolated func image(for hash: String) -> NSImage? {
        let key = hash as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = ImageStore.shared.load(hash),
              let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: key, cost: data.count)
        return img
    }

    nonisolated func invalidate(_ hash: String) {
        cache.removeObject(forKey: hash as NSString)
    }

    nonisolated func invalidateAll() {
        cache.removeAllObjects()
    }
}
