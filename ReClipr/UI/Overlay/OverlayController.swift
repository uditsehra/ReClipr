//
//  OverlayController.swift
//  ReClipr
//
//  Shows and hides the floating panel, and — the part everything else depends on —
//  makes sure the app the user came from gets focus back, so their ⌘V pastes where
//  they expect.
//
//  The primary mechanism is restraint: a non-activating panel becoming key does not
//  activate ReClipr, so AppKit normally hands focus straight back when the panel
//  orders out. The explicit reactivation below is a fallback for when it does not.
//

import AppKit
import SwiftUI

@MainActor
final class OverlayController: NSObject, NSWindowDelegate {
    private let store: ClipboardStore
    private let actions: SurfaceActions
    private let router = OverlayKeyRouter()

    private var panel: ClipboardPanel?
    private var backgroundView: OverlayBackgroundView?
    private lazy var model = ClipHistoryModel(
        store: store, settings: AppSettings.shared, metrics: .overlay)
    private weak var previousApp: NSRunningApplication?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    /// Set while Preferences is being opened from the overlay, so the panel losing
    /// key status does not read as a click-outside dismissal.
    private var isSuppressingResignKey = false

    /// Set while show() places the panel, so the resulting windowDidMove is not
    /// mistaken for the user dragging it.
    private var isPositioningProgrammatically = false

    var isVisible: Bool { panel?.isVisible ?? false }

    init(store: ClipboardStore, actions: SurfaceActions) {
        self.store = store
        self.actions = actions
        super.init()
    }

    // MARK: - NSWindowDelegate

    /// Records where the user dragged the panel to, but only while it is on screen —
    /// AppKit also emits this during the programmatic placement in show().
    func windowDidMove(_ notification: Notification) {
        guard let panel, panel.isVisible, !isPositioningProgrammatically else { return }
        guard AppSettings.shared.overlayPlacement == .remember else { return }
        AppSettings.shared.overlayOrigin = panel.frame.origin
    }

    // MARK: - Presentation

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }

        capturePreviousApp()

        let panel = existingPanel()
        position(panel)

        // Re-applied on every show: the theme, the wallpaper, or the screen the
        // panel opens on may all have changed since last time.
        let settings = AppSettings.shared
        backgroundView?.apply(settings.overlayBackground,
                              scrimStyle: settings.overlayScrim,
                              dimming: settings.overlayDimming,
                              screen: targetScreen())
        backgroundView?.startPlaybackIfNeeded()

        panel.orderFrontRegardless()
        // Not makeKeyAndOrderFront: that would activate the app.
        panel.makeKey()
        installDismissMonitors()
    }

    func hide(restoreFocus: Bool = true) {
        removeDismissMonitors()
        // Decoding 4K video behind a hidden window would drain the battery for
        // nothing.
        backgroundView?.pausePlayback()
        panel?.orderOut(nil)

        guard restoreFocus, let target = previousApp else {
            previousApp = nil
            return
        }
        previousApp = nil

        // Only step in if AppKit has not already restored focus. Reactivating
        // unconditionally causes a visible flicker, and can drag the user back from
        // a third app they clicked into — or across Spaces.
        DispatchQueue.main.async {
            guard !target.isTerminated,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier
            else { return }
            target.activate()
        }
    }

    // MARK: - Panel

    private func existingPanel() -> ClipboardPanel {
        if let panel { return panel }

        let created = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520))

        // The model is a reference type, so the key-handling closures below stay
        // valid outside SwiftUI's body evaluation — which is exactly where the
        // previous struct-capturing version crashed.
        model.onActivate = { [weak self] item in
            self?.store.copyToClipboard(item)
            // Dismiss at once: the panel holds key focus, so any delay means a quick
            // ⌘V lands in our own search field.
            self?.hide()
        }
        model.onDismiss = { [weak self] in self?.hide() }
        model.onOpenPreferences = { [weak self] in self?.actions.openPreferences() }

        let root = OverlayRootView(model: model)
            .environmentObject(store)
            .environmentObject(actions)
            .environmentObject(router)
            .environmentObject(AppSettings.shared)

        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let background = OverlayBackgroundView(frame: created.contentRect(forFrameRect: created.frame))
        background.contentContainer.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.contentContainer.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.contentContainer.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.contentContainer.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.contentContainer.bottomAnchor),
        ])
        created.contentView = background
        backgroundView = background

        created.onKeyEvent = { [weak self] event in
            guard let self else { return false }
            if event.keyCode == 53 {                      // escape
                // Unwinds a selection, then a search, then the window.
                if self.model.handleEscape() { return true }
                self.hide()
                return true
            }
            return self.model.handleKey(event)
        }
        created.onCancel = { [weak self] in self?.hide() }

        created.delegate = self
        panel = created
        return created
    }

    /// Centred on the screen under the pointer, a little above centre. That screen is
    /// where the user is looking; the active window's screen cannot be queried
    /// without the Accessibility APIs this app deliberately avoids.
    /// The screen under the pointer — where the user is looking. The active
    /// window's screen is not queryable without the Accessibility APIs this app
    /// deliberately avoids.
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func position(_ panel: ClipboardPanel) {
        guard let visible = targetScreen()?.visibleFrame else { return }

        isPositioningProgrammatically = true
        defer { isPositioningProgrammatically = false }

        let width = min(680, visible.width - 80)
        let height = min(560, visible.height - 120)

        // Restore a remembered position, but only if it still lands on a screen that
        // exists — displays get unplugged and resolutions change.
        if AppSettings.shared.overlayPlacement == .remember,
           let origin = AppSettings.shared.overlayOrigin {
            let candidate = NSRect(x: origin.x, y: origin.y, width: width, height: height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(candidate) }) {
                panel.setFrame(candidate, display: true)
                return
            }
        }

        let x = visible.midX - width / 2
        // 28% down reads as centred; true centre looks low.
        let y = visible.maxY - height - (visible.height * 0.28 - height / 2).clamped(to: 20...visible.height)

        panel.setFrame(NSRect(x: x, y: max(visible.minY + 20, y), width: width, height: height),
                       display: true)
    }

    // MARK: - Focus

    private func capturePreviousApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        // Re-pressing the shortcut while the panel is key would otherwise record
        // ReClipr itself, and restoring focus would become a no-op.
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        previousApp = app
    }

    // MARK: - Dismissal

    private func installDismissMonitors() {
        removeDismissMonitors()

        // Mouse-type global monitors need no Accessibility permission; only keyboard
        // ones do. This covers clicks that do not change key window, such as on the
        // desktop or our own status item.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, !self.isSuppressingResignKey else { return }
            self.hide()
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { event in event }
    }

    private func removeDismissMonitors() {
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localClickMonitor { NSEvent.removeMonitor(m); localClickMonitor = nil }
    }

    /// Dismisses without handing focus back, so a window we are about to open
    /// becomes key instead of the app underneath.
    func hideForWindowPresentation() {
        isSuppressingResignKey = true
        hide(restoreFocus: false)
        DispatchQueue.main.async { [weak self] in
            self?.isSuppressingResignKey = false
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
