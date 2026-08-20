//
//  ReCliprMenuView.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import SwiftUI

private enum ViewMode: String {
    case list, grid
}

private enum DateFilter: Hashable {
    case all, today, yesterday, pastWeek, pastMonth
    case month(year: Int, month: Int)

    var label: String {
        switch self {
        case .all:       return "All"
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        case .pastWeek:  return "Past Week"
        case .pastMonth: return "Past Month"
        case .month(let year, let month):
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = 1
            guard let date = Calendar.current.date(from: comps) else { return "" }
            let fmt = DateFormatter()
            let thisYear = Calendar.current.component(.year, from: Date())
            fmt.dateFormat = year == thisYear ? "MMMM" : "MMM yyyy"
            return fmt.string(from: date)
        }
    }

    func matches(_ date: Date) -> Bool {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all:
            return true
        case .today:
            return cal.isDateInToday(date)
        case .yesterday:
            return cal.isDateInYesterday(date)
        case .pastWeek:
            let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
            return days >= 2 && days <= 7
        case .pastMonth:
            let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
            return days >= 8 && days <= 30
        case .month(let y, let m):
            let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
            guard days > 30 else { return false }
            let c = cal.dateComponents([.year, .month], from: date)
            return c.year == y && c.month == m
        }
    }
}

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

struct ReCliprMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: ClipboardStore

    @AppStorage("viewMode") private var viewModeRaw: String = ViewMode.list.rawValue
    @State private var copiedItemID: UUID?
    @State private var showClearConfirmation = false
    @State private var dateFilter: DateFilter = .all

    private var viewMode: ViewMode {
        ViewMode(rawValue: viewModeRaw) ?? .list
    }

    // Items after applying both the text search and the selected date filter
    private var displayedItems: [ClipItem] {
        let base = store.filteredItems
        guard dateFilter != .all else { return base }
        return base.filter { dateFilter.matches($0.date) }
    }

    // Only the filters that have at least one matching item in the full history
    private var availableFilters: [DateFilter] {
        let all = store.items
        guard !all.isEmpty else { return [] }

        var result: [DateFilter] = [.all]
        for f in [DateFilter.today, .yesterday, .pastWeek, .pastMonth] {
            if all.contains(where: { f.matches($0.date) }) { result.append(f) }
        }

        // Collect unique calendar months older than 30 days, most recent first, max 4
        let cal = Calendar.current
        let now = Date()
        var seen = Set<DateFilter>()
        for item in all {
            let days = cal.dateComponents([.day], from: item.date, to: now).day ?? 0
            guard days > 30 else { continue }
            let c = cal.dateComponents([.year, .month], from: item.date)
            guard let y = c.year, let m = c.month else { continue }
            seen.insert(.month(year: y, month: m))
        }
        let sorted = seen.sorted {
            if case .month(let y1, let m1) = $0, case .month(let y2, let m2) = $1 {
                return y1 == y2 ? m1 > m2 : y1 > y2
            }
            return false
        }.prefix(4)
        result.append(contentsOf: sorted)
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field + list/grid toggle
            HStack(spacing: 6) {
                TextField("Search Clipboard", text: $store.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                Button {
                    viewModeRaw = viewMode == .list
                        ? ViewMode.grid.rawValue
                        : ViewMode.list.rawValue
                } label: {
                    Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help(viewMode == .list ? "Switch to grid view" : "Switch to list view")
            }

            // Date filter pills — only shown when more than one bucket has items
            if availableFilters.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableFilters, id: \.self) { filter in
                            Button(filter.label) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    dateFilter = filter
                                }
                            }
                            .buttonStyle(FilterPillStyle(isSelected: dateFilter == filter))
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.vertical, 2)
                }
            }

            if displayedItems.isEmpty {
                Text(store.searchQuery.isEmpty && dateFilter == .all
                     ? "No clipboard history yet"
                     : "No items match this filter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    if viewMode == .list {
                        listContent
                    } else {
                        gridContent
                    }
                }
                .frame(minHeight: 160, maxHeight: 400)
            }

            Divider()

            Button("Preferences...") { openWindow(id: "preferences") }

            if showClearConfirmation {
                HStack(spacing: 8) {
                    Text("Clear all history?")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { showClearConfirmation = false }
                        .controlSize(.small)
                    Button("Clear All", role: .destructive) {
                        store.clearAll()
                        showClearConfirmation = false
                    }
                    .controlSize(.small)
                }
            } else {
                Button("Clear History") { showClearConfirmation = true }
            }

            Button("Quit ReClipr") { NSApp.terminate(nil) }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            store.searchQuery = ""
            dateFilter = .all
        }
    }

    // MARK: - List View

    @ViewBuilder
    private var listContent: some View {
        let items = Array(displayedItems.prefix(50))
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                listRow(item)
                if index < items.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func listRow(_ item: ClipItem) -> some View {
        Button { handleCopy(item) } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let img = item.content.image {
                    // Full-width image preview so it's actually legible
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .topTrailing) {
                            if copiedItemID == item.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                    .padding(4)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                } else {
                    HStack(alignment: .top) {
                        Text(item.content.displayTitle)
                            .font(.system(size: 12))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if copiedItemID == item.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                metaRow(for: item)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) { store.deleteItem(item) }
        }
    }

    // MARK: - Grid View

    private let gridColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    @ViewBuilder
    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(displayedItems.prefix(50)) { item in
                gridCell(item)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func gridCell(_ item: ClipItem) -> some View {
        Button { handleCopy(item) } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    gridPreview(for: item)
                    if copiedItemID == item.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(gridLabel(for: item))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) { store.deleteItem(item) }
        }
    }

    @ViewBuilder
    private func gridPreview(for item: ClipItem) -> some View {
        if let img = item.content.image {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(minHeight: 72, maxHeight: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Text(item.content.displayTitle)
                .font(.system(size: 10))
                .lineLimit(5)
                .padding(6)
                .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 90, alignment: .topLeading)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func gridLabel(for item: ClipItem) -> String {
        item.sourcePageTitle ?? item.sourceAppName ?? item.content.displayTitle
    }

    // MARK: - Shared Helpers

    @ViewBuilder
    private func metaRow(for item: ClipItem) -> some View {
        HStack(spacing: 4) {
            if let title = item.sourcePageTitle {
                Image(systemName: "globe")
                Text(title).lineLimit(1)
                Text("·")
            } else if let url = item.sourcePageURL,
                      url.scheme == "https" || url.scheme == "http",
                      let host = url.host, !host.isEmpty {
                let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                Image(systemName: "globe")
                Text(domain).lineLimit(1)
                Text("·")
            } else if let appName = item.sourceAppName {
                Text(appName)
                Text("·")
            }
            Text(item.date, style: .relative)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func handleCopy(_ item: ClipItem) {
        store.copyToClipboard(item)
        withAnimation(.easeIn(duration: 0.1)) {
            copiedItemID = item.id
        }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            dismiss()
        }
    }
}
