//
//  ClipboardMonitor.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
import AppKit

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

    var onNewCopy: (@MainActor (ClipContent, ClipWebMeta) -> Void)?

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

        // Priority 1: File URLs only (excludes http/https web URLs)
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let first = urls.first {
            onNewCopy?(.file(first), webMeta)
            return
        }

        // Priority 2: Images — offload PNG compression + disk write to a background task
        // so the 0.5 s timer tick is never blocked by a large screenshot.
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation {
            let meta = webMeta
            let callback = onNewCopy
            Task.detached(priority: .utility) {
                guard let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { return }
                let hash = ImageStore.shared.save(png)
                await MainActor.run { callback?(.image(hash), meta) }
            }
            return
        }

        // Priority 3: Text
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onNewCopy?(.text(text), webMeta)
        }
    }
}
