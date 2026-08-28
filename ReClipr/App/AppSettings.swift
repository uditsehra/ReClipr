//
//  AppSettings.swift
//  ReClipr
//
//  One observable home for every preference, replacing @AppStorage scattered across
//  views. Two things this buys beyond tidiness:
//
//  1. Defaults are supplied through UserDefaults.register(defaults:), which never
//     persists them. That is what lets the default shortcut move from ⌘⇧V to ⌥⌘C
//     without touching a shortcut the user deliberately recorded — an unset key
//     picks up the new default, a stored key keeps its value.
//  2. Consumers can observe a single property instead of UserDefaults.didChange-
//     Notification, which fires for every write anywhere in the app.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    // MARK: Keys

    enum Key {
        // Referenced from nonisolated contexts, so each key is explicitly nonisolated.
        nonisolated static let showMenuBarIcon = "showMenuBarIcon"
        nonisolated static let openAsOverlay = "openAsOverlay"
        nonisolated static let shortcutKeyCode = "shortcutKeyCode"
        nonisolated static let shortcutModifiers = "shortcutModifiers"
        nonisolated static let shortcutDisplay = "shortcutDisplay"
        nonisolated static let maxHistoryCount = "maxHistoryCount"
        nonisolated static let duplicatePolicy = "duplicatePolicy"
        nonisolated static let duplicateInterval = "duplicateInterval"
        nonisolated static let ignoredApps = "ignoredApps"
        nonisolated static let launchAtLogin = "launchAtLogin"
        nonisolated static let watchScreenshots = "watchScreenshots"
        nonisolated static let copyScreenshotToClipboard = "copyScreenshotToClipboard"
        nonisolated static let largeFileThresholdBytes = "largeFileThresholdBytes"
        nonisolated static let blobBudgetBytes = "blobBudgetBytes"
        nonisolated static let overlayBackground = "overlayBackground"
        nonisolated static let overlayDimming = "overlayDimming"
        nonisolated static let overlayScrim = "overlayScrim"
        nonisolated static let overlayPlacement = "overlayPlacement"
        nonisolated static let overlayOriginX = "overlayOriginX"
        nonisolated static let overlayOriginY = "overlayOriginY"
    }

    /// ⌥⌘C — keyCode 8 is 'C'; 1_572_864 is .command (1<<20) | .option (1<<19).
    static let defaultShortcutKeyCode = 8
    static let defaultShortcutModifiers = 1_572_864
    static let defaultShortcutDisplay = "⌥⌘C"

    static let registeredDefaults: [String: Any] = [
        Key.showMenuBarIcon: true,
        Key.openAsOverlay: false,
        Key.shortcutKeyCode: defaultShortcutKeyCode,
        Key.shortcutModifiers: defaultShortcutModifiers,
        Key.shortcutDisplay: defaultShortcutDisplay,
        Key.maxHistoryCount: 200,
        Key.duplicatePolicy: DuplicatePolicy.none.rawValue,
        Key.duplicateInterval: 300.0,
        Key.ignoredApps: "com.apple.keychainaccess",
        Key.launchAtLogin: false,
        Key.watchScreenshots: true,
        Key.copyScreenshotToClipboard: true,
        Key.largeFileThresholdBytes: 10_000_000,
        Key.blobBudgetBytes: 2_000_000_000,
        Key.overlayBackground: "glass",
        Key.overlayDimming: 0.25,
        Key.overlayScrim: OverlayScrimStyle.dim.rawValue,
        Key.overlayPlacement: OverlayPlacement.center.rawValue,
    ]

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: registeredDefaults)
    }

    // MARK: Presentation

    @Published var showMenuBarIcon: Bool { didSet { write(Key.showMenuBarIcon, showMenuBarIcon) } }
    @Published var openAsOverlay: Bool { didSet { write(Key.openAsOverlay, openAsOverlay) } }

    // MARK: Shortcut

    @Published var shortcutKeyCode: Int { didSet { write(Key.shortcutKeyCode, shortcutKeyCode) } }
    @Published var shortcutModifiers: Int { didSet { write(Key.shortcutModifiers, shortcutModifiers) } }
    @Published var shortcutDisplay: String { didSet { write(Key.shortcutDisplay, shortcutDisplay) } }

    /// Set when Carbon refuses the combination, usually because another app owns it.
    /// Not persisted — it describes this launch only.
    @Published var shortcutRegistrationFailed = false

    var hasShortcut: Bool { shortcutKeyCode >= 0 }

    // MARK: History

    @Published var maxHistoryCount: Int { didSet { write(Key.maxHistoryCount, maxHistoryCount) } }
    @Published var duplicatePolicyRaw: String { didSet { write(Key.duplicatePolicy, duplicatePolicyRaw) } }
    @Published var duplicateInterval: Double { didSet { write(Key.duplicateInterval, duplicateInterval) } }
    @Published var ignoredAppsRaw: String { didSet { write(Key.ignoredApps, ignoredAppsRaw) } }
    @Published var launchAtLogin: Bool { didSet { write(Key.launchAtLogin, launchAtLogin) } }

    var duplicatePolicy: DuplicatePolicy {
        DuplicatePolicy(rawValue: duplicatePolicyRaw) ?? .none
    }

    var ignoredApps: Set<String> {
        Set(ignoredAppsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    // MARK: Capture and storage

    @Published var watchScreenshots: Bool { didSet { write(Key.watchScreenshots, watchScreenshots) } }
    @Published var copyScreenshotToClipboard: Bool {
        didSet { write(Key.copyScreenshotToClipboard, copyScreenshotToClipboard) }
    }
    @Published var largeFileThresholdBytes: Int {
        didSet { write(Key.largeFileThresholdBytes, largeFileThresholdBytes) }
    }
    /// Zero means unlimited.
    @Published var blobBudgetBytes: Int { didSet { write(Key.blobBudgetBytes, blobBudgetBytes) } }

    // MARK: Overlay appearance

    @Published var overlayBackgroundRaw: String {
        didSet { write(Key.overlayBackground, overlayBackgroundRaw) }
    }
    /// How strongly a wallpaper is dimmed behind the content, 0…0.8.
    @Published var overlayDimming: Double { didSet { write(Key.overlayDimming, overlayDimming) } }

    @Published var overlayScrimRaw: String { didSet { write(Key.overlayScrim, overlayScrimRaw) } }
    @Published var overlayPlacementRaw: String { didSet { write(Key.overlayPlacement, overlayPlacementRaw) } }

    var overlayScrim: OverlayScrimStyle {
        get { OverlayScrimStyle(rawValue: overlayScrimRaw) ?? .dim }
        set { overlayScrimRaw = newValue.rawValue }
    }

    var overlayPlacement: OverlayPlacement {
        get { OverlayPlacement(rawValue: overlayPlacementRaw) ?? .center }
        set { overlayPlacementRaw = newValue.rawValue }
    }

    /// Last dragged position. Written directly rather than through @Published: it
    /// changes continuously while dragging and no view needs to react.
    var overlayOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: Key.overlayOriginX) != nil else { return nil }
            return CGPoint(x: defaults.double(forKey: Key.overlayOriginX),
                           y: defaults.double(forKey: Key.overlayOriginY))
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.overlayOriginX)
                defaults.removeObject(forKey: Key.overlayOriginY)
                return
            }
            defaults.set(newValue.x, forKey: Key.overlayOriginX)
            defaults.set(newValue.y, forKey: Key.overlayOriginY)
        }
    }

    var overlayBackground: OverlayBackground {
        get { OverlayBackground(storageValue: overlayBackgroundRaw) }
        set { overlayBackgroundRaw = newValue.storageValue }
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.registerDefaults(in: defaults)

        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        openAsOverlay = defaults.bool(forKey: Key.openAsOverlay)
        shortcutKeyCode = defaults.integer(forKey: Key.shortcutKeyCode)
        shortcutModifiers = defaults.integer(forKey: Key.shortcutModifiers)
        shortcutDisplay = defaults.string(forKey: Key.shortcutDisplay) ?? Self.defaultShortcutDisplay
        maxHistoryCount = defaults.integer(forKey: Key.maxHistoryCount)
        duplicatePolicyRaw = defaults.string(forKey: Key.duplicatePolicy) ?? DuplicatePolicy.none.rawValue
        duplicateInterval = defaults.double(forKey: Key.duplicateInterval)
        ignoredAppsRaw = defaults.string(forKey: Key.ignoredApps) ?? ""
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        watchScreenshots = defaults.bool(forKey: Key.watchScreenshots)
        copyScreenshotToClipboard = defaults.bool(forKey: Key.copyScreenshotToClipboard)
        largeFileThresholdBytes = defaults.integer(forKey: Key.largeFileThresholdBytes)
        blobBudgetBytes = defaults.integer(forKey: Key.blobBudgetBytes)
        overlayBackgroundRaw = defaults.string(forKey: Key.overlayBackground) ?? "glass"
        overlayDimming = defaults.double(forKey: Key.overlayDimming)
        overlayScrimRaw = defaults.string(forKey: Key.overlayScrim) ?? OverlayScrimStyle.dim.rawValue
        overlayPlacementRaw = defaults.string(forKey: Key.overlayPlacement) ?? OverlayPlacement.center.rawValue
    }

    // MARK: Shortcut helpers

    func recordShortcut(keyCode: Int, modifiers: Int, display: String) {
        shortcutKeyCode = keyCode
        shortcutModifiers = modifiers
        shortcutDisplay = display
    }

    /// Clearing the shortcut while the menu bar icon is hidden would leave no way to
    /// open ReClipr at all, so the icon is restored rather than blocking the user.
    /// Returns true when the icon had to be turned back on.
    @discardableResult
    func clearShortcut() -> Bool {
        shortcutKeyCode = -1
        shortcutModifiers = 0
        shortcutDisplay = "None"
        shortcutRegistrationFailed = false

        guard !showMenuBarIcon else { return false }
        showMenuBarIcon = true
        return true
    }

    private func write(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
    }
}
