//
//  Persistence.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import Foundation

final class Persistence {
    static let shared = Persistence()
    private init() {}
    
    private var appSupportURL: URL {
        let fm = FileManager.default
        let base = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        
        let dir = base!.appendingPathComponent("ReClipr", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var storeURL: URL {
        appSupportURL.appendingPathComponent("history.json")
    }
    
    func load() -> [ClipItem] {
        guard let data = try? Data(contentsOf: storeURL) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([ClipItem].self, from: data)
        }   catch{
            print("Failed to decode history", error)
            return []
        }

    }
    
    func save(_ items: [ClipItem]){
        guard let data = try? JSONEncoder().encode(items) else {
            return
        }
        try? data.write(to: storeURL, options: [.atomic])
    }
}
