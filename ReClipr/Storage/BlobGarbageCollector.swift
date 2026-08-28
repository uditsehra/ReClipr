//
//  BlobGarbageCollector.swift
//  ReClipr
//
//  History used to be text and the occasional PNG; an item count was a fine proxy
//  for disk use. Once PDFs, audio and copied files land in the store that stops
//  being true, so space is bounded explicitly.
//
//  Two mechanisms, deliberately separate:
//
//  * Reference counting, which is about correctness — a blob nothing points at is
//    dead weight, and is removed as soon as the last clip referencing it goes.
//  * A total-size budget, which is about restraint — even live blobs get evicted
//    once the store outgrows what the user allowed.
//

import Foundation
import OSLog

enum BlobGarbageCollector {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ReClipr", category: "BlobGC")

    /// Deletes stored blobs that no clip references.
    ///
    /// There is a real window in which these accumulate: a blob is written as soon as
    /// a copy is classified, but history.json is only saved after a 1.5 s debounce, so
    /// a crash in between leaves bytes on disk that nothing will ever point at.
    /// Runs shortly after launch, off the main actor.
    nonisolated static func sweepOrphans(liveHashes: Set<String>) -> Int {
        let inventory = BlobStore.shared.inventory()
        guard !inventory.isEmpty else { return 0 }

        var reclaimed = 0
        for blob in inventory where !liveHashes.contains(blob.hash) {
            BlobStore.shared.delete(hash: blob.hash)
            reclaimed += 1
        }
        if reclaimed > 0 {
            logger.notice("Swept \(reclaimed, privacy: .public) orphaned blob(s)")
        }
        return reclaimed
    }

    nonisolated static func totalBytes() -> Int64 {
        BlobStore.shared.directorySize()
    }

    /// Chooses the oldest clips to drop until the store fits `budget`.
    ///
    /// Whole clips are evicted, never individual blobs: deleting a blob out from
    /// under a live row leaves a history entry that renders as a broken box, which is
    /// worse than the row being gone.
    ///
    /// Ordering is by age rather than true LRU. Real LRU needs a per-blob access
    /// timestamp, which means either a write on every render or trusting
    /// `.contentAccessDate`, which macOS updates unreliably. Age matches the existing
    /// history-limit semantics and needs no extra state.
    ///
    /// `items` must be newest-first, as ClipboardStore keeps them.
    nonisolated static func itemsToEvict(from items: [ClipItem], budget: Int64) -> Set<UUID> {
        guard budget > 0 else { return [] }

        var total: Int64 = 0
        for item in items { total += item.content.storedByteCount }
        guard total > budget else { return [] }

        var evicted = Set<UUID>()
        // Oldest first.
        for item in items.reversed() {
            guard total > budget else { break }
            // A pinned clip is kept deliberately; the budget is not permitted to
            // discard it.
            guard !item.isPinned else { continue }
            // Text and referenced files cost nothing on disk; evicting them would
            // shrink history without freeing a single byte.
            let cost = item.content.storedByteCount
            guard cost > 0 else { continue }
            evicted.insert(item.id)
            total -= cost
        }
        return evicted
    }
}
