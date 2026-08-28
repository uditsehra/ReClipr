//
//  MenuBarController.swift
//  ReClipr
//
//  Owns the status item and its popover. The item can be created and destroyed at
//  runtime, because showing it is now a preference.
//

import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let store: ClipboardStore
    private let actions: SurfaceActions

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var backgroundView: OverlayBackgroundView?
    private var keyMonitor: Any?

    /// Owned here rather than created inside the SwiftUI view, so the key monitor can
    /// route into the same instance the popover is rendering.
    private lazy var model = ClipHistoryModel(
        store: store, settings: AppSettings.shared, metrics: .popover)

    /// Invoked on a plain left-click. Routed through the coordinator so the click
    /// opens whichever surface the user configured.
    var onPrimaryClick: (() -> Void)?

    var isEnabled: Bool { statusItem != nil }

    init(store: ClipboardStore, actions: SurfaceActions) {
        self.store = store
        self.actions = actions
        super.init()
    }

    // MARK: - Status item

    func setEnabled(_ enabled: Bool) {
        if enabled, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "ReClipr")
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem = item
        } else if !enabled, let item = statusItem {
            popover?.close()
            // Must go through the status bar; simply dropping the reference leaves a
            // gap in the menu bar.
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isSecondary {
            showContextMenu()
        } else {
            onPrimaryClick?()
        }
    }

    /// Preferences and Quit must stay reachable whenever the icon is visible,
    /// whatever the left-click opens.
    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open ReClipr", action: #selector(menuOpen), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(menuPreferences), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Clear History", action: #selector(menuClear), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ReClipr", action: #selector(menuQuit), keyEquivalent: "q")
            .target = self

        // Attaching the menu to the item would make it swallow left-clicks too.
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.height + 4),
                   in: button)
    }

    @objc private func menuOpen() { onPrimaryClick?() }
    @objc private func menuPreferences() { actions.openPreferences() }
    @objc private func menuClear() { store.clearAll() }
    @objc private func menuQuit() { actions.quit() }

    // MARK: - Popover

    var isPopoverShown: Bool { popover?.isShown ?? false }

    func togglePopover() {
        guard let button = statusItem?.button else { return }
        let pop = existingPopover()
        if pop.isShown {
            pop.close()
        } else {
            let settings = AppSettings.shared
            backgroundView?.apply(settings.overlayBackground,
                                  scrimStyle: settings.overlayScrim,
                                  dimming: settings.overlayDimming,
                                  screen: NSScreen.main)
            backgroundView?.startPlaybackIfNeeded()
            installKeyMonitor()
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // A status-item popover genuinely needs the app active to accept typing.
            // The overlay deliberately does not do this.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func closePopover() { popover?.close() }

    private func existingPopover() -> NSPopover {
        if let popover { return popover }

        model.onActivate = { [weak self] item in
            guard let self else { return }
            self.store.copyToClipboard(item)
            withAnimation(.easeIn(duration: 0.1)) { self.model.copiedItemID = item.id }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.model.copiedItemID = nil
                self.actions.dismiss()
            }
        }
        model.onDismiss = { [weak self] in self?.actions.dismiss() }
        model.onOpenPreferences = { [weak self] in self?.actions.openPreferences() }

        let hosting = NSHostingView(
            rootView: PopoverRootView(model: model)
                .environmentObject(store)
                .environmentObject(actions)
                .environmentObject(AppSettings.shared))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        // Same background machinery as the overlay, so a chosen theme applies to both
        // surfaces rather than only the floating one.
        let background = OverlayBackgroundView(frame: NSRect(x: 0, y: 0, width: 352, height: 540))
        background.contentContainer.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.contentContainer.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.contentContainer.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.contentContainer.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.contentContainer.bottomAnchor),
        ])
        backgroundView = background

        let controller = NSViewController()
        controller.view = background
        controller.view.frame = NSRect(x: 0, y: 0, width: 352, height: 540)

        let pop = NSPopover()
        pop.contentViewController = controller
        pop.contentSize = NSSize(width: 352, height: 540)
        pop.behavior = .transient
        pop.delegate = self
        popover = pop
        return pop
    }

    // MARK: - Keyboard

    /// An NSPopover's window cannot be subclassed, so key handling goes through a
    /// local monitor installed only while the popover is showing. Command
    /// combinations are included here because, unlike the panel, there is no
    /// performKeyEquivalent to override.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPopoverShown else { return event }
            if event.keyCode == 53 {                       // escape
                if self.model.handleEscape() { return nil }
                self.actions.dismiss()
                return nil
            }
            return self.model.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

// MARK: - NSPopoverDelegate

extension MenuBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        removeKeyMonitor()
        // Decoding video behind a closed popover is the same waste as behind a
        // hidden panel.
        backgroundView?.pausePlayback()
    }
}
