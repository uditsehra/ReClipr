//
//  PreferencesView.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import AppKit
import Combine
import OSLog
import ServiceManagement
import SwiftUI

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "Preferences")

// MARK: - Shortcut Recorder (class so the event monitor closure can capture it weakly)

private final class ShortcutRecorder: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?

    func start(onRecord: @escaping (Int, Int, String) -> Void) {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 { // Escape — cancel recording
                self.stop()
                return nil
            }

            let mods = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            guard !mods.isEmpty else { return event } // require at least one real modifier

            let display = Self.displayString(event: event, modifiers: mods)
            onRecord(Int(event.keyCode), Int(mods.rawValue), display)
            self.stop()
            return nil
        }
    }

    func stop() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private static func displayString(event: NSEvent, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        s += key.isEmpty ? "?" : key
        return s
    }
}

// MARK: - PreferencesView

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

    // Default: ⌘⇧V (keyCode 9, modifiers = command | shift = 1_179_648)
    @AppStorage("shortcutKeyCode")     private var shortcutKeyCode: Int    = 9
    @AppStorage("shortcutModifiers")   private var shortcutModifiersRaw: Int = 1_179_648
    @AppStorage("shortcutDisplay")     private var shortcutDisplay: String  = "⌘⇧V"

    @StateObject private var recorder = ShortcutRecorder()

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

            // Keyboard shortcut
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcut")
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 8) {
                    Text("Open history")
                        .font(.system(size: 13))

                    Spacer()

                    Button(recorder.isRecording ? "Press keys…" : shortcutDisplay) {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            recorder.start { keyCode, modRaw, display in
                                UserDefaults.standard.set(keyCode, forKey: "shortcutKeyCode")
                                UserDefaults.standard.set(modRaw,  forKey: "shortcutModifiers")
                                UserDefaults.standard.set(display, forKey: "shortcutDisplay")
                                GlobalHotkeyManager.shared.register(
                                    keyCode: keyCode,
                                    modifiers: NSEvent.ModifierFlags(rawValue: UInt(modRaw))
                                )
                            }
                        }
                    }
                    .foregroundStyle(recorder.isRecording ? Color.orange : Color.primary)
                    .buttonStyle(.bordered)

                    Button {
                        recorder.stop()
                        GlobalHotkeyManager.shared.unregister()
                        UserDefaults.standard.set(-1,     forKey: "shortcutKeyCode")
                        UserDefaults.standard.set(0,      forKey: "shortcutModifiers")
                        UserDefaults.standard.set("None", forKey: "shortcutDisplay")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear shortcut")
                    .disabled(shortcutKeyCode == -1)
                }

                Text("Works system-wide. Default: ⌘⇧V")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
