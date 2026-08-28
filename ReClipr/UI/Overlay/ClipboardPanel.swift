//
//  ClipboardPanel.swift
//  ReClipr
//
//  The floating history window.
//
//  .nonactivatingPanel is the load-bearing choice: it lets the panel take key focus
//  so the search field accepts typing, without making ReClipr the active
//  application. The app the user came from stays frontmost, which is what allows
//  their ⌘V to land there after they pick something.
//

import AppKit

final class ClipboardPanel: NSPanel {
    /// Return true to consume the event. Called before the responder chain sees it.
    var onKeyEvent: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        // Appears over a full-screen app without switching Spaces. Deliberately not
        // .statusBar or .screenSaver: those sit above the menu bar and misbehave
        // under Stage Manager.
        //
        // .transient rather than .stationary: a stationary window stays put during
        // Mission Control and gets drawn over by other windows' app icons and
        // labels. Transient hides it for the duration instead, which is the right
        // behaviour for a dismiss-on-click HUD.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false        // dismissal is handled explicitly
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        // Draggable by any part of the background. Cards and buttons consume their
        // own mouse events, so this only picks up drags on empty chrome.
        isMovableByWindowBackground = true
    }

    // Borderless windows refuse key status unless this is overridden.
    override var canBecomeKey: Bool { true }
    // Never take main-window status; that belongs to the app the user is working in.
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Intercepts keys before the responder chain. Overriding keyDown would be too
    /// late: the focused search field consumes arrows and Return first, which is
    /// exactly the case that needs handling.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyEvent?(event) == true { return }
        super.sendEvent(event)
    }

    /// Command combinations never reach sendEvent: NSApplication dispatches them as
    /// key equivalents first, and SwiftUI installs a default main menu whose
    /// Edit ▸ Select All claims ⌘A. Without this, ⌘A selected the text in the search
    /// field instead of selecting every clip.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEvent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}
