//
//  ReCliprMenuView.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import SwiftUI


struct ReCliprMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var store: ClipboardStore
    
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8){
            
            // Search
            TextField("Seach Clipboard", text: $store.searchQuery)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            
            // Content
            if store.filteredItems.isEmpty {
                Text(store.searchQuery.isEmpty
                     ? "No clipboard history yet"
                     : "No matching results"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
            }
            else{
                ForEach(store.filteredItems.prefix(10)) {item in
                    Button {
                        store.copyToClipboard(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.content.displayTitle)
                                .lineLimit(1)

                        HStack(spacing: 6) {
                            if let appName = item.sourceAppName {
                                Text(appName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text("·")
                            Text(item.date, style: .time)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            // Actions
            Button("Preferences..."){
//                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "preferences")
            }
            
            Button("Clear History"){
                store.clearAll()
            }
            
            Button("Quit ReClipr"){
                NSApp.terminate(nil)
            }
        }
        .padding()
        .frame(width: 320)
    }
    
    private func openPreferences(){
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

