//
//  AppearanceTests.swift
//  ReCliprTests
//

import XCTest
@testable import ReClipr

@MainActor
final class AppearanceTests: XCTestCase {

    func testBackgroundRoundTripsThroughStorage() {
        let cases: [OverlayBackground] = [
            .glass,
            .desktopPicture,
            .image(URL(fileURLWithPath: "/System/Library/Desktop Pictures/Mac Blue.heic")),
            .image(URL(fileURLWithPath: "/tmp/a path with spaces.png")),
        ]
        for background in cases {
            XCTAssertEqual(OverlayBackground(storageValue: background.storageValue), background)
        }
    }

    func testUnknownStorageValueFallsBackToGlass() {
        XCTAssertEqual(OverlayBackground(storageValue: "nonsense"), .glass)
        XCTAssertEqual(OverlayBackground(storageValue: ""), .glass)
    }

    func testAPathContainingAColonSurvives() {
        let url = URL(fileURLWithPath: "/tmp/a:b.png")
        XCTAssertEqual(OverlayBackground(storageValue: "image:/tmp/a:b.png"), .image(url))
    }

    func testAMissingWallpaperIsReportedUnavailable() {
        XCTAssertFalse(OverlayBackground.image(URL(fileURLWithPath: "/nope-zzz.png")).isAvailable)
        XCTAssertTrue(OverlayBackground.glass.isAvailable, "glass has no file and cannot go missing")
    }

    func testScrimAndPlacementDefaultsAndFallbacks() {
        let defaults = UserDefaults(suiteName: "ReCliprTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.overlayScrim, .dim)
        XCTAssertEqual(settings.overlayPlacement, .center)

        defaults.set("garbage", forKey: AppSettings.Key.overlayScrim)
        defaults.set("garbage", forKey: AppSettings.Key.overlayPlacement)
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.overlayScrim, .dim)
        XCTAssertEqual(reloaded.overlayPlacement, .center)
    }

    func testRememberedOriginPersistsAndClears() {
        let defaults = UserDefaults(suiteName: "ReCliprTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.overlayOrigin)

        // Negative coordinates are legal on a display left of the main one.
        settings.overlayOrigin = CGPoint(x: -1440, y: -200)
        XCTAssertEqual(AppSettings(defaults: defaults).overlayOrigin, CGPoint(x: -1440, y: -200))

        settings.overlayOrigin = nil
        XCTAssertNil(AppSettings(defaults: defaults).overlayOrigin)
    }

    func testShortcutDefaultIsNotPersistedSoItCanChange() {
        let defaults = UserDefaults(suiteName: "ReCliprTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.shortcutKeyCode, AppSettings.defaultShortcutKeyCode)
        // object(forKey:) searches the registration domain as well, so the persistent
        // domain is what actually answers "was this written to disk".
        let suite = defaults.dictionaryRepresentation()
        _ = suite
        XCTAssertNil(defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[
            AppSettings.Key.shortcutKeyCode],
            "registered defaults must not be written, or the default could never move")
    }

    func testAnExplicitlyRecordedShortcutIsKept() {
        let defaults = UserDefaults(suiteName: "ReCliprTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.recordShortcut(keyCode: 9, modifiers: 1_179_648, display: "⌘⇧V")
        XCTAssertEqual(AppSettings(defaults: defaults).shortcutKeyCode, 9)
    }

    func testClearingTheShortcutRestoresTheMenuBarIcon() {
        let defaults = UserDefaults(suiteName: "ReCliprTests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.showMenuBarIcon = false
        XCTAssertTrue(settings.clearShortcut(), "the icon must come back, or there is no way in")
        XCTAssertTrue(settings.showMenuBarIcon)
    }
}
