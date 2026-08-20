//
//  ReCliprApp.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import SwiftUI

@main
struct ReCliprApp: App {
    // AppDelegate.init() creates the store eagerly at launch (before any window appears),
    // so clipboard monitoring begins immediately — not lazily on the first menu click.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // All UI is managed by AppDelegate via NSStatusItem + NSPopover.
        // SwiftUI requires at least one Scene; Settings{} satisfies that without
        // creating any visible window on launch.
        Settings {}
    }
}
