//
//  PreferencesView.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
//  Split into tabs: five sections stacked in one column ran to roughly 900pt.
//

import AppKit
import Combine
import OSLog
import ServiceManagement
import SwiftUI

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "Preferences")

// MARK: - Shortcut Recorder

final class ShortcutRecorder: ObservableObject {
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
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ClipboardStore

    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            PresentationTab().tabItem { Label("Appearance", systemImage: "macwindow") }
            CaptureTab().tabItem { Label("Capture", systemImage: "camera") }
            StorageTab().tabItem { Label("Storage", systemImage: "internaldrive") }
            ShortcutTab().tabItem { Label("Shortcut", systemImage: "keyboard") }
        }
        .frame(width: 460, height: 420)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Duplicates")
                VStack(alignment: .leading, spacing: 6) {
                    duplicateOption("No Duplicates", .none)
                    HStack(spacing: 8) {
                        duplicateOption("After Interval", .timed)
                        if settings.duplicatePolicyRaw == DuplicatePolicy.timed.rawValue {
                            intervalPicker
                        }
                    }
                    duplicateOption("Allow All", .always)
                }

                Divider()

                LabeledRow("History Limit", "Maximum number of items to keep") {
                    Menu {
                        ForEach([50, 100, 200, 500, 1000], id: \.self) { count in
                            Button("\(count) items") { settings.maxHistoryCount = count }
                        }
                    } label: {
                        Text("\(settings.maxHistoryCount) items")
                    }
                    .fixedSize()
                }

                Divider()

                LabeledRow("Launch at Login", "Start automatically on login") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .onChange(of: settings.launchAtLogin) { _, value in toggleLaunchAtLogin(value) }
                }

                Divider()

                SectionHeader("Ignored Apps")
                TextEditor(text: $settings.ignoredAppsRaw)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Text("Bundle identifiers, separated by commas. Copies from these apps are never recorded.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .onAppear { settings.launchAtLogin = (SMAppService.mainApp.status == .enabled) }
    }

    private func duplicateOption(_ title: String, _ value: DuplicatePolicy) -> some View {
        HStack(spacing: 8) {
            Image(systemName: settings.duplicatePolicyRaw == value.rawValue
                  ? "largecircle.fill.circle" : "circle")
                .foregroundColor(.accentColor)
            Text(title).font(.system(size: 13))
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { settings.duplicatePolicyRaw = value.rawValue }
    }

    private var intervalPicker: some View {
        Menu {
            ForEach([30, 60, 120, 300, 600, 900, 1800], id: \.self) { seconds in
                Button(label(for: seconds)) { settings.duplicateInterval = Double(seconds) }
            }
        } label: {
            Text(label(for: Int(settings.duplicateInterval)))
        }
        .fixedSize()
    }

    private func label(for seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)min"
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            logger.error("Launch at login failed: \(error, privacy: .public)")
        }
    }
}

// MARK: - Presentation

private struct PresentationTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LabeledRow("Show Menu Bar Icon", "The paperclip in your menu bar") {
                    Toggle("", isOn: $settings.showMenuBarIcon)
                        .labelsHidden()
                        // Hiding the icon with no shortcut set would leave no way in.
                        .disabled(!settings.hasShortcut && settings.showMenuBarIcon)
                }
                if !settings.hasShortcut && settings.showMenuBarIcon {
                    Text("Set a keyboard shortcut first, or you would have no way to open ReClipr.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Divider()

                LabeledRow("Open as Floating Overlay",
                           "Appears over whatever you are working in") {
                    // TODO(monetisation): gate behind FeatureGate.isUnlocked(.overlay)
                    // and present a purchase sheet when it returns false.
                    Toggle("", isOn: $settings.openAsOverlay).labelsHidden()
                }
                Text("Click an item to copy it, then press ⌘V. ReClipr never pastes for you.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(reachabilitySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Divider()

                BackgroundPicker()

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    /// Always visible, so the consequences of the two toggles are never a surprise.
    private var reachabilitySummary: String {
        let shortcut = settings.hasShortcut ? settings.shortcutDisplay : nil
        switch (settings.showMenuBarIcon, shortcut) {
        case (true, let key?):
            return "History opens with \(key), or by clicking the menu bar icon."
        case (true, nil):
            return "History opens by clicking the menu bar icon. No keyboard shortcut is set."
        case (false, let key?):
            return "History opens with \(key) only. Preferences and Quit live in the overlay's ⋯ menu."
        case (false, nil):
            return "ReClipr is currently unreachable. Set a shortcut or turn the menu bar icon back on."
        }
    }
}

// MARK: - Capture

private struct CaptureTab: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ClipboardStore

    private static let thresholds = [5_000_000, 10_000_000, 50_000_000, 100_000_000]

    private var statusColor: Color {
        if store.screenshotAccessDenied { return .orange }
        return store.screenshotIsWatching ? .green : .secondary
    }

    private var statusText: String {
        if store.screenshotAccessDenied {
            return "Cannot read the screenshots folder — grant Files and Folders access."
        }
        return store.screenshotIsWatching ? "Watching for new screenshots" : "Not watching"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LabeledRow("Watch Screenshots Folder",
                           "Add ⇧⌘3 and ⇧⌘4 screenshots to history automatically") {
                    Toggle("", isOn: $settings.watchScreenshots).labelsHidden()
                }

                // Live status: which folder, whether the watcher is actually running,
                // and when it last saw something. Without this a watcher that failed
                // to start is indistinguishable from one that simply has nothing to do.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(store.screenshotAccessDenied ? .orange : .secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(store.screenshotFolderPath.isEmpty
                             ? ScreenshotWatcher.currentConfig().directory.path
                             : store.screenshotFolderPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Button("Reveal") {
                            NSWorkspace.shared.selectFile(
                                nil, inFileViewerRootedAtPath:
                                    store.screenshotFolderPath.isEmpty
                                    ? ScreenshotWatcher.currentConfig().directory.path
                                    : store.screenshotFolderPath)
                        }
                        .controlSize(.mini)
                        Button("Recheck") { store.refreshScreenshotWatch() }
                            .controlSize(.mini)
                    }

                    if let last = store.lastScreenshotCaptured {
                        Text("Last captured at \(ClipTimestamp.string(for: last)).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if store.screenshotAccessDenied {
                        Button("Open Privacy Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Files") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if settings.watchScreenshots {
                    Toggle("Also copy new screenshots to the clipboard",
                           isOn: $settings.copyScreenshotToClipboard)
                        .font(.system(size: 13))
                    Text("Lets you paste a screenshot with ⌘V straight away. It replaces whatever you had copied.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                LabeledRow("Copy Files Under", "Larger files are stored as a link instead") {
                    Menu {
                        ForEach(Self.thresholds, id: \.self) { bytes in
                            Button(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) {
                                settings.largeFileThresholdBytes = bytes
                            }
                        }
                    } label: {
                        Text(ByteCountFormatter.string(
                            fromByteCount: Int64(settings.largeFileThresholdBytes), countStyle: .file))
                    }
                    .fixedSize()
                }
                Text("Smaller files are copied into ReClipr, so the clip still works if you delete the original. "
                     + "Larger ones point at the original — pasting in Finder copies it, and ⌥⌘V moves it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear { store.refreshScreenshotWatch() }
    }
}

// MARK: - Storage

private struct StorageTab: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ClipboardStore
    @StateObject private var usage = StorageUsageModel()
    @State private var confirmingClear = false

    private static let budgets = [500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000, 0]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Space Used")
                HStack {
                    Text(usage.isCalculating ? "Calculating…" : usage.formatted)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                    Spacer()
                    Button("Refresh") { usage.refresh() }
                        .controlSize(.small)
                }
                if settings.blobBudgetBytes > 0 {
                    ProgressView(value: usage.fraction(of: settings.blobBudgetBytes))
                        .progressViewStyle(.linear)
                }

                Divider()

                LabeledRow("Storage Limit", "Oldest items are removed once this is exceeded") {
                    Menu {
                        ForEach(Self.budgets, id: \.self) { bytes in
                            Button(bytes == 0
                                   ? "Unlimited"
                                   : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) {
                                settings.blobBudgetBytes = bytes
                            }
                        }
                    } label: {
                        Text(settings.blobBudgetBytes == 0
                             ? "Unlimited"
                             : ByteCountFormatter.string(
                                fromByteCount: Int64(settings.blobBudgetBytes), countStyle: .file))
                    }
                    .fixedSize()
                }
                Text("Only items whose contents ReClipr stores count toward this. Text clips and linked files are free.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                if confirmingClear {
                    HStack {
                        Text("Delete all history and stored files?")
                            .font(.system(size: 12))
                        Spacer()
                        Button("Cancel") { confirmingClear = false }.controlSize(.small)
                        Button("Delete", role: .destructive) {
                            usage.clearCache(store: store)
                            confirmingClear = false
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button("Clear History and Cache…", role: .destructive) { confirmingClear = true }
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .onAppear { usage.refresh() }
    }
}

// MARK: - Shortcut

private struct ShortcutTab: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var recorder = ShortcutRecorder()
    @State private var restoredIcon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Keyboard Shortcut")

                HStack(spacing: 8) {
                    Text("Open history").font(.system(size: 13))
                    Spacer()

                    Button(recorder.isRecording ? "Press keys…" : settings.shortcutDisplay) {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            recorder.start { keyCode, modRaw, display in
                                settings.recordShortcut(keyCode: keyCode, modifiers: modRaw, display: display)
                                restoredIcon = false
                            }
                        }
                    }
                    .foregroundStyle(recorder.isRecording ? Color.orange : Color.primary)
                    .buttonStyle(.bordered)

                    Button {
                        recorder.stop()
                        GlobalHotkeyManager.shared.unregister()
                        restoredIcon = settings.clearShortcut()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear shortcut")
                    .disabled(!settings.hasShortcut)
                }

                if settings.shortcutRegistrationFailed {
                    Label("\(settings.shortcutDisplay) is already used by another app. Choose a different combination.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if restoredIcon {
                    Text("Menu bar icon turned back on so ReClipr stays reachable.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Works system-wide. Default: \(AppSettings.defaultShortcutDisplay)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}

// MARK: - Shared bits

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.system(size: 13, weight: .medium))
    }
}

private struct LabeledRow<Accessory: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder let accessory: Accessory

    init(_ title: String, _ caption: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}
