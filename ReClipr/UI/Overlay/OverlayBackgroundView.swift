//
//  OverlayBackgroundView.swift
//  ReClipr
//
//  Draws whatever sits behind the overlay's content: Liquid Glass, a still
//  wallpaper, or a looping video.
//
//  Two structurally different arrangements, which is the whole reason this class
//  exists:
//
//  * Glass — NSGlassEffectView renders nothing unless the content is handed to it as
//    its `contentView`, so the content is nested *inside* the effect. Using it as a
//    bare backdrop produces a fully transparent window.
//
//  * Media — the wallpaper is a sibling *behind* the content, with a scrim between
//    them. A photograph behind a list of text is unreadable without one, and its
//    strength is a user setting because the right amount depends on the image.
//

import AppKit

final class OverlayBackgroundView: NSView {

    /// The view the SwiftUI hosting view lives in. Reparented between arrangements,
    /// never rebuilt, so the SwiftUI tree and its state survive a theme change.
    let contentContainer = NSView()

    private var backdrop: NSView?
    private var scrim: NSVisualEffectView?
    private var scrimHost: NSView?
    private var gradientLayer: CAGradientLayer?
    private var dimLayer: CALayer?
    private var imageLayer: CALayer?

    private var contentConstraints: [NSLayoutConstraint] = []
    private var currentBackground: OverlayBackground?
    private var currentDimming: Double = -1
    private var currentScrim: OverlayScrimStyle?

    private let cornerRadius: CGFloat = 16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func layout() {
        super.layout()
        imageLayer?.frame = bounds
        dimLayer?.frame = bounds
        gradientLayer?.frame = bounds
    }

    // MARK: - Applying a theme

    func apply(_ background: OverlayBackground,
               scrimStyle: OverlayScrimStyle,
               dimming: Double,
               screen: NSScreen?) {
        // A wallpaper that has been deleted, or lives on an unmounted volume, falls
        // back to glass rather than leaving an empty panel.
        var resolved = background.isAvailable ? background : .glass

        // "Follow the desktop" resolves to whatever that screen is showing now.
        if case .desktopPicture = resolved {
            if let url = WallpaperLibrary.currentDesktopPicture(for: screen) {
                resolved = .image(url)
            } else {
                resolved = .glass
            }
        }

        // Rebuilding tears down an AVPlayer and re-decodes, so skip no-op reapplies.
        guard resolved != currentBackground
                || dimming != currentDimming
                || scrimStyle != currentScrim else { return }
        currentBackground = resolved
        currentDimming = dimming
        currentScrim = scrimStyle

        teardown()

        switch resolved {
        case .glass, .desktopPicture:
            installGlass()
        case .image(let url):
            installImage(url)
            installScrim(style: scrimStyle, dimming: dimming)
        }
    }

    private func teardown() {
        imageLayer?.removeFromSuperlayer()
        imageLayer = nil
        dimLayer?.removeFromSuperlayer()
        dimLayer = nil
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil
        scrim?.removeFromSuperview()
        scrim = nil
        scrimHost?.removeFromSuperview()
        scrimHost = nil

        NSLayoutConstraint.deactivate(contentConstraints)
        contentConstraints = []
        contentContainer.removeFromSuperview()

        backdrop?.removeFromSuperview()
        backdrop = nil
    }

    // MARK: - Arrangements

    /// Content nested inside the effect — the only arrangement in which
    /// NSGlassEffectView actually draws.
    private func installGlass() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            pin(glass, to: self)
            glass.contentView = contentContainer
            // contentView placement is not documented to fill the effect, so pin it.
            pin(contentContainer, to: glass, storeIn: &contentConstraints)
            backdrop = glass
            return
        }

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        pin(effect, to: self)
        backdrop = effect
        mountContentAbove()
    }

    /// Drawn into a layer rather than an NSImageView deliberately: an image view
    /// reports the image's own dimensions as its intrinsic content size, which pinned
    /// to the panel edges resized the whole window to the wallpaper — a 6016×6016
    /// window for a 6K desktop picture. A layer has no intrinsic size, and
    /// resizeAspectFill crops instead of distorting.
    private func installImage(_ url: URL) {
        let host = NSView()
        host.wantsLayer = true
        pin(host, to: self)
        backdrop = host

        let image = NSImage(contentsOf: url)
        let layer = CALayer()
        layer.contents = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        host.layer?.addSublayer(layer)
        imageLayer = layer
    }

    /// A dim wash only — deliberately no blur.
    ///
    /// The first version put a full-panel NSVisualEffectView over the media, which
    /// frosted a playing video into a flat grey wash and made the dimming slider
    /// useless: it controlled the layer *underneath* the blur, so turning it to zero
    /// revealed nothing. Legibility belongs to the cards, which carry their own
    /// translucent surfaces; the background's job is to stay visible.
    ///
    /// The gradient darkens only the top and bottom bands, where the search field and
    /// hint bar sit directly on the background with nothing behind them.
    private func installScrim(style: OverlayScrimStyle, dimming: Double) {
        // Blur is opt-in. It is the most readable option and shows the least of the
        // wallpaper, which is why it is no longer the only behaviour.
        if style == .blur {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            pin(effect, to: self)
            scrim = effect
        }

        let host = NSView()
        host.wantsLayer = true
        pin(host, to: self)
        scrimHost = host

        if style != .none, dimming > 0 {
            let dim = CALayer()
            dim.backgroundColor = NSColor.black.withAlphaComponent(dimming).cgColor
            dim.frame = bounds
            dim.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            host.layer?.addSublayer(dim)
            dimLayer = dim
        }

        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor.black.withAlphaComponent(0.45).cgColor,
            NSColor.black.withAlphaComponent(0.0).cgColor,
            NSColor.black.withAlphaComponent(0.0).cgColor,
            NSColor.black.withAlphaComponent(0.45).cgColor,
        ]
        gradient.locations = [0.0, 0.16, 0.84, 1.0]
        gradient.frame = bounds
        gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        host.layer?.addSublayer(gradient)
        gradientLayer = gradient

        mountContentAbove()
    }

    /// Places the content as the topmost sibling.
    private func mountContentAbove() {
        addSubview(contentContainer)
        pin(contentContainer, to: self, storeIn: &contentConstraints)
    }

    // MARK: - Layout helpers

    private func pin(_ view: NSView, to parent: NSView) {
        var ignored: [NSLayoutConstraint] = []
        if view.superview !== parent { parent.addSubview(view) }
        pin(view, to: parent, storeIn: &ignored)
    }

    private func pin(_ view: NSView, to parent: NSView, storeIn store: inout [NSLayoutConstraint]) {
        view.translatesAutoresizingMaskIntoConstraints = false
        if view.superview !== parent { parent.addSubview(view) }
        let constraints = [
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        store.append(contentsOf: constraints)
    }

    // MARK: - Playback

    /// Retained so both surfaces can call them unconditionally. Backgrounds are
    /// static now — an aerial is a cached frame, not a running player — so there is
    /// nothing to start or stop.
    func startPlaybackIfNeeded() {}
    func pausePlayback() {}
}
