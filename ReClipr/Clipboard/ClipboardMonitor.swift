//
//  ClipboardMonitor.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
import AppKit

struct ClipWebMeta {
    let sourceURL: URL?
    let pageTitle: String?
}

final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    var onNewCopy: ((ClipContent, ClipWebMeta) -> Void)?

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

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        // Browsers write public.url (source page URL) and public.url-name (page/link title)
        let webURL = pasteboard.string(forType: .init("public.url")).flatMap { URL(string: $0) }
        let pageTitle = pasteboard.string(forType: .init("public.url-name"))
        let webMeta = ClipWebMeta(sourceURL: webURL, pageTitle: pageTitle)

        // Priority 1: File URLs only (excludes http/https web URLs)
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let first = urls.first {
            onNewCopy?(.file(first), webMeta)
            return
        }

        // Priority 2: Images — compress to PNG, save to disk, reference by hash
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            let hash = ImageStore.shared.save(png)
            onNewCopy?(.image(hash), webMeta)
            return
        }

        // Priority 3: Text
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onNewCopy?(.text(text), webMeta)
        }
    }
}
