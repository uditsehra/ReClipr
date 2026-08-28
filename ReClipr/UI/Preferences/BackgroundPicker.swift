//
//  BackgroundPicker.swift
//  ReClipr
//
//  Theme chooser for the overlay background.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BackgroundPicker: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var stills: [Wallpaper] = []
    @State private var aerials: [Wallpaper] = []

    private let tileSize = CGSize(width: 76, height: 48)
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: tileSize.width), spacing: 8)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overlay Background")
                .font(.system(size: 13, weight: .medium))

            LazyVGrid(columns: columns, spacing: 8) {
                specialTile(.glass, label: "Glass", symbol: "circle.dotted")
                specialTile(.desktopPicture, label: "Desktop", symbol: "menubar.dock.rectangle")
                Button {
                    chooseCustomFile()
                } label: {
                    tileChrome(isSelected: false) {
                        VStack(spacing: 3) {
                            Image(systemName: "plus")
                            Text("Choose…").font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            if !stills.isEmpty {
                Text("macOS Wallpapers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(stills) { wallpaper in
                            wallpaperTile(wallpaper)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 118)
            }

            if !aerials.isEmpty {
                Text("Aerial Stills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(aerials) { wallpaper in
                            wallpaperTile(wallpaper)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("A single frame from each aerial, so there is no playback cost.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if settings.overlayBackground != .glass {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Scrim").font(.system(size: 12, weight: .medium))
                    Picker("", selection: Binding(
                        get: { settings.overlayScrim },
                        set: { settings.overlayScrim = $0 })) {
                        ForEach(OverlayScrimStyle.allCases, id: \.self) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(settings.overlayScrim.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if settings.overlayScrim != .none {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Dimming").font(.system(size: 12))
                            Spacer()
                            Text("\(Int(settings.overlayDimming * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.overlayDimming, in: 0...0.8)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Overlay Position").font(.system(size: 12, weight: .medium))
                Picker("", selection: Binding(
                    get: { settings.overlayPlacement },
                    set: { settings.overlayPlacement = $0 })) {
                    ForEach(OverlayPlacement.allCases, id: \.self) { placement in
                        Text(placement.label).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 6) {
                    Text(settings.overlayPlacement.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if settings.overlayPlacement == .remember, settings.overlayOrigin != nil {
                        Button("Reset") { settings.overlayOrigin = nil }
                            .controlSize(.mini)
                    }
                }

                Text("Drag the overlay by its background to move it.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            // Enumerating /System/Library/Desktop Pictures and decoding previews is
            // disk work; keep it off the main thread.
            Task.detached(priority: .userInitiated) {
                let foundStills = WallpaperLibrary.stills()
                let foundAerials = WallpaperLibrary.aerials()
                await MainActor.run {
                    stills = foundStills
                    aerials = foundAerials
                }
            }
        }
    }

    // MARK: - Tiles

    private func specialTile(_ background: OverlayBackground,
                             label: String,
                             symbol: String) -> some View {
        Button {
            settings.overlayBackground = background
        } label: {
            tileChrome(isSelected: settings.overlayBackground == background) {
                VStack(spacing: 3) {
                    Image(systemName: symbol)
                    Text(label).font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func wallpaperTile(_ wallpaper: Wallpaper) -> some View {
        Button {
            // Extracting an aerial's frame touches the disk, so it happens off the
            // main thread the first time a given wallpaper is chosen.
            Task.detached(priority: .userInitiated) {
                let resolved = wallpaper.background
                await MainActor.run {
                    if let resolved { settings.overlayBackground = resolved }
                }
            }
        } label: {
            tileChrome(isSelected: isSelected(wallpaper)) {
                ZStack {
                    if let preview = WallpaperLibrary.thumbnail(for: wallpaper, size: tileSize) {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: wallpaper.isVideo ? "film" : "photo")
                            .foregroundStyle(.secondary)
                    }

                }
            }
        }
        .buttonStyle(.plain)
        .help(wallpaper.name)
    }

    private func tileChrome<Content: View>(isSelected: Bool,
                                           @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: tileSize.width, height: tileSize.height)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                  lineWidth: isSelected ? 2 : 1)
            )
    }

    private func chooseCustomFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image, or a video to take a single frame from"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let isVideo = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false

        guard isVideo else {
            settings.overlayBackground = .image(url)
            return
        }
        // A chosen movie is treated the same as an aerial: one frame, cached.
        Task.detached(priority: .userInitiated) {
            let frame = WallpaperLibrary.stillFrame(forVideoAt: url)
            await MainActor.run {
                if let frame { settings.overlayBackground = .image(frame) }
            }
        }
    }

    /// An aerial's selected state is its cached frame, not the movie path.
    private func isSelected(_ wallpaper: Wallpaper) -> Bool {
        guard case .image(let current) = settings.overlayBackground else { return false }
        if !wallpaper.isVideo { return current == wallpaper.url }
        return current.deletingPathExtension().lastPathComponent
            == wallpaper.url.deletingPathExtension().lastPathComponent
    }
}
