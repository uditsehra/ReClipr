//
//  StorageUsageModel.swift
//  ReClipr
//
//  Disk usage readout for the Storage tab.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class StorageUsageModel: ObservableObject {
    @Published private(set) var bytes: Int64?
    @Published private(set) var isCalculating = false

    func refresh() {
        guard !isCalculating else { return }
        isCalculating = true
        // Task.detached, not Task: default actor isolation is MainActor here, so a
        // plain Task would walk the whole blob directory on the main thread and
        // freeze the window.
        Task.detached(priority: .utility) {
            let total = BlobStore.shared.directorySize()
            await MainActor.run {
                self.bytes = total
                self.isCalculating = false
            }
        }
    }

    func clearCache(store: ClipboardStore) {
        store.clearAll()
        refresh()
    }

    var formatted: String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func fraction(of budget: Int) -> Double {
        guard budget > 0, let bytes else { return 0 }
        return min(1, Double(bytes) / Double(budget))
    }
}
