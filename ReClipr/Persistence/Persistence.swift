//
//  Persistence.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "Persistence")

/// Decodes an element, or nothing. Used so one malformed clip cannot take the whole
/// history with it — the previous [ClipItem] decode returned [] for the entire file
/// if any single record failed, which a schema change makes considerably likelier.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        // Consumes exactly one element either way, so the unkeyed container stays
        // correctly positioned for the next.
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

final class Persistence {
    static let shared = Persistence()

    private let storeURL: URL
    private let backupURL: URL
    private static let backupFlag = "didBackupV1History"

    /// Defaults to the app's real Application Support directory. Tests pass a
    /// temporary one — without that, running the suite loads and mutates the user's
    /// actual clipboard history.
    init(directory: URL? = nil) {
        let dir = directory ?? FileAccess.appSupportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("history.json")
        backupURL = dir.appendingPathComponent("history.v1.backup.json")
    }

    func load() -> [ClipItem] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([Lenient<ClipItem>].self, from: data)
            let items = decoded.compactMap(\.value)
            let dropped = decoded.count - items.count
            if dropped > 0 {
                logger.error("Dropped \(dropped, privacy: .public) unreadable clip(s) while loading history")
            }
            return items
        } catch {
            logger.error("Failed to decode history: \(error, privacy: .public)")
            return []
        }
    }

    func save(_ items: [ClipItem]) {
        backupV1IfNeeded()
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error, privacy: .public)")
        }
    }

    /// Snapshots the pre-v2 file once, immediately before the first write that would
    /// overwrite it. Encoding is one-way, so this is the only route back.
    private func backupV1IfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.backupFlag) else { return }
        defer { defaults.set(true, forKey: Self.backupFlag) }

        guard FileManager.default.fileExists(atPath: storeURL.path),
              !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            try FileManager.default.copyItem(at: storeURL, to: backupURL)
            logger.notice("Backed up v1 history before first v2 write")
        } catch {
            logger.error("Could not back up v1 history: \(error, privacy: .public)")
        }
    }
}
