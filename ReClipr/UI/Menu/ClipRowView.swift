//
//  ClipRowView.swift
//  ReClipr
//
//  One history row. History now holds PDFs, audio and arbitrary files as well as
//  text and images, so a row leads with a thumbnail where one exists and a type icon
//  otherwise, and clearly marks a clip whose payload has gone.
//

import SwiftUI

/// Shows a QuickLook preview once one is available, and the type's SF Symbol until
/// then. Never blocks: generation happens in a .task and the row renders immediately.
struct ClipTypeBadge: View {
    let content: ClipContent
    var size: CGFloat = 34

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: content.symbolName)
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: thumbnailKey) { await loadThumbnail() }
    }

    /// Identifies what should be previewed, so the task re-runs when the row is
    /// recycled onto a different clip.
    private var thumbnailKey: String? {
        switch content {
        case .text:
            return nil
        case .image(let ref), .blob(let ref):
            return ref.hash
        case .files(let attachments):
            guard attachments.count == 1 else { return nil }
            switch attachments[0] {
            case .inline(let ref):    return ref.hash
            case .reference(let ref): return ref.path
            }
        }
    }

    private func loadThumbnail() async {
        guard thumbnailKey != nil else { return }
        let provider = ThumbnailProvider.shared

        let result: NSImage?
        switch content {
        case .text:
            result = nil
        case .image(let ref), .blob(let ref):
            result = await provider.thumbnail(for: ref)
        case .files(let attachments):
            guard attachments.count == 1 else { result = nil; break }
            switch attachments[0] {
            case .inline(let ref):    result = await provider.thumbnail(for: ref)
            case .reference(let ref): result = await provider.thumbnail(for: ref)
            }
        }
        thumbnail = result
    }
}

/// The card each clip sits in. Selection and hover are both drawn here so the two
/// surfaces cannot drift apart.
struct ClipCardBackground: View {
    let isSelected: Bool
    var isHovered: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            // Material, not a translucent colour: a card has to stay readable over a
            // playing video as well as over glass, and a flat 7% wash does not.
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.12),
                                  lineWidth: isSelected ? 2 : 1)
            )
    }

    private var tint: Color {
        if isSelected { return Color.accentColor.opacity(0.22) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }
}

/// Marks a clip that points at a file it does not own. Worth the space: pasting one
/// of these in Finder acts on the user's original, and ⌥⌘V moves it outright.
struct LinkedFileBadge: View {
    var body: some View {
        Label("Linked", systemImage: "link")
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.tint.opacity(0.15))
            .foregroundStyle(.tint)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help("Points at the original file. Pasting copies it; ⌥⌘V in Finder moves it.")
    }
}

struct ClipMetaRow: View {
    let item: ClipItem

    var body: some View {
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
            Text(ClipTimestamp.string(for: item.date))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct ClipGridCell: View {
    let item: ClipItem
    let isSelected: Bool
    let showsCopiedTick: Bool
    var previewHeight: CGFloat = 108
    let onSelect: () -> Void
    let onDelete: () -> Void
    var onPreview: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onCopyPlain: (() -> Void)?

    @State private var isHovered = false

    private var isMissing: Bool { item.content.isResourceMissing }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    preview
                    if showsCopiedTick {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .padding(4)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .font(.caption)
                            .padding(4)
                    }
                }
                HStack(spacing: 3) {
                    if item.content.hasLinkedFiles && !isMissing {
                        Image(systemName: "link").font(.system(size: 8)).foregroundStyle(.tint)
                    }
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(ClipTimestamp.string(for: item.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Trailing the timestamp rather than over the thumbnail: the
                    // corner already carries the selection tick, and a pin sitting on
                    // the content obscures the very thing the card is showing.
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tint)
                            .help("Pinned — kept regardless of history limits")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(9)
            .opacity(isMissing ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isMissing)
        .background(ClipCardBackground(isSelected: isSelected, isHovered: isHovered))
        .onHover { isHovered = $0 }
        .onLongPressGesture(minimumDuration: 0.4) { onPreview() }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Quick Look", action: onPreview)
        Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
        if let onCopyPlain {
            Button("Copy as Plain Text", action: onCopyPlain)
        }
        Divider()
        Button("Delete", role: .destructive, action: onDelete)
    }

    /// Every tile is the same height, so the grid reads as a grid. Images fill and
    /// crop rather than letterboxing, which keeps thumbnails legible at this size.
    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.quaternary.opacity(0.6))

            if let image = item.content.image, !isMissing {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: previewHeight * 0.24))
                    .foregroundStyle(.orange)
            } else if item.content.kind == .text {
                Text(item.content.displayTitle)
                    .font(.system(size: 10))
                    .lineLimit(6)
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ClipTypeBadge(content: item.content, size: previewHeight * 0.62)
            }
        }
        .frame(height: previewHeight)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 1)
    }

    private var label: String {
        item.sourcePageTitle ?? item.sourceAppName ?? item.content.displayTitle
    }
}
