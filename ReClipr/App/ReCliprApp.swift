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
    // so clipboard monitoring begins immediately — not lazily on the first menu click
    // like @StateObject inside a MenuBarExtra closure would be.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ReClipr", systemImage: "paperclip") {
            RootView()
                .environmentObject(appDelegate.store)
        }.menuBarExtraStyle(.window)

        Window("Preferences", id: "preferences") {
            PreferencesView()
        }.defaultSize(width: 380, height: 380)
    }
}
