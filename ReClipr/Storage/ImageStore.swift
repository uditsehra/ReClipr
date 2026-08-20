//
//  ImageStore.swift
//  ReClipr
//
//  Content-addressable PNG storage. Files are keyed by SHA-256 hash so identical
//  images share a single file, and hash comparison replaces byte-for-byte Data ==.
//

import CryptoKit
import Foundation

final class ImageStore {
    nonisolated static let shared = ImageStore()

    // Computed once at init — avoids running createDirectory on every I/O call.
    private let imagesDir: URL

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("ReClipr/images", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        imagesDir = dir
    }

    // MARK: - Public API (nonisolated — safe to call from any thread / actor)

    nonisolated func save(_ pngData: Data) -> String {
        let hash = sha256(pngData)
        let url = imagesDir.appendingPathComponent("\(hash).png")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? pngData.write(to: url, options: .atomic)
        }
        return hash
    }

    nonisolated func load(_ hash: String) -> Data? {
        try? Data(contentsOf: imagesDir.appendingPathComponent("\(hash).png"))
    }

    nonisolated func delete(_ hash: String) {
        try? FileManager.default.removeItem(
            at: imagesDir.appendingPathComponent("\(hash).png")
        )
    }

    nonisolated func deleteAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: imagesDir, includingPropertiesForKeys: nil
        ) else { return }
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: - Private

    nonisolated private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
