//
//  PresentationCoordinator.swift
//  ReClipr
//
//  Decides which surface a request to open history should use. Kept separate
//  because the answer depends on two independent settings and must never resolve to
//  "nothing" — with the icon hidden the popover has no anchor to hang from.
//

import AppKit

@MainActor
final class PresentationCoordinator {
    private let settings: AppSettings
    private let menuBar: MenuBarController
    private let overlay: OverlayController

    init(settings: AppSettings, menuBar: MenuBarController, overlay: OverlayController) {
        self.settings = settings
        self.menuBar = menuBar
        self.overlay = overlay
    }

    func toggleHistory() {
        if settings.openAsOverlay, FeatureGate.isUnlocked(.overlay) {
            menuBar.closePopover()
            overlay.toggle()
            return
        }

        if menuBar.isEnabled {
            menuBar.togglePopover()
            return
        }

        // No icon to anchor a popover to — fall back to the overlay rather than
        // doing nothing, which is what the old guard-and-return did.
        overlay.toggle()
    }

    func dismissAll() {
        menuBar.closePopover()
        overlay.hide()
    }

    /// Which surface was open when a window took over, so Escape can put it back.
    private var surfaceToRestore: ClipSurface?

    /// Clears the way for a window that needs to become key, remembering what it
    /// displaced.
    func prepareForWindowPresentation() {
        if overlay.isVisible {
            surfaceToRestore = .overlay
            overlay.hideForWindowPresentation()
        } else if menuBar.isPopoverShown {
            surfaceToRestore = .popover
        } else {
            surfaceToRestore = nil
        }
        menuBar.closePopover()
    }

    /// Reopens whatever the window displaced. Dismissing Preferences with Escape
    /// should feel like stepping back, not like quitting out of the app entirely.
    func restoreSurfaceAfterWindow() {
        guard let surface = surfaceToRestore else { return }
        surfaceToRestore = nil

        // Next runloop turn: the window is still closing, and showing a panel mid
        // teardown loses key status.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch surface {
            case .overlay:
                self.overlay.show()
            case .popover:
                if !self.menuBar.isPopoverShown { self.menuBar.togglePopover() }
            }
        }
    }

    /// The window was dismissed deliberately rather than stepped back from.
    func forgetDisplacedSurface() {
        surfaceToRestore = nil
    }
}
