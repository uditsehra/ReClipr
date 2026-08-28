//
//  ClipSurface.swift
//  ReClipr
//
//  The history list is shown in two places with different ergonomics: a small
//  mouse-driven popover hanging off the menu bar, and a large keyboard-driven
//  overlay floating over another app. The content is identical; only these
//  measurements and affordances differ.
//

import Foundation

enum ClipSurface: Sendable {
    case popover
    case overlay
}

struct SurfaceMetrics: Sendable {
    let rowLimit: Int
    let listMinHeight: CGFloat?
    let listMaxHeight: CGFloat?
    let gridMinItemWidth: CGFloat
    /// Height of a grid tile's preview area. Fixed rather than intrinsic so the grid
    /// stays on a regular baseline instead of every row jumping to its tallest image.
    let gridPreviewHeight: CGFloat
    /// Cap for a full-width image in list mode.
    let listImageMaxHeight: CGFloat
    let showsKeyboardNav: Bool
    /// How long to leave the "copied" tick up before dismissing. The overlay must
    /// dismiss immediately: it holds key focus, so any delay means a quick ⌘V lands
    /// in our own search field instead of the app the user came from.
    let selectionConfirmationDelay: Duration?
    let contentPadding: CGFloat

    static let popover = SurfaceMetrics(
        rowLimit: 50,
        listMinHeight: 160,
        listMaxHeight: 400,
        gridMinItemWidth: 104,
        gridPreviewHeight: 78,
        listImageMaxHeight: 150,
        showsKeyboardNav: true,
        selectionConfirmationDelay: .milliseconds(500),
        contentPadding: 16)

    static let overlay = SurfaceMetrics(
        rowLimit: 200,
        listMinHeight: nil,
        listMaxHeight: nil,
        gridMinItemWidth: 156,
        gridPreviewHeight: 108,
        listImageMaxHeight: 200,
        showsKeyboardNav: true,
        selectionConfirmationDelay: nil,
        contentPadding: 16)

    static func metrics(for surface: ClipSurface) -> SurfaceMetrics {
        switch surface {
        case .popover: return .popover
        case .overlay: return .overlay
        }
    }
}
