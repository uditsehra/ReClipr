//
//  ClipItem.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
import Foundation

struct ClipItem: Identifiable, Codable {
    let id: UUID
    let content: ClipContent
    let date: Date

    // Source Info
    let sourceBundleID: String?
    let sourceAppName: String?

    // Web metadata populated from pasteboard when copying from browsers
    let sourcePageURL: URL?
    let sourcePageTitle: String?

    init(
        id: UUID = UUID(),
        content: ClipContent,
        date: Date = Date(),
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        sourcePageURL: URL? = nil,
        sourcePageTitle: String? = nil
    ) {
        self.id = id
        self.content = content
        self.date = date
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.sourcePageURL = sourcePageURL
        self.sourcePageTitle = sourcePageTitle
    }
}
