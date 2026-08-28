//
//  ClipHistoryModelTests.swift
//  ReCliprTests
//
//  Selection and key handling. These exist because the overlay once crashed on the
//  first arrow key: key handling lived on a SwiftUI View that the panel captured and
//  called outside body evaluation, where @EnvironmentObject is not resolvable.
//  Holding this state in a reference type is what fixed it, and these tests are what
//  keep it fixed.
//

import XCTest
import AppKit
@testable import ReClipr

@MainActor
final class ClipHistoryModelTests: XCTestCase {

    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private var store: ClipboardStore!
    private var model: ClipHistoryModel!

    private enum Key {
        static let left: UInt16 = 123, right: UInt16 = 124
        static let down: UInt16 = 125, up: UInt16 = 126
        static let ret: UInt16 = 36, space: UInt16 = 49
        static let a: UInt16 = 0, delete: UInt16 = 51
        static let semicolon: UInt16 = 41, comma: UInt16 = 43
        static let p: UInt16 = 35
    }

    private var suiteName: String!
    private var directory: URL!

    override func setUp() async throws {
        suiteName = "ReCliprTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)

        // A temporary store, and no pasteboard monitoring. Using the real singleton
        // would load the user's live history — and any delete test would then write
        // an empty file back over it.
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReCliprTests-\(UUID().uuidString)")

        settings = AppSettings(defaults: defaults)
        store = ClipboardStore(settings: settings,
                               persistence: Persistence(directory: directory),
                               startsMonitoring: false)
        model = ClipHistoryModel(store: store, settings: settings, metrics: .overlay)

        XCTAssertTrue(store.items.isEmpty, "each test must start from an empty history")
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        model = nil; store = nil; settings = nil; defaults = nil; directory = nil
    }

    private func key(_ code: UInt16,
                     _ modifiers: NSEvent.ModifierFlags = [],
                     characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    private func seed(_ count: Int) {
        for i in (1...count).reversed() { store.debugInsertForTesting(.text("clip \(i)")) }
        model.resetSelection()
    }

    private var selectedIndex: Int? {
        model.displayedItems.firstIndex { model.selection.contains($0.id) }
    }

    // MARK: Navigation

    func testKeyHandlingWorksOutsideAViewBody() {
        seed(4)
        // The original crash: this call path runs from NSPanel.sendEvent, not from
        // SwiftUI. Reaching it at all is the assertion.
        XCTAssertTrue(model.handleKey(key(Key.down)))
    }

    func testArrowsInAGrid() {
        seed(9)
        model.columnCount = 3

        XCTAssertTrue(model.handleKey(key(Key.right)))
        XCTAssertEqual(selectedIndex, 1, "right moves one item")

        XCTAssertTrue(model.handleKey(key(Key.left)))
        XCTAssertEqual(selectedIndex, 0, "left moves back one")

        XCTAssertTrue(model.handleKey(key(Key.down)))
        XCTAssertEqual(selectedIndex, 3, "down moves a whole row in a grid")

        XCTAssertTrue(model.handleKey(key(Key.up)))
        XCTAssertEqual(selectedIndex, 0)
    }

    func testNavigationClampsAtBothEnds() {
        seed(5)
        model.columnCount = 2
        _ = model.handleKey(key(Key.left))
        XCTAssertEqual(selectedIndex, 0, "left at the start must not wrap or crash")
        for _ in 0..<20 { _ = model.handleKey(key(Key.right)) }
        XCTAssertEqual(selectedIndex, 4, "right past the end must clamp")
    }

    func testAZeroColumnCountCannotStall() {
        seed(3)
        model.columnCount = 0     // never trusted; a zero stride would freeze navigation
        _ = model.handleKey(key(Key.down))
        XCTAssertEqual(selectedIndex, 1)
    }

    func testKeysOnAnEmptyListAreSafe() {
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(model.handleKey(key(Key.down)))
        XCTAssertFalse(model.handleKey(key(Key.ret)))
        XCTAssertNil(model.previewItem)
    }

    // MARK: Selection

    func testShiftExtendsSelection() {
        seed(6)
        model.columnCount = 3
        _ = model.handleKey(key(Key.right, .shift))
        _ = model.handleKey(key(Key.right, .shift))
        XCTAssertEqual(model.selection.count, 3)
        XCTAssertTrue(model.hasMultipleSelected)
    }

    func testCommandASelectsEverything() {
        seed(5)
        XCTAssertTrue(model.handleKey(key(Key.a, .command, characters: "a")))
        XCTAssertEqual(model.selection.count, 5)
    }

    func testMultiDeleteRemovesEverySelectedClip() {
        seed(4)
        model.selectAll()
        model.deleteSelected()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
    }

    func testPartialDeleteLeavesASurvivorSelected() {
        seed(3)
        _ = model.handleKey(key(Key.right, .shift))
        XCTAssertEqual(model.selection.count, 2)
        model.deleteSelected()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(model.selection.count, 1, "something sensible should stay selected")
    }

    // MARK: Escape ordering

    func testEscapeUnwindsOneLayerAtATime() {
        seed(3)
        model.showPreview(model.displayedItems[0])
        XCTAssertTrue(model.handleEscape(), "first escape closes the preview")
        XCTAssertNil(model.previewItem)

        model.selectAll()
        XCTAssertTrue(model.handleEscape(), "then it collapses the selection")
        XCTAssertEqual(model.selection.count, 1)

        store.searchQuery = "clip"
        XCTAssertTrue(model.handleEscape(), "then it clears the search")
        XCTAssertTrue(store.searchQuery.isEmpty)

        XCTAssertFalse(model.handleEscape(), "finally it falls through so the window closes")
    }

    // MARK: Preview

    func testSpaceTogglesPreviewAndArrowsStepIt() {
        seed(6)
        model.columnCount = 3
        XCTAssertTrue(model.handleKey(key(Key.space)))
        XCTAssertNotNil(model.previewItem)

        _ = model.handleKey(key(Key.right))
        XCTAssertEqual(model.previewItem?.id, model.displayedItems[1].id)

        _ = model.handleKey(key(Key.down))
        XCTAssertEqual(model.previewItem?.id, model.displayedItems[4].id, "down steps a row")

        XCTAssertTrue(model.handleKey(key(Key.space)))
        XCTAssertNil(model.previewItem)
    }

    func testAMissingPayloadCannotBePreviewed() {
        let dead = ClipItem(content: .image(
            BlobRef(hash: "definitely-missing", uti: "public.png", ext: "png", byteCount: 1)))
        model.showPreview(dead)
        XCTAssertNil(model.previewItem, "a clip whose bytes are gone must not open a preview")
    }

    // MARK: Shortcuts

    func testBothPreferencesShortcuts() {
        seed(2)
        var opened = 0
        model.onOpenPreferences = { opened += 1 }
        XCTAssertTrue(model.handleKey(key(Key.semicolon, .command, characters: ";")))
        XCTAssertTrue(model.handleKey(key(Key.comma, .command, characters: ",")))
        XCTAssertEqual(opened, 2)
    }

    func testBarePunctuationFallsThroughToSearch() {
        seed(2)
        var opened = 0
        model.onOpenPreferences = { opened += 1 }
        XCTAssertFalse(model.handleKey(key(Key.semicolon, characters: ";")))
        XCTAssertFalse(model.handleKey(key(Key.comma, characters: ",")))
        XCTAssertEqual(opened, 0, "you must still be able to type ; and , into the search field")
    }

    func testCommandPTogglesPin() {
        seed(3)
        XCTAssertTrue(model.handleKey(key(Key.p, .command, characters: "p")))
        XCTAssertTrue(store.items.contains { $0.isPinned })
    }

    func testReturnCopiesTheSelectedClip() {
        seed(3)
        var copied = 0
        model.onActivate = { _ in copied += 1 }
        XCTAssertTrue(model.handleKey(key(Key.ret)))
        XCTAssertEqual(copied, 1)
    }
}
