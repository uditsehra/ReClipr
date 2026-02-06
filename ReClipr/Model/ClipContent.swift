//
//  ClipContent.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import AppKit

enum ClipContent: Codable, Equatable {
    case text(String)
    case image(Data)
    case file(URL)
    
    enum CodingKeys: String, CodingKey {
        case type, text, imageData, fileURL
    }
    
    enum ContentType: String, Codable{
        case text, image, file
    }
    
    init (from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        
        switch type {
        case .text:
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        
        case .image:
            let data = try container.decode(Data.self, forKey: .imageData)
            self = .image(data)
            
        case .file:
            let url = try container.decode(URL.self, forKey: .fileURL)
            self = .file(url)
        }
    }
    
    func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
            
        case .image(let data):
            try container.encode(ContentType.image, forKey: .type)
            try container.encode(data, forKey: .imageData)
            
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
            return a == b
        case let (.file(a), .file(b)):
            // Compare standardized file URLs to avoid minor representation differences
            return a.standardizedFileURL == b.standardizedFileURL
        default:
            return false
        }
    }
    
    var searchableText: String {
        switch self{
            case .text(let text) :
                return text
            case .file(let url) :
                return url.lastPathComponent
            case .image :
                return "[image]"
        }
    }
}

// UI Helpers
extension ClipContent {
    var displayTitle: String {
        switch self {
        case .text(let text):
            return text.count > 80 ? String(text.prefix(80)) + "…" : text
            
        case .image: 
            return "[Image]"
            
        case .file(let url):
            return url.lastPathComponent
        }
    }
    
    var image: NSImage? {
        if case .image(let data) = self {
            return NSImage(data: data)
        }
        return nil
    }
}
