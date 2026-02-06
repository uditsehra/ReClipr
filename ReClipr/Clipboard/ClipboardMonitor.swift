//
//  ClipboardMoitor.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//
import AppKit

final class ClipboardMonitor{
    //var objectWillChange: ObservableObjectPublisher
    
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    
    var onNewCopy: ((ClipContent) -> Void)?
    
    func start(){
        stop()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true){
            [weak self] _ in self?.checkPasteboard()
        }
        
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func stop(){
        timer?.invalidate()
        timer = nil
    }
    
    private func checkPasteboard(){
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        //Priority 1 : Files
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: nil
        ) as? [URL], let first = urls.first{
            onNewCopy?(.file(first))
            return
        }
        
        //Priority 2: Images
        if let image = NSImage(pasteboard: pasteboard),
            let tiff = image.tiffRepresentation{
                onNewCopy?(.image(tiff))
                return
            
        }
        
        //Priority 3: Text
        if let text = pasteboard.string(forType: .string){
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onNewCopy?(.text(text))
                return
            }
        }
    }
}
