//
//  OverlayBackground.swift
//  ReClipr
//
//  What sits behind the overlay's content. Stored as a small string so it round-trips
//  through UserDefaults without a codable blob.
//

import Foundation

enum OverlayBackground: Sendable {
    /// Pure Liquid Glass over whatever is behind the window — the default.
    case glass
    /// Follows the desktop wallpaper of whichever screen the panel opens on.
    case desktopPicture
    /// A still image.
    ///
    /// Aerial wallpapers land here too. They used to play as looping 4K video, which
    /// cost 15–20% CPU the whole time the panel was open — a lot of power for a
    /// backdrop behind a window you dismiss in two seconds. A single frame is
    /// extracted once, cached, and shown instead.
    case image(URL)

    // MARK: Storage

    /// "glass", "desktop", "image:<path>"
    nonisolated var storageValue: String {
        switch self {
        case .glass:          return "glass"
        case .desktopPicture: return "desktop"
        case .image(let url): return "image:\(url.path)"
        }
    }

    nonisolated init(storageValue raw: String) {
        if raw == "desktop" { self = .desktopPicture; return }
        if let path = raw.dropPrefixIfPresent("image:") {
            self = .image(URL(fileURLWithPath: path)); return
        }
        // Written before aerials became stills. Convert the stored movie to a cached
        // frame on first read; if that fails, fall back to glass.
        if let path = raw.dropPrefixIfPresent("video:") {
            if let frame = WallpaperLibrary.stillFrame(forVideoAt: URL(fileURLWithPath: path)) {
                self = .image(frame)
            } else {
                self = .glass
            }
            return
        }
        self = .glass
    }

    /// Whether a legibility scrim is needed. Glass already handles its own contrast.
    nonisolated var needsScrim: Bool {
        self != .glass
    }

    /// The file this background reads, if any — used to detect a wallpaper that has
    /// been deleted or is on an unmounted volume.
    nonisolated var fileURL: URL? {
        switch self {
        case .image(let url):         return url
        case .glass, .desktopPicture: return nil
        }
    }

    nonisolated var isAvailable: Bool {
        guard let fileURL else { return true }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}

// Written out rather than synthesised: a main-actor-isolated conformance cannot be
// used from the nonisolated contexts that read the stored theme.
extension OverlayBackground: Equatable {
    nonisolated static func == (lhs: OverlayBackground, rhs: OverlayBackground) -> Bool {
        switch (lhs, rhs) {
        case (.glass, .glass), (.desktopPicture, .desktopPicture): return true
        case let (.image(a), .image(b)): return a == b
        default: return false
        }
    }
}

private extension String {
    nonisolated func dropPrefixIfPresent(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
