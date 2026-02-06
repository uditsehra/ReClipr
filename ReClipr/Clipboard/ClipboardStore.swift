//
//  ClipboardStore.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
import SwiftUI
import Combine

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = [] {
        didSet{
            Persistence.shared.save(items)
        }
    }
    
    // Adding duplication policy
    @AppStorage("duplicatePolicy")
    private var duplicatePolicyRaw: String = DuplicatePolicy.none.rawValue
    @AppStorage("duplicateInterval")
    private var duplicateInterval: Double = 300 // seconds (5 min)
    
    //Adding IgnoredApps
    @AppStorage("ignoredApps")
    private var ignoredAppsRaw: String = "com.apple.keychainaccess"

    
    private var ignoredApps: Set<String> {
        Set(
            ignoredAppsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
    
    //Adding Source Info
    @Published var searchQuery: String = ""
    private func currentSourceApp() -> (bundleID: String?, name: String?){
        guard let app = NSWorkspace.shared.frontmostApplication else{
            return (nil, nil)
        }
        
        return (
            app.bundleIdentifier,
            app.localizedName
        )
    }
    
    var filteredItems: [ClipItem] {
        guard !searchQuery.isEmpty else {return items}
        
        let q = searchQuery.lowercased()
        
        return items.filter { item in
            //Search Content
            if item.content.searchableText.lowercased().contains(q){
                return true
            }
            //Search source app name
            if let appName = item.sourceAppName?.lowercased(),
               appName.contains(q) {
                return true
            }
            
            return false
        }
    }
    
    // Duplicates monitoring
    private var duplicatePolicy: DuplicatePolicy {
        DuplicatePolicy(rawValue: duplicatePolicyRaw) ?? .none
    }
    
    private let monitor = ClipboardMonitor()
    
    init() {
        items = Persistence.shared.load()
        monitor.onNewCopy = {
            [weak self] content in guard let self else {return}
            
            if let sourceApp = NSWorkspace.shared.frontmostApplication?
                .bundleIdentifier, ignoredApps.contains(sourceApp){
                return
            }
            
            self.addItem(content)
        }
    }
    
    func startMonitoring(){
        monitor.start()
    }
    
    func stopMonitoring(){
        monitor.stop()
    }
    
    private func addItem(_ content: ClipContent) {
        let now = Date()
        
        if let existingIndex = items.firstIndex(where: { $0.content == content}){
            let existingItem = items[existingIndex]
            
            switch duplicatePolicy{
            case .none:
                items.remove(at: existingIndex)
                items.insert(existingItem, at: 0)
                
            case .timed:
                let elapsed = now.timeIntervalSince(existingItem.date)
                
                if elapsed >= duplicateInterval {
                    let source = currentSourceApp()
                    let newItem = ClipItem(
                        content: content,
                        sourceBundleID: source.bundleID,
                        sourceAppName: source.name
                    )
                    items.insert(newItem, at: 0)
                } else {
                    items.remove(at: existingIndex)
                    items.insert(existingItem, at: 0)
                }
                
            case .always:
                let source = currentSourceApp()
                let newItem = ClipItem(
                    content: content,
                    sourceBundleID: source.bundleID,
                    sourceAppName: source.name
                )
                items.insert(newItem, at: 0)
            }
        } else {
//
//            let item = ClipItem(content: content)
//            items.insert(item, at: 0)
            let source = currentSourceApp()
            let item = ClipItem(
                content: content,
                sourceBundleID: source.bundleID,
                sourceAppName: source.name
            )
            items.insert(item, at: 0)
        }
    }
    
    func copyToClipboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.content {
        case .text(let text):
            pb.setString(text, forType: .string)
            
        case .image(let data):
            if let image = NSImage(data: data) {
                pb.writeObjects([image])
            }
            
        case .file(let url):
            pb.writeObjects([url as NSURL])
        }
    }
    
    func clearAll() {
        items.removeAll()
    }
    
}

