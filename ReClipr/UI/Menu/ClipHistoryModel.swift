//
//  ClipHistoryModel.swift
//  ReClipr
//
//  Owns list state — filtering, selection, key handling — as a reference type.
//
//  This exists because of a real crash: key handling used to live on ClipHistoryView
//  and the overlay captured that struct to call later from NSPanel.sendEvent. A
//  SwiftUI View read outside body evaluation has no environment, so the first
//  @EnvironmentObject access trapped and any keystroke killed the app. Holding the
//  store as a plain reference here makes the closure safe to capture.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class ClipHistoryModel: ObservableObject {
    let store: ClipboardStore
    let settings: AppSettings
    let metrics: SurfaceMetrics

    /// Multi-selection. A plain click still copies; ⌘-click and ⇧-click build a set.
    @Published var selection: Set<UUID> = []
    @Published var dateFilter: DateFilter = .all
    @Published var copiedItemID: UUID?

    /// Item shown in the full-size preview, if any. Set by a long press or the space
    /// bar, which is the Quick Look gesture people already expect on macOS.
    @Published var previewItem: ClipItem?

    /// Number of columns the grid is currently laying out, measured by the view.
    /// Arrow keys are meaningless in a grid without it: ↑↓ have to move a whole row.
    var columnCount: Int = 1

    /// Always a grid now; kept as a constant so the arrow-key stride reads clearly.
    var isGrid: Bool { true }

    /// Anchor for ⇧-click range extension.
    private var selectionAnchor: UUID?
    private var cancellables = Set<AnyCancellable>()

    /// Copy an item and dismiss. Supplied by the surface.
    var onActivate: (ClipItem) -> Void = { _ in }
    /// Ask the surface to close.
    var onDismiss: () -> Void = {}
    /// Open Preferences from a keyboard shortcut.
    var onOpenPreferences: () -> Void = {}

    init(store: ClipboardStore, settings: AppSettings, metrics: SurfaceMetrics) {
        self.store = store
        self.settings = settings
        self.metrics = metrics

        // The view observes this model, so changes to the store must propagate.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Derived

    /// Forwarded so the search field can bind through the model rather than reaching
    /// into the store, which is no longer an @EnvironmentObject in the view.
    var searchQuery: String {
        get { store.searchQuery }
        set { store.searchQuery = newValue }
    }

    var displayedItems: [ClipItem] {
        let base = store.filteredItems
        let filtered = dateFilter == .all ? base : base.filter { dateFilter.matches($0.date) }
        return Array(filtered.prefix(metrics.rowLimit))
    }

    var selectedItems: [ClipItem] {
        displayedItems.filter { selection.contains($0.id) }
    }

    var hasMultipleSelected: Bool { selection.count > 1 }

    // MARK: - Selection

    func resetSelection() {
        selection = displayedItems.first.map { [$0.id] } ?? []
        selectionAnchor = displayedItems.first?.id
    }

    func clearSelection() {
        selection.removeAll()
        selectionAnchor = nil
    }

    func isSelected(_ item: ClipItem) -> Bool { selection.contains(item.id) }

    // MARK: - Preview

    func showPreview(_ item: ClipItem) {
        guard !item.content.isResourceMissing else { return }
        selection = [item.id]
        selectionAnchor = item.id
        previewItem = item
    }

    func closePreview() {
        previewItem = nil
    }

    /// Space toggles the preview for whatever is selected, matching Quick Look.
    func togglePreviewForSelection() {
        if previewItem != nil {
            closePreview()
            return
        }
        guard let item = selectedItems.first ?? displayedItems.first else { return }
        showPreview(item)
    }

    /// Routes a click by modifier: ⌘ toggles, ⇧ extends, plain copies.
    /// Read from the current event rather than a gesture, since SwiftUI's Button
    /// action does not carry modifier flags.
    func handleTap(on item: ClipItem) {
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.command) {
            toggle(item)
        } else if modifiers.contains(.shift) {
            extendSelection(to: item)
        } else {
            selection = [item.id]
            selectionAnchor = item.id
            activate(item)
        }
    }

    private func toggle(_ item: ClipItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
            selectionAnchor = item.id
        }
    }

    private func extendSelection(to item: ClipItem) {
        let items = displayedItems
        guard let anchor = selectionAnchor ?? items.first?.id,
              let from = items.firstIndex(where: { $0.id == anchor }),
              let to = items.firstIndex(where: { $0.id == item.id })
        else {
            selection = [item.id]
            return
        }
        let range = from <= to ? from...to : to...from
        selection = Set(items[range].map(\.id))
    }

    func selectAll() {
        selection = Set(displayedItems.map(\.id))
    }

    private func activate(_ item: ClipItem) {
        guard !item.content.isResourceMissing else { return }
        onActivate(item)
    }

    // MARK: - Deletion

    /// Removes every selected clip, then selects whatever took their place.
    func deleteSelected() {
        let doomed = selectedItems
        guard !doomed.isEmpty else { return }

        let items = displayedItems
        let lastIndex = doomed.compactMap { d in items.firstIndex { $0.id == d.id } }.max() ?? 0
        let survivor = items.dropFirst(lastIndex + 1).first { !selection.contains($0.id) }
            ?? items.prefix(lastIndex).last { !selection.contains($0.id) }

        for item in doomed { store.deleteItem(item) }

        selection = survivor.map { [$0.id] } ?? []
        selectionAnchor = survivor?.id
    }

    func togglePin(_ item: ClipItem) {
        store.togglePin(item)
    }

    func copyPlainText(_ item: ClipItem) {
        store.copyAsPlainText(item)
        onDismiss()
    }

    func delete(_ item: ClipItem) {
        store.deleteItem(item)
        selection.remove(item.id)
    }

    // MARK: - Keyboard

    /// Returns true when the event was consumed. Anything else falls through to the
    /// search field so typing always searches.
    func handleKey(_ event: NSEvent) -> Bool {
        let items = displayedItems
        guard !items.isEmpty else { return false }

        let modifiers = event.modifierFlags
        let current = selection.count == 1
            ? items.firstIndex { $0.id == selection.first }
            : selectedItems.last.flatMap { last in items.firstIndex { $0.id == last.id } }

        // While the preview is open it owns the keyboard: space and escape close it,
        // and arrow keys step through items with the preview following along.
        if previewItem != nil {
            switch event.keyCode {
            case 49: // space
                closePreview()
                return true
            case 125, 126, 123, 124: // arrows step the preview through the list
                let stride = isGrid && (event.keyCode == 125 || event.keyCode == 126)
                    ? max(1, columnCount) : 1
                let step = (event.keyCode == 125 || event.keyCode == 124) ? stride : -stride
                move(from: current, by: step, in: items, extending: false)
                previewItem = selectedItems.first
                return true
            case 36, 76: // return copies what is being previewed
                if let item = previewItem { activate(item) }
                return true
            default:
                return true      // swallow everything else
            }
        }

        // In a grid, ↑↓ step a whole row and ←→ step one item. In a list both pairs
        // step one item, since there is only ever one column.
        let rowStride = isGrid ? max(1, columnCount) : 1

        switch event.keyCode {
        case 49: // space opens the preview
            togglePreviewForSelection()
            return true

        case 125: // down
            move(from: current, by: rowStride, in: items, extending: modifiers.contains(.shift))
            return true

        case 126: // up
            move(from: current, by: -rowStride, in: items, extending: modifiers.contains(.shift))
            return true

        case 124: // right
            move(from: current, by: 1, in: items, extending: modifiers.contains(.shift))
            return true

        case 123: // left
            move(from: current, by: -1, in: items, extending: modifiers.contains(.shift))
            return true

        case 36, 76: // return / enter
            guard let index = current, items.indices.contains(index) else { return false }
            activate(items[index])
            return true

        case 51 where modifiers.contains(.command): // ⌘⌫
            deleteSelected()
            return true

        case 0 where modifiers.contains(.command): // ⌘A
            selectAll()
            return true

        // Both ⌘; and ⌘, open Preferences: the first is what was asked for, the
        // second is the system-wide convention every other Mac app uses.
        case 41 where modifiers.contains(.command),   // ⌘;
             43 where modifiers.contains(.command):   // ⌘,
            onOpenPreferences()
            return true

        case 35 where modifiers.contains(.command):  // ⌘P pins or unpins
            if let item = selectedItems.first { togglePin(item) }
            return true

        case 36 where modifiers.contains([.command, .shift]),  // ⇧⌘⏎ pastes plain
             76 where modifiers.contains([.command, .shift]):
            if let item = selectedItems.first, item.canCopyAsPlainText { copyPlainText(item) }
            return true

        default:
            break
        }

        // ⌘1…⌘9 copies the nth visible clip.
        if modifiers.contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let digit = Int(characters), (1...9).contains(digit), digit <= items.count {
            activate(items[digit - 1])
            return true
        }

        return false
    }

    /// Escape unwinds one layer at a time: a multi-selection, then a search, then the
    /// window. Returns true when it handled the key without dismissing.
    func handleEscape() -> Bool {
        if previewItem != nil {
            closePreview()
            return true
        }
        if hasMultipleSelected {
            selection = selection.first.map { [$0] } ?? []
            return true
        }
        if !store.searchQuery.isEmpty {
            store.searchQuery = ""
            return true
        }
        return false
    }

    private func move(from index: Int?, by offset: Int, in items: [ClipItem], extending: Bool) {
        let target = index.map { max(0, min($0 + offset, items.count - 1)) } ?? 0
        guard items.indices.contains(target) else { return }
        let id = items[target].id

        if extending {
            selection.insert(id)
        } else {
            selection = [id]
            selectionAnchor = id
        }
    }
}
