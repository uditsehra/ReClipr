//
//  PasteboardClassifier.swift
//  ReClipr
//
//  Decides what a pasteboard actually contains. Kept separate from ClipboardMonitor
//  so the decision is pure, testable, and runs off the main thread: NSPasteboard is
//  main-thread-only, so the monitor snapshots it into a Sendable value first and the
//  classification happens on a background task.
//

import AppKit
import UniformTypeIdentifiers

/// A main-thread snapshot of the pasteboard, safe to hand to a background task.
struct PasteboardSnapshot: Sendable {
    let types: [String]
    let fileURLs: [URL]
    let string: String?
    let payloadUTI: String?
    let payloadData: Data?
    let suggestedName: String?
    /// Plain-text rendering of a rich payload, kept so search still works.
    let sidecarText: String?

    nonisolated init(types: [String],
                     fileURLs: [URL],
                     string: String?,
                     payloadUTI: String?,
                     payloadData: Data?,
                     suggestedName: String?,
                     sidecarText: String?) {
        self.types = types
        self.fileURLs = fileURLs
        self.string = string
        self.payloadUTI = payloadUTI
        self.payloadData = payloadData
        self.suggestedName = suggestedName
        self.sidecarText = sidecarText
    }
}

enum ClassifiedCopy: Sendable {
    case text(String)
    case fileURLs([URL])
    case data(Data, uti: String, suggestedName: String?, sidecarText: String?)
    case image(pngData: Data)
    /// Deliberately not recorded — a password or a transient scratch value.
    case ignored
    case none
}

enum PasteboardClassifier {

    /// Markers apps use to say "do not put this in a clipboard history".
    /// org.nspasteboard.ConcealedType is the convention password managers use; until
    /// now only the ignoredApps bundle-ID list protected against this, and the
    /// frontmost app at poll time is a race-prone proxy for the true source.
    nonisolated static let skipMarkers: Set<String> = [
        "org.nspasteboard.TransientType",
        "org.nspasteboard.ConcealedType",
        "de.petermaurer.TransientPasteboardType",
        "com.agilebits.onepassword",
        "com.typeit4me.clipping",
        "Pasteboard generator type",
    ]

    /// Types read explicitly, in preference order, before falling back to a generic
    /// scan. Order matters: a copy from Preview offers PDF and TIFF, and PDF is the
    /// higher-fidelity choice.
    nonisolated static let preferredTypes: [UTType] = [
        .pdf, .rtfd, .rtf, .png, .tiff,
    ]

    nonisolated static func classify(_ snapshot: PasteboardSnapshot) -> ClassifiedCopy {
        // 0. Never record what an app asked us not to.
        if snapshot.types.contains(where: skipMarkers.contains) { return .ignored }

        // 1. Files — all of them. Previously only the first URL was kept.
        if !snapshot.fileURLs.isEmpty { return .fileURLs(snapshot.fileURLs) }

        // 2/3. A typed payload the monitor already read for us.
        if let data = snapshot.payloadData, let uti = snapshot.payloadUTI, !data.isEmpty {
            if UTType(uti)?.conforms(to: .image) == true, uti == UTType.png.identifier {
                return .image(pngData: data)
            }
            return .data(data, uti: uti,
                         suggestedName: snapshot.suggestedName,
                         sidecarText: snapshot.sidecarText)
        }

        // 5. Plain text.
        if let text = snapshot.string,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }

        return .none
    }

    /// Picks the first declared, concrete data type worth storing. Excludes text and
    /// URLs (handled separately), dynamic `dyn.` placeholders with no real meaning,
    /// and Apple's internal pasteboard scaffolding.
    nonisolated static func genericDataType(in types: [String]) -> UTType? {
        for identifier in types {
            guard !identifier.hasPrefix("com.apple.pasteboard."),
                  !identifier.hasPrefix("com.apple.webarchive"),
                  let type = UTType(identifier),
                  type.isDeclared,
                  type.conforms(to: .data),
                  !type.conforms(to: .plainText),
                  !type.conforms(to: .url),
                  type.preferredFilenameExtension != nil
            else { continue }
            return type
        }
        return nil
    }
}
