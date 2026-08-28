//
//  DateFilter.swift
//  ReClipr
//
//  Extracted from ReCliprMenuView so both presentation surfaces can share it, and so
//  the expensive part — working out which buckets actually contain anything — can
//  live on the store and be computed once per history change instead of once per
//  render. That mattered little in a mouse-driven popover; in the overlay the view
//  re-renders on every keystroke.
//

import Foundation

private let monthOnlyFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMMM"; return f
}()

private let monthYearFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
}()

enum DateFilter: Hashable, Sendable {
    case all, today, yesterday, pastWeek, pastMonth
    case month(year: Int, month: Int)

    var label: String {
        switch self {
        case .all:       return "All"
        case .today:     return "Today"
        case .yesterday: return "Yesterday"
        case .pastWeek:  return "Past Week"
        case .pastMonth: return "Past Month"
        case .month(let year, let month):
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = 1
            guard let date = Calendar.current.date(from: comps) else { return "" }
            let thisYear = Calendar.current.component(.year, from: Date())
            return year == thisYear
                ? monthOnlyFormatter.string(from: date)
                : monthYearFormatter.string(from: date)
        }
    }

    func matches(_ date: Date, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        switch self {
        case .all:
            return true
        case .today:
            return cal.isDateInToday(date)
        case .yesterday:
            return cal.isDateInYesterday(date)
        case .pastWeek:
            let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
            return days >= 2 && days <= 7
        case .pastMonth:
            let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
            return days >= 8 && days <= 30
        case .month(let y, let m):
            let days = cal.dateComponents([.day], from: date, to: now).day ?? 0
            guard days > 30 else { return false }
            let c = cal.dateComponents([.year, .month], from: date)
            return c.year == y && c.month == m
        }
    }

    /// Buckets that contain at least one item, newest first, capped at four trailing
    /// months. Returns an empty array — not [.all] — when there is nothing to filter,
    /// so the caller can hide the row entirely.
    static func available(for items: [ClipItem], now: Date = Date()) -> [DateFilter] {
        guard !items.isEmpty else { return [] }

        var result: [DateFilter] = [.all]
        for filter in [DateFilter.today, .yesterday, .pastWeek, .pastMonth]
        where items.contains(where: { filter.matches($0.date, now: now) }) {
            result.append(filter)
        }

        let cal = Calendar.current
        var months = Set<DateFilter>()
        for item in items {
            let days = cal.dateComponents([.day], from: item.date, to: now).day ?? 0
            guard days > 30 else { continue }
            let c = cal.dateComponents([.year, .month], from: item.date)
            guard let y = c.year, let m = c.month else { continue }
            months.insert(.month(year: y, month: m))
        }

        let sorted = months.sorted {
            guard case .month(let y1, let m1) = $0, case .month(let y2, let m2) = $1 else { return false }
            return y1 == y2 ? m1 > m2 : y1 > y2
        }.prefix(4)

        result.append(contentsOf: sorted)
        return result
    }
}
