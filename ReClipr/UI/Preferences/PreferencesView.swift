//
//  PreferencesView.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import OSLog
import ServiceManagement
import SwiftUI

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "Preferences")

struct PreferencesView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("ignoredApps")
    private var ignoredAppsRaw: String = "com.apple.keychainaccess"

    @AppStorage("duplicatePolicy")
    private var duplicatePolicyRaw: String = DuplicatePolicy.none.rawValue
    @AppStorage("duplicateInterval")
    private var duplicateInterval: Double = 300

    @AppStorage("maxHistoryCount")
    private var maxHistoryCount: Int = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Duplicates
            VStack(alignment: .leading, spacing: 10) {
                Text("Duplicates")
                    .font(.system(size: 13, weight: .medium))

                VStack(alignment: .leading, spacing: 6) {
                    duplicateOption(title: "No Duplicates", value: .none)

                    HStack(spacing: 8) {
                        duplicateOption(title: "After Interval", value: .timed)
                        if duplicatePolicyRaw == DuplicatePolicy.timed.rawValue {
                            intervalPicker
                        }
                    }

                    duplicateOption(title: "Allow All", value: .always)
                }
            }

            Divider()

            // History limit
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History Limit")
                        .font(.system(size: 13, weight: .medium))
                    Text("Maximum number of items to keep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    ForEach([50, 100, 200, 500, 1000], id: \.self) { count in
                        Button("\(count) items") { maxHistoryCount = count }
                    }
                } label: {
                    Text("\(maxHistoryCount) items")
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Divider()

            // Launch at login
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .font(.system(size: 13, weight: .medium))
                    Text("Start automatically on login")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, newValue in toggleLaunchAtLogin(newValue) }
            }

            Divider()

            // Ignored apps
            VStack(alignment: .leading, spacing: 8) {
                Text("Ignored Apps")
                    .font(.system(size: 13, weight: .medium))

                TextEditor(text: $ignoredAppsRaw)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 70)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    )

                Text("Enter app bundle identifiers separated by commas.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func duplicateOption(title: String, value: DuplicatePolicy) -> some View {
        HStack(spacing: 8) {
            Image(systemName: duplicatePolicyRaw == value.rawValue
                  ? "largecircle.fill.circle" : "circle")
                .foregroundColor(.accentColor)
            Text(title).font(.system(size: 13))
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { duplicatePolicyRaw = value.rawValue }
    }

    private var intervalPicker: some View {
        Menu {
            ForEach([30, 60, 120, 300, 600, 900, 1800], id: \.self) { seconds in
                Button(label(for: seconds)) { duplicateInterval = Double(seconds) }
            }
        } label: {
            Text(label(for: Int(duplicateInterval)))
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func label(for seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)min"
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch at login failed: \(error, privacy: .public)")
        }
    }
}
