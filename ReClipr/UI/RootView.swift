//
//  RootView.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import SwiftUI

struct RootView: View {
    @StateObject private var store = ClipboardStore()

    var body: some View {
        ReCliprMenuView()
            .environmentObject(store)
            .onAppear {
                store.startMonitoring()
            }
    }
}
