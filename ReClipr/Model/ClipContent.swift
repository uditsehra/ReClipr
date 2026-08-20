//
//  ClipContent.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import AppKit

enum ClipContent: Codable, Equatable {
    case text(String)
    /// Associated value is the SHA-256 hex string of the PNG file stored in ImageStore.
    case image(String)
    case file(URL)

    enum CodingKeys: String, CodingKey {
        case type, text, imageHash, imageData, fileURL
    }

    enum ContentType: String, Codable {
        case text, image, file
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)

        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))

        case .image:
            if let hash = try? container.decode(String.self, forKey: .imageHash) {
                self = .image(hash)
            } else if let data = try? container.decode(Data.self, forKey: .imageData) {
                // Migrate legacy inline image data → disk file on first load
                let hash = ImageStore.shared.save(data)
                self = .image(hash)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .imageHash, in: container,
                    debugDescription: "Missing imageHash or imageData"
                )
            }

        case .file:
            self = .file(try container.decode(URL.self, forKey: .fileURL))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)

        case .image(let hash):
            try container.encode(ContentType.image, forKey: .type)
            try container.encode(hash, forKey: .imageHash)

        case .file(let url):
            try container.encode(ContentType.file, forKey: .type)
            try container.encode(url, forKey: .fileURL)
        }
    }
}

extension ClipContent {
    static func == (lhs: ClipContent, rhs: ClipContent) -> Bool {
        switch (lhs, rhs) {
        case let (.text(a), .text(b)):
            return a == b
        case let (.image(a), .image(b)):
            return a == b  // Hash comparison: O(64) vs O(n·bytes)
        case let (.file(a), .file(b)):
            return a.standardizedFileURL == b.standardizedFileURL
        default:
            return false
        }
    }

    var searchableText: String {
        switch self {
        case .text(let text): return text
        case .file(let url):  return url.lastPathComponent
        case .image:          return "[image]"
        }
    }
}

// MARK: - UI Helpers

extension ClipContent {
    var displayTitle: String {
        switch self {
        case .text(let text):
            return text.count > 400 ? String(text.prefix(400)) + "…" : text
        case .image:
            return "[Image]"
        case .file(let url):
            return url.lastPathComponent
        }
    }

    var image: NSImage? {
        guard case .image(let hash) = self else { return nil }
        return ImageCache.shared.image(for: hash)
    }
}
