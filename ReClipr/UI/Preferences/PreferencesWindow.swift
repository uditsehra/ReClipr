//
//  PreferencesWindow.swift
//  ReClipr
//
//  A titled window ignores Escape by default. For a settings window you open with
//  ⌘, and glance at, dismissing the same way you dismiss everything else in the app
//  is worth the twelve lines.
//

import AppKit

final class PreferencesWindow: NSWindow {
    /// Called when Escape dismisses the window, so the caller can put back whatever
    /// this window displaced. Not called when the window is closed any other way —
    /// clicking the close button means "done", not "go back".
    var onCancel: (() -> Void)?

    /// Sent up the responder chain when Escape is pressed.
    override func cancelOperation(_ sender: Any?) {
        let handler = onCancel
        close()
        handler?()
    }

    /// A borderless-ish utility window still needs to accept key input for the
    /// controls inside it.
    override var canBecomeKey: Bool { true }
}
