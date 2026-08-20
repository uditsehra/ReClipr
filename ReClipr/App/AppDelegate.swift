//
//  AppDelegate.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Initialized in AppDelegate.init(), which @NSApplicationDelegateAdaptor calls
    // before App.body is ever evaluated — so the store and its monitoring are always
    // running by the time the menu is first opened.
    let store = ClipboardStore()
}
