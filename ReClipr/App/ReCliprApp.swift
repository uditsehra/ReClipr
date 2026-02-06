//
//  ReCliprApp.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import SwiftUI


@main
struct ReCliprApp: App {
        var body: some Scene {
            MenuBarExtra("ReClipr", systemImage: "paperclip"){
                RootView()
            }.menuBarExtraStyle(.window)
            
            Window("Preferences", id: "preferences"){
                PreferencesView()
            }.defaultSize(width: 380, height: 150)
    }
}
