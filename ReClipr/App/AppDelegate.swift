//
//  AppDelegate.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import AppKit
import SwiftUI

extension Notification.Name {
    static let closeReCliprPopover   = Notification.Name("ReClipr.closePopover")
    static let openReCliprPreferences = Notification.Name("ReClipr.openPreferences")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipboardStore()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var preferencesWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        applyStoredShortcut()

        NotificationCenter.default.addObserver(
            forName: .closeReCliprPopover,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.popover?.close()
        }

        NotificationCenter.default.addObserver(
            forName: .openReCliprPreferences,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openPreferences()
        }
    }

    // MARK: - Status Item + Popover

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "ReClipr")
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item

        let hc = NSHostingController(rootView: RootView().environmentObject(store))
        hc.view.frame = NSRect(x: 0, y: 0, width: 352, height: 540)

        let pop = NSPopover()
        pop.contentViewController = hc
        pop.contentSize = NSSize(width: 352, height: 540)
        pop.behavior = .transient
        popover = pop
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Preferences Window

    @objc func openPreferences() {
        // Close the popover first so its transient-dismiss doesn't race with the
        // window becoming key, which would cause the preferences window to disappear.
        popover?.close()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.preferencesWindow == nil {
                let vc = NSHostingController(rootView: PreferencesView())
                let window = NSWindow(contentViewController: vc)
                window.title = "Preferences"
                window.styleMask = [.titled, .closable]
                window.setContentSize(NSSize(width: 340, height: 460))
                window.center()
                window.isReleasedWhenClosed = false
                self.preferencesWindow = window
            }
            self.preferencesWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Global Hotkey

    func applyStoredShortcut() {
        let defaults = UserDefaults.standard
        let keyCode = defaults.object(forKey: "shortcutKeyCode") as? Int ?? 9
        let modRaw  = defaults.object(forKey: "shortcutModifiers") as? Int ?? 1_179_648 // ⌘⇧
        GlobalHotkeyManager.shared.register(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(modRaw))
        )
        GlobalHotkeyManager.shared.onActivate = { [weak self] in
            self?.togglePopover()
        }
    }
}
