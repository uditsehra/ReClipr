//
//  WallpaperLibrary.swift
//  ReClipr
//
//  Finds the wallpapers macOS already ships, so the theme picker offers something
//  familiar without asking the user to hunt through the filesystem.
//

import AppKit
import AVFoundation
import Foundation

struct Wallpaper: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL
    let isVideo: Bool

    nonisolated init(id: String, name: String, url: URL, isVideo: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.isVideo = isVideo
    }

    /// An aerial resolves to its cached still frame, not to the movie.
    nonisolated var background: OverlayBackground? {
        guard isVideo else { return .image(url) }
        return WallpaperLibrary.stillFrame(forVideoAt: url).map { .image($0) }
    }
}

enum WallpaperLibrary {
    nonisolated private static let stillsDirectory = URL(fileURLWithPath: "/System/Library/Desktop Pictures")

    /// Apple's aerial screensaver clips. Present only if the user has downloaded any.
    nonisolated private static let aerialDirectory = URL(
        fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS")

    /// Still wallpapers shipped with macOS, alphabetical.
    nonisolated static func stills(limit: Int = 60) -> [Wallpaper] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: stillsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []

        return contents
            .filter { ["heic", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(limit)
            .map {
                Wallpaper(id: $0.path,
                          name: $0.deletingPathExtension().lastPathComponent,
                          url: $0,
                          isVideo: false)
            }
    }

    /// Aerial video wallpapers. These are 4K files of roughly 150 MB each, which is
    /// why the picker warns about playback cost.
    nonisolated static func aerials() -> [Wallpaper] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: aerialDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []

        return contents
            .filter { $0.pathExtension.lowercased() == "mov" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .enumerated()
            .map { index, url in
                // The UUID filenames carry no meaning, and Apple's name strings are
                // not reliably present, so number them.
                Wallpaper(id: url.path, name: "Aerial \(index + 1)", url: url, isVideo: true)
            }
    }

    nonisolated static var hasAerials: Bool {
        !aerials().isEmpty
    }

    /// The wallpaper currently set for a screen, when it is a still image.
    static func currentDesktopPicture(for screen: NSScreen?) -> URL? {
        guard let screen = screen ?? NSScreen.main else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    // MARK: - Still frames

    nonisolated private static var framesDirectory: URL {
        let dir = FileAccess.appSupportDirectory().appendingPathComponent("wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Extracts one frame from a movie and caches it as a PNG, returning the cached
    /// file. Called once per wallpaper; afterwards it is a file-exists check.
    ///
    /// Grabbing a frame rather than playing the clip is the whole point: the result
    /// looks nearly identical behind a translucent panel and costs nothing to display.
    nonisolated static func stillFrame(forVideoAt url: URL) -> URL? {
        let name = url.deletingPathExtension().lastPathComponent
        let cached = framesDirectory.appendingPathComponent("\(name).png")
        if FileManager.default.fileExists(atPath: cached.path) { return cached }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Ample for a 680pt panel on a Retina display, and a fraction of a 4K frame.
        generator.maximumSize = CGSize(width: 2048, height: 2048)

        // A little way in: the opening frames of an aerial are often a fade from black.
        guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 3, preferredTimescale: 600),
                                                       actualTime: nil)
        else { return nil }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try png.write(to: cached, options: .atomic)
            return cached
        } catch {
            return nil
        }
    }

    // MARK: - Thumbnails

    nonisolated(unsafe) private static let thumbnails = NSCache<NSString, NSImage>()

    /// Small preview for the picker. Video frames are grabbed at the first second.
    nonisolated static func thumbnail(for wallpaper: Wallpaper, size: CGSize) -> NSImage? {
        let key = "\(wallpaper.id)-\(Int(size.width))" as NSString
        if let hit = thumbnails.object(forKey: key) { return hit }

        let image: NSImage?
        if wallpaper.isVideo {
            image = videoFrame(at: wallpaper.url, size: size)
        } else {
            image = NSImage(contentsOf: wallpaper.url)
        }

        guard let image else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    nonisolated private static func videoFrame(at url: URL, size: CGSize) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)
        guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600),
                                                       actualTime: nil)
        else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }
}
