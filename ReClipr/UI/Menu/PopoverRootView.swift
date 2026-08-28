//
//  PopoverRootView.swift
//  ReClipr
//
//  Menu bar chrome around the shared history view. The fixed width lives here,
//  matching the NSPopover's content size — ClipHistoryView itself declares none so
//  the overlay can size it freely.
//

import SwiftUI

struct PopoverRootView: View {
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var actions: SurfaceActions

    @ObservedObject var model: ClipHistoryModel
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClipHistoryView(model: model)

            Divider()

            footer
        }
        .padding(SurfaceMetrics.popover.contentPadding)
        .frame(width: 352)
    }

    /// One row of quiet icon actions, mirroring the overlay's hint bar.
    ///
    /// Previously three full-width buttons stacked vertically, which read as a form
    /// rather than a toolbar and gave a destructive action the same visual weight as
    /// opening settings. Quit lives in the status item's right-click menu now — the
    /// conventional place for a menu bar app, and not something worth a permanent
    /// slot next to your clips.
    @ViewBuilder
    private var footer: some View {
        if showClearConfirmation {
            HStack(spacing: 8) {
                Text("Clear all history?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Cancel") { showClearConfirmation = false }
                    .controlSize(.small)
                Button("Clear All", role: .destructive) {
                    store.clearAll()
                    showClearConfirmation = false
                }
                .controlSize(.small)
            }
        } else {
            HStack(spacing: 12) {
                footerButton("Preferences", systemImage: "gearshape") {
                    actions.openPreferences()
                }
                .keyboardShortcut(";", modifiers: .command)

                footerButton("Clear", systemImage: "trash") {
                    showClearConfirmation = true
                }

                Spacer(minLength: 4)

                Text("Press ⌘V to paste")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func footerButton(_ title: String,
                              systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 11))
                Text(title).font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
