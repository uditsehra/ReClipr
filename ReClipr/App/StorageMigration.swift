//
//  StorageMigration.swift
//  ReClipr
//
//  Turning the App Sandbox off silently relocates .applicationSupportDirectory:
//  sandboxed it resolves inside ~/Library/Containers/<bundle-id>/Data/…, unsandboxed
//  it resolves to the real ~/Library/Application Support. Without this migration the
//  first unsandboxed launch appears to erase every clip and stored image while
//  remembering every preference, because UserDefaults is not redirected the same way.
//
//  The same relocation applies to UserDefaults: a sandboxed app's preferences live
//  at <container>/Data/Library/Preferences/<bundle-id>.plist, so the user's shortcut,
//  duplicate policy and ignored-apps list do not carry over either. Both are migrated
//  here.
//
//  Must run before ClipboardStore reads history.json or any preference.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReClipr",
                            category: "StorageMigration")

enum StorageMigration {
    private static let completionFlag = "storageMigratedV1"
    private static let preferencesFlag = "preferencesMigratedV1"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: completionFlag) else { return }

        migratePreferences()

        let fm = FileManager.default
        let destination = FileAccess.appSupportDirectory()

        // appSupportDirectory() creates the directory, so "already migrated" is
        // decided by the presence of real data, not by the directory existing.
        if fm.fileExists(atPath: destination.appendingPathComponent("history.json").path) {
            defaults.set(true, forKey: completionFlag)
            return
        }

        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let container = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/ReClipr",
                                   isDirectory: true)

        // No container at all is the normal fresh-install case: nothing to do, ever.
        guard fm.fileExists(atPath: container.path) else {
            defaults.set(true, forKey: completionFlag)
            return
        }

        // Copy rather than move: a downgrade to a sandboxed build still finds its
        // data, and a partial failure leaves the original untouched.
        //
        // The flag is set only on success. A container we can see but cannot read
        // (a revoked permission, a transient I/O error) must be retried on the next
        // launch rather than silently skipped forever.
        do {
            for entry in try fm.contentsOfDirectory(atPath: container.path) {
                let from = container.appendingPathComponent(entry)
                let to = destination.appendingPathComponent(entry)
                guard !fm.fileExists(atPath: to.path) else { continue }
                try fm.copyItem(at: from, to: to)
            }
            defaults.set(true, forKey: completionFlag)
            logger.notice("Migrated clipboard history out of the sandbox container")
        } catch {
            logger.error("Storage migration failed, will retry next launch: \(error, privacy: .public)")
        }
    }
}

// MARK: - Preferences

private extension StorageMigration {

    /// Copies the sandboxed container's preferences into the standard domain.
    /// Existing values always win, so a user who has already configured the
    /// unsandboxed build is never overwritten.
    static func migratePreferences() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: preferencesFlag) else { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let plist = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist")

        guard FileManager.default.fileExists(atPath: plist.path) else {
            defaults.set(true, forKey: preferencesFlag)
            return
        }

        guard let data = try? Data(contentsOf: plist),
              let stored = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = stored as? [String: Any]
        else {
            logger.error("Could not read container preferences, will retry next launch")
            return
        }

        var imported = 0
        for (key, value) in dict where key != completionFlag && key != preferencesFlag {
            guard defaults.object(forKey: key) == nil else { continue }
            defaults.set(value, forKey: key)
            imported += 1
        }

        defaults.set(true, forKey: preferencesFlag)
        logger.notice("Imported \(imported, privacy: .public) preference(s) from the sandbox container")
    }
}
