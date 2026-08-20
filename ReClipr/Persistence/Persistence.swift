//
//  Persistence.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "Persistence")

final class Persistence {
    static let shared = Persistence()

    // Computed once at init — avoids running createDirectory on every load/save.
    private let storeURL: URL

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("ReClipr", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("history.json")
    }

    func load() -> [ClipItem] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        do {
            return try JSONDecoder().decode([ClipItem].self, from: data)
        } catch {
            logger.error("Failed to decode history: \(error, privacy: .public)")
            return []
        }
    }

    func save(_ items: [ClipItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error, privacy: .public)")
        }
    }
}
