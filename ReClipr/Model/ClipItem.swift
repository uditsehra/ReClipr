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
    
    init(
        id: UUID = UUID(),
        content: ClipContent,
        date: Date = Date(),
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.id = id
        self.content = content
        self.date = date
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
    }
}
