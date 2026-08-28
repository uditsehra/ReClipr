//
//  ClipPreviewOverlay.swift
//  ReClipr
//
//  Full-size look at one clip, opened by a long press or the space bar.
//
//  Deliberately drawn inside the panel rather than through QLPreviewPanel: Quick Look
//  opens its own window and takes key focus, which would break the "pick an item,
//  then ⌘V into the app you came from" flow the whole overlay is built around.
//

import AppKit
import SwiftUI

struct ClipPreviewOverlay: View {
    let item: ClipItem
    let onCopy: () -> Void
    let onClose: () -> Void

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            // Tapping anywhere outside the card dismisses.
            Rectangle()
                .fill(.black.opacity(0.45))
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)

                Divider()

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.content.displayTitle)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if let subtitle = item.content.subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Copy", action: onCopy)
                        .keyboardShortcut(.defaultAction)
                    Button("Close", action: onClose)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(maxWidth: 520, maxHeight: 420)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .shadow(radius: 24, y: 8)
            .padding(28)
        }
        .transition(.opacity)
        .task(id: item.id) { await loadThumbnail() }
    }

    @ViewBuilder
    private var content: some View {
        if let image = item.content.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if case .text(let text) = item.content {
            ScrollView {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            VStack(spacing: 10) {
                Image(systemName: item.content.symbolName)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(item.content.displayTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func loadThumbnail() async {
        switch item.content {
        case .blob(let ref):
            thumbnail = await ThumbnailProvider.shared.thumbnail(for: ref)
        case .files(let attachments):
            guard let only = attachments.first else { return }
            switch only {
            case .inline(let ref):    thumbnail = await ThumbnailProvider.shared.thumbnail(for: ref)
            case .reference(let ref): thumbnail = await ThumbnailProvider.shared.thumbnail(for: ref)
            }
        default:
            break
        }
    }
}
