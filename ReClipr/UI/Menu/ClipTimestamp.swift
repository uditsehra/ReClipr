//
//  ClipTimestamp.swift
//  ReClipr
//
//  Rows used to render `Text(date, style: .relative)`, which is a live-updating
//  ticker: SwiftUI re-renders every visible row once a second forever. In a list of
//  200 clips that is pure overhead for information nobody watches change.
//
//  ClipItem.date is already stamped at creation, so the timestamp is formatted once
//  and cached by the minute it belongs to.
//

import Foundation

enum ClipTimestamp {
    private static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayAndTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    private static let withYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    /// Formatted once per (item, minute) rather than re-derived on every render.
    nonisolated(unsafe) private static var cache: [Int: String] = [:]
    private static let lock = NSLock()

    static func string(for date: Date, now: Date = Date()) -> String {
        let key = Int(date.timeIntervalSinceReferenceDate / 60)

        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        let calendar = Calendar.current
        let formatted: String
        if calendar.isDateInToday(date) {
            formatted = timeOnly.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatted = "Yesterday, " + timeOnly.string(from: date)
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatted = dayAndTime.string(from: date)
        } else {
            formatted = withYear.string(from: date)
        }

        lock.lock()
        // Bounded: a long session with a big history should not grow this without end.
        if cache.count > 2000 { cache.removeAll(keepingCapacity: true) }
        cache[key] = formatted
        lock.unlock()
        return formatted
    }
}
