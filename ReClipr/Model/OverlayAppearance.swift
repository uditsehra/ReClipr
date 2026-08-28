//
//  OverlayAppearance.swift
//  ReClipr
//
//  How the overlay treats its background, and where it opens.
//

import Foundation

/// What sits between a wallpaper and the content.
///
/// Blur was the original hard-coded behaviour and it hid the wallpaper almost
/// entirely, so it is now one choice among three rather than the only one.
enum OverlayScrimStyle: String, CaseIterable, Sendable {
    /// Nothing but the edge gradient that keeps the search field and hint bar legible.
    case none
    /// An adjustable dark wash. The default.
    case dim
    /// Dim plus a full-panel blur — the most readable, and the least of the wallpaper.
    case blur

    var label: String {
        switch self {
        case .none: return "None"
        case .dim:  return "Dim"
        case .blur: return "Blur"
        }
    }

    var detail: String {
        switch self {
        case .none: return "Wallpaper shown at full strength."
        case .dim:  return "Darkens the wallpaper behind your clips."
        case .blur: return "Frosts the wallpaper. Most readable, least visible."
        }
    }
}

/// Where the panel appears when opened.
enum OverlayPlacement: String, CaseIterable, Sendable {
    /// Always centred on the screen under the pointer.
    case center
    /// Reopens wherever it was last dragged to.
    case remember

    var label: String {
        switch self {
        case .center:   return "Always centre"
        case .remember: return "Remember position"
        }
    }

    var detail: String {
        switch self {
        case .center:   return "Opens in the middle of the screen you are working on."
        case .remember: return "Opens where you last dragged it."
        }
    }
}
