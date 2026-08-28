//
//  AppDelegate.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
//  Ownership and wiring only; each surface lives in its own controller.
//

import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Lazy, not eager: stored-property initialisers run before
    // applicationWillFinishLaunching, and StorageMigration must complete before
    // ClipboardStore reads history.json.
    private(set) lazy var store = ClipboardStore()

    private let settings = AppSettings.shared
    private lazy var actions = SurfaceActions()
    private lazy var menuBar = MenuBarController(store: store, actions: actions)
    private lazy var overlay = OverlayController(store: store, actions: actions)
    private lazy var coordinator = PresentationCoordinator(
        settings: settings, menuBar: menuBar, overlay: overlay)

    private var preferencesWindow: PreferencesWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Registered defaults must exist before anything reads a preference, and the
        // migration must precede both. Neither touches the lazy `store`.
        AppSettings.registerDefaults()
        StorageMigration.runIfNeeded()
        TempExport.shared.purge()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        actions.dismiss = { [weak self] in self?.coordinator.dismissAll() }
        actions.openPreferences = { [weak self] in self?.openPreferences() }

        menuBar.onPrimaryClick = { [weak self] in self?.coordinator.toggleHistory() }
        menuBar.setEnabled(settings.showMenuBarIcon)

        settings.$showMenuBarIcon
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.menuBar.setEnabled(enabled) }
            .store(in: &cancellables)

        settings.$shortcutKeyCode
            .combineLatest(settings.$shortcutModifiers)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.applyStoredShortcut() }
            .store(in: &cancellables)

        applyStoredShortcut()

        // macOS does not announce a change to the screenshot location, so re-resolve
        // whenever the user comes back to us.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.refreshScreenshotWatch() }
        }
    }

    /// Double-clicking the app while it is already running is the most discoverable
    /// way back in if the icon is hidden and the shortcut was cleared.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openPreferences()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "reclipr" {
            switch url.host {
            case "preferences": openPreferences()
            case "show":        coordinator.toggleHistory()
            default:            break
            }
        }
    }

    // MARK: - Preferences

    @objc func openPreferences() {
        // Close whatever is showing first, so its dismissal does not race the window
        // becoming key.
        coordinator.prepareForWindowPresentation()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.preferencesWindow == nil {
                let controller = NSHostingController(
                    rootView: PreferencesView()
                        .environmentObject(self.store)
                        .environmentObject(AppSettings.shared))
                let window = PreferencesWindow(contentViewController: controller)
                window.title = "Preferences"
                window.styleMask = [.titled, .closable]
                window.setContentSize(NSSize(width: 460, height: 460))
                window.center()
                window.isReleasedWhenClosed = false
                window.onCancel = { [weak self] in
                    self?.coordinator.restoreSurfaceAfterWindow()
                }
                self.preferencesWindow = window
            }
            self.preferencesWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Global Hotkey

    func applyStoredShortcut() {
        let ok = GlobalHotkeyManager.shared.register(
            keyCode: settings.shortcutKeyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(settings.shortcutModifiers)))
        settings.shortcutRegistrationFailed = settings.hasShortcut && !ok

        GlobalHotkeyManager.shared.onActivate = { [weak self] in
            self?.coordinator.toggleHistory()
        }
    }
}
