//
//  SurfaceActions.swift
//  ReClipr
//
//  What "close" and "open preferences" mean depends on which surface is showing.
//  Injecting them removes the NotificationCenter round-trip the popover used, and
//  with it the sleep-then-post pattern that would misbehave in the overlay.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class SurfaceActions: ObservableObject {
    // Declared explicitly: the synthesized witness cannot satisfy a nonisolated
    // protocol requirement from a main-actor-isolated type with no @Published state.
    nonisolated let objectWillChange = ObservableObjectPublisher()

    var dismiss: @MainActor () -> Void
    var openPreferences: @MainActor () -> Void
    var quit: @MainActor () -> Void

    init(dismiss: @escaping @MainActor () -> Void = {},
         openPreferences: @escaping @MainActor () -> Void = {},
         quit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) {
        self.dismiss = dismiss
        self.openPreferences = openPreferences
        self.quit = quit
    }
}
