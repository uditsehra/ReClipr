//
//  OverlayRootView.swift
//  ReClipr
//
//  Chrome for the floating surface: a title row carrying the actions that live in
//  the popover's footer, the shared history view, and a key hint bar.
//

import AppKit
import Combine
import SwiftUI

/// Carries key events from the panel into the SwiftUI tree.
@MainActor
final class OverlayKeyRouter: ObservableObject {
    // See SurfaceActions: explicit publisher, no @Published state to synthesize from.
    nonisolated let objectWillChange = ObservableObjectPublisher()

    var handler: ((NSEvent) -> Bool)?
    var escapeHandler: (() -> Bool)?
}

struct OverlayRootView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var actions: SurfaceActions
    @EnvironmentObject private var router: OverlayKeyRouter

    @ObservedObject var model: ClipHistoryModel
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            titleRow

            ClipHistoryView(model: model)

            hintBar
        }
        .padding(SurfaceMetrics.overlay.contentPadding)
        .frame(minWidth: 480, idealWidth: 640, maxWidth: .infinity,
               minHeight: 320, idealHeight: 520, maxHeight: .infinity)
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("ReClipr")
                .font(.system(size: 13, weight: .semibold))
            Text("\(store.items.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary)
                .clipShape(Capsule())

            Spacer()

            if showClearConfirmation {
                Text("Clear all?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") { showClearConfirmation = false }
                    .controlSize(.small)
                Button("Clear", role: .destructive) {
                    store.clearAll()
                    showClearConfirmation = false
                }
                .controlSize(.small)
            } else {
                // With the menu bar icon hidden this menu is the only route to
                // Preferences and Quit, so it is always present.
                Menu {
                    Button("Preferences…") { actions.openPreferences() }
                        .keyboardShortcut(";", modifiers: .command)
                    Button("Clear History") { showClearConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var hintBar: some View {
        HStack(spacing: 10) {
            hint("↑↓←→", "navigate")
            hint("⏎", "copy")
            hint("space", "preview")
            hint("⌘click", "multi-select")
            hint("⌘⌫", "delete")
            hint("⎋", "close")
            Spacer()
            Text("Press ⌘V to paste")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
