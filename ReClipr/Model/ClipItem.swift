//
//  ClipItem.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
import Foundation

struct ClipItem: Identifiable, Codable, Sendable {
    let id: UUID
    let content: ClipContent
    let date: Date

    // Source Info
    let sourceBundleID: String?
    let sourceAppName: String?

    // Web metadata populated from pasteboard when copying from browsers
    let sourcePageURL: URL?
    let sourcePageTitle: String?

    /// Plain-text rendering kept alongside a rich payload (RTF, RTFD) so search still
    /// matches the words the user can see. Absent for every other content kind.
    let sidecarText: String?

    /// Pinned clips sort to the top and are exempt from the history limit and the
    /// storage budget. Without this, the snippets you reuse most are exactly the ones
    /// that age out fastest.
    var isPinned: Bool = false

    nonisolated init(
        id: UUID = UUID(),
        content: ClipContent,
        date: Date = Date(),
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        sourcePageURL: URL? = nil,
        sourcePageTitle: String? = nil,
        sidecarText: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.content = content
        self.date = date
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.sourcePageURL = sourcePageURL
        self.sourcePageTitle = sourcePageTitle
        self.sidecarText = sidecarText
        self.isPinned = isPinned
    }
}

// MARK: - Codable
//
// Written out rather than synthesised. Swift's synthesised Decodable ignores a
// property's default value and treats it as a required key, so adding `isPinned`
// made every previously saved clip fail to decode — and the next save would have
// written an empty history over the top. Any field added here must be decoded with
// decodeIfPresent for the same reason.

extension ClipItem {
    private enum CodingKeys: String, CodingKey {
        case id, content, date
        case sourceBundleID, sourceAppName, sourcePageURL, sourcePageTitle
        case sidecarText, isPinned
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        content = try c.decode(ClipContent.self, forKey: .content)
        date = try c.decode(Date.self, forKey: .date)
        sourceBundleID = try c.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName)
        sourcePageURL = try c.decodeIfPresent(URL.self, forKey: .sourcePageURL)
        sourcePageTitle = try c.decodeIfPresent(String.self, forKey: .sourcePageTitle)
        sidecarText = try c.decodeIfPresent(String.self, forKey: .sidecarText)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(sourceBundleID, forKey: .sourceBundleID)
        try c.encodeIfPresent(sourceAppName, forKey: .sourceAppName)
        try c.encodeIfPresent(sourcePageURL, forKey: .sourcePageURL)
        try c.encodeIfPresent(sourcePageTitle, forKey: .sourcePageTitle)
        try c.encodeIfPresent(sidecarText, forKey: .sidecarText)
        if isPinned { try c.encode(true, forKey: .isPinned) }
    }
}

extension ClipItem {
    /// The plain-text rendering of this clip, when there is one: the text itself, or
    /// the sidecar kept alongside a rich payload. Nil for images and files, which
    /// have no sensible text form.
    var plainText: String? {
        if case .text(let text) = content { return text }
        return sidecarText
    }

    var canCopyAsPlainText: Bool { plainText != nil }
}
