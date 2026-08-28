//
//  ClipboardMonitor.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
import AppKit
import UniformTypeIdentifiers

private extension URL {
    var isWebURL: Bool { scheme == "https" || scheme == "http" }
}

struct ClipWebMeta {
    let sourceURL: URL?
    let pageTitle: String?
}

final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    var onNewCopy: (@MainActor (ClipContent, ClipWebMeta, String?) -> Void)?

    deinit {
        stop()
    }

    func start() {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] _ in self?.checkPasteboard()
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // Call after programmatically writing to the pasteboard so the monitor
    // doesn't re-detect our own write as an incoming copy.
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Clears the pasteboard, runs `body`, and records the resulting changeCount in
    /// one synchronous main-thread block, so the monitor can never observe our own
    /// write as an incoming copy. Previously the write and the sync were separate
    /// statements, which was safe only as long as nothing awaited between them.
    ///
    /// `body` must not suspend.
    func writeToPasteboard(_ body: @MainActor (NSPasteboard) -> Void) {
        let pb = NSPasteboard.general
        pb.clearContents()
        body(pb)
        lastChangeCount = pb.changeCount
    }

    // MARK: - Web metadata extraction

    private static func webMeta(from pasteboard: NSPasteboard) -> ClipWebMeta {
        let pageTitle = pasteboard.string(forType: .init("public.url-name"))

        // 1. public.url — set by browsers for link copies and some text copies
        if let str = pasteboard.string(forType: .init("public.url")),
           let url = URL(string: str), url.isWebURL {
            return ClipWebMeta(sourceURL: url, pageTitle: pageTitle)
        }

        // 2. Apple Web Archive — WebKit/Safari writes this for text selections;
        //    the source page URL is nested at WebMainResource.WebResourceURL
        if let data = pasteboard.data(forType: .init("Apple Web Archive pasteboard type")),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dict = plist as? [String: Any],
           let main = dict["WebMainResource"] as? [String: Any],
           let urlString = main["WebResourceURL"] as? String,
           let url = URL(string: urlString), url.isWebURL {
            return ClipWebMeta(sourceURL: url, pageTitle: pageTitle)
        }

        // 3. org.chromium.source-url — Chrome / Chromium text selections
        if let str = pasteboard.string(forType: .init("org.chromium.source-url")),
           let url = URL(string: str), url.isWebURL {
            return ClipWebMeta(sourceURL: url, pageTitle: pageTitle)
        }

        return ClipWebMeta(sourceURL: nil, pageTitle: pageTitle)
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let webMeta = Self.webMeta(from: pasteboard)
        guard let snapshot = Self.snapshot(pasteboard) else { return }

        // Everything expensive — hashing, PNG compression, copying file bytes —
        // happens off the main thread so a large screenshot never stalls the poll.
        let callback = onNewCopy
        Task.detached(priority: .utility) {
            let classified = PasteboardClassifier.classify(snapshot)
            guard let (content, sidecar) = ClipIngestor.makeContent(from: classified) else { return }
            await MainActor.run { callback?(content, webMeta, sidecar) }
        }
    }

    /// Reads everything needed off the pasteboard in one main-thread pass.
    /// NSPasteboard cannot be touched from another thread, so nothing but plain
    /// values crosses the boundary.
    private static func snapshot(_ pb: NSPasteboard) -> PasteboardSnapshot? {
        let types = pb.types?.map(\.rawValue) ?? []

        // Bail immediately on a concealed or transient copy, before reading any bytes.
        if types.contains(where: PasteboardClassifier.skipMarkers.contains) {
            return PasteboardSnapshot(types: types, fileURLs: [], string: nil,
                                      payloadUTI: nil, payloadData: nil,
                                      suggestedName: nil, sidecarText: nil)
        }

        let fileURLs = (pb.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let string = pb.string(forType: .string)

        var payloadUTI: String?
        var payloadData: Data?
        var sidecar: String?

        if fileURLs.isEmpty {
            // Preferred, explicitly-named types first.
            for type in PasteboardClassifier.preferredTypes {
                guard let data = pb.data(forType: .init(type.identifier)), !data.isEmpty else { continue }
                payloadUTI = type.identifier
                payloadData = data
                if type.conforms(to: .rtf) || type.conforms(to: .rtfd) { sidecar = string }
                break
            }

            // Then any other declared, concrete type — this is what catches audio,
            // video and app-specific documents.
            if payloadData == nil,
               let type = PasteboardClassifier.genericDataType(in: types),
               let data = pb.data(forType: .init(type.identifier)), !data.isEmpty {
                payloadUTI = type.identifier
                payloadData = data
            }

            // Last resort for providers that offer images in odd flavours.
            if payloadData == nil,
               let image = NSImage(pasteboard: pb),
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                payloadUTI = UTType.png.identifier
                payloadData = png
            }
        }

        let suggestedName = pb.string(forType: .init("public.file-name"))
            ?? pb.string(forType: .init("public.url-name"))

        return PasteboardSnapshot(types: types,
                                  fileURLs: fileURLs,
                                  string: string,
                                  payloadUTI: payloadUTI,
                                  payloadData: payloadData,
                                  suggestedName: suggestedName,
                                  sidecarText: sidecar)
    }
}
