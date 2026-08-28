//
//  ClipHistoryView.swift
//  ReClipr
//
//  The history list itself, with no chrome and no fixed width — each surface wraps
//  it and supplies its own frame, header and footer.
//
//  All state lives in ClipHistoryModel, not here: the overlay calls into key
//  handling from outside SwiftUI's body evaluation, where a View's @EnvironmentObject
//  is not resolvable.
//

import AppKit
import SwiftUI

private struct FilterPillStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
    }
}

struct ClipHistoryView: View {
    @ObservedObject var model: ClipHistoryModel

    @FocusState private var searchFocused: Bool

    private var store: ClipboardStore { model.store }
    private var settings: AppSettings { model.settings }
    private var metrics: SurfaceMetrics { model.metrics }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if model.hasMultipleSelected {
                selectionBar
            } else if store.availableDateFilters.count > 1 {
                filterPills
            }

            if model.displayedItems.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .overlay {
            if let previewed = model.previewItem {
                ClipPreviewOverlay(
                    item: previewed,
                    onCopy: {
                        model.closePreview()
                        model.onActivate(previewed)
                    },
                    onClose: { model.closePreview() })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.previewItem?.id)
        .onAppear {
            store.searchQuery = ""
            model.dateFilter = .all
            model.copiedItemID = nil
            model.resetSelection()
            if metrics.showsKeyboardNav { searchFocused = true }
        }
        // A stale selection would make Return copy something no longer on screen.
        .onChange(of: store.searchQuery) { _, _ in model.resetSelection() }
        .onChange(of: model.dateFilter) { _, _ in model.resetSelection() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Search Clipboard", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)

            if !model.selection.isEmpty {
                Text("\(model.selection.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // Same reasoning as the cards: the search field sits directly on whatever
        // background is behind the panel.
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Replaces the filter row while a multi-selection is active, so the destructive
    /// action is adjacent to the count it applies to.
    private var selectionBar: some View {
        HStack(spacing: 8) {
            Text("\(model.selection.count) selected")
                .font(.system(size: 12, weight: .medium))

            Spacer()

            Button("Select All") { model.selectAll() }
                .controlSize(.small)
            Button("Deselect") { model.resetSelection() }
                .controlSize(.small)
            Button(role: .destructive) {
                model.deleteSelected()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.small)
            .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.availableDateFilters, id: \.self) { filter in
                    Button(filter.label) {
                        withAnimation(.easeInOut(duration: 0.15)) { model.dateFilter = filter }
                    }
                    .buttonStyle(FilterPillStyle(isSelected: model.dateFilter == filter))
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        Text(store.searchQuery.isEmpty && model.dateFilter == .all
             ? "No clipboard history yet"
             : "No items match this filter")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    // MARK: - Content

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                grid
            }
            .frame(minHeight: metrics.listMinHeight, maxHeight: metrics.listMaxHeight)
            .onChange(of: model.selection) { _, selection in
                // Follow the keyboard, not every set mutation.
                guard selection.count == 1, let id = selection.first else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.gridMinItemWidth), spacing: 10)],
                  spacing: 10) {
            ForEach(model.displayedItems) { item in
                ClipGridCell(item: item,
                             isSelected: model.isSelected(item),
                             showsCopiedTick: model.copiedItemID == item.id,
                             previewHeight: metrics.gridPreviewHeight,
                             onSelect: { model.handleTap(on: item) },
                             onDelete: { model.delete(item) },
                             onPreview: { model.showPreview(item) },
                             onTogglePin: { model.togglePin(item) },
                             onCopyPlain: item.canCopyAsPlainText
                                 ? { model.copyPlainText(item) } : nil)
                    .id(item.id)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        // Arrow keys need the real column count to step a row at a time, and an
        // adaptive grid only settles it at layout time.
        .background(
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                    let spacing: CGFloat = 10
                    let minimum = metrics.gridMinItemWidth
                    model.columnCount = max(1, Int((width + spacing) / (minimum + spacing)))
                }
            }
        )
    }


}
