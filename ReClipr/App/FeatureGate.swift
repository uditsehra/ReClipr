//
//  FeatureGate.swift
//  ReClipr
//
//  Everything is free today. This exists so that introducing a paid tier later is a
//  provider swap plus a purchase sheet, rather than hunting down every place a limit
//  would need to apply.
//

import Foundation

enum Feature: String, CaseIterable, Sendable {
    case overlay
    case unlimitedHistory
    case largeFileCapture
    case screenshotWatch
    case extendedStorageBudget
}

protocol EntitlementProvider: Sendable {
    nonisolated func isUnlocked(_ feature: Feature) -> Bool
}

/// The only provider that ships right now.
struct FreeEverythingProvider: EntitlementProvider {
    nonisolated func isUnlocked(_ feature: Feature) -> Bool { true }
}

enum FeatureGate {
    // TODO(monetisation): replace with a StoreKit 2 backed provider that reads the
    // current entitlement, and present a purchase sheet where isUnlocked returns
    // false. No call site should need to change.
    nonisolated(unsafe) static var provider: EntitlementProvider = FreeEverythingProvider()

    nonisolated static func isUnlocked(_ feature: Feature) -> Bool {
        provider.isUnlocked(feature)
    }
}
