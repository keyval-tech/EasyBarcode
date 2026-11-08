import Foundation
import BarcodeKit

/// Time buckets for history filtering, evaluated against `createdAt`.
public enum HistoryTimeRange: String, CaseIterable {
    case all
    case today
    case last7
    case last30

    public var title: String {
        switch self {
        case .all: return "全部时间"
        case .today: return "今天"
        case .last7: return "近 7 天"
        case .last30: return "近 30 天"
        }
    }

    func includes(_ date: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .last7:
            return date >= now.addingTimeInterval(-7 * 86_400)
        case .last30:
            return date >= now.addingTimeInterval(-30 * 86_400)
        }
    }
}

/// The active history window filter; all fields combine with AND.
public struct HistoryFilter {
    /// Case-insensitive match against content and note.
    public var query: String = ""
    /// Tab name; `nil` shows all entries regardless of tabs.
    public var tab: String?
    public var format: BarcodeFormat?
    public var timeRange: HistoryTimeRange = .all
    public var onlyWithNotes: Bool = false

    public var isActive: Bool {
        !query.isEmpty || tab != nil || format != nil
            || timeRange != .all || onlyWithNotes
    }

    public init() {}
}

extension HistoryStore {
    /// Applies a filter over the stored entries, newest first.
    public func entries(matching filter: HistoryFilter) -> [HistoryEntry] {
        entries.filter { entry in
            if !filter.query.isEmpty {
                let query = filter.query.lowercased()
                let inDigits = entry.digits.lowercased().contains(query)
                let inNote = entry.note?.lowercased().contains(query) ?? false
                if !inDigits && !inNote { return false }
            }
            if let tab = filter.tab, !(entry.tabs ?? []).contains(tab) {
                return false
            }
            if let format = filter.format, entry.format != format {
                return false
            }
            if !filter.timeRange.includes(entry.createdAt) {
                return false
            }
            if filter.onlyWithNotes && (entry.note ?? "").isEmpty {
                return false
            }
            return true
        }
    }
}
