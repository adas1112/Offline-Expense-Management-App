import Foundation

struct RecurrencePlan: Equatable, Sendable {
    var id: UUID
    var frequency: RecurrenceFrequency
    var start: Date
    var end: Date?
    var isPaused: Bool
    var emittedKeys: Set<String>
}

enum RecurringScheduler {
    static let stepLimit = 800

    static func occurrenceKey(ruleID: UUID, date: Date, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(ruleID.uuidString)#\(formatter.string(from: day))"
    }

    static func occurrenceDates(plan: RecurrencePlan, through: Date, calendar: Calendar) -> [Date] {
        guard !plan.isPaused else { return [] }
        var dates: [Date] = []
        var cursor = plan.start
        var steps = 0
        while cursor <= through && steps < stepLimit {
            steps += 1
            if let end = plan.end, cursor > end { break }
            let key = occurrenceKey(ruleID: plan.id, date: cursor, calendar: calendar)
            if !plan.emittedKeys.contains(key) {
                dates.append(cursor)
            }
            guard let next = advance(cursor, frequency: plan.frequency, calendar: calendar), next > cursor else { break }
            cursor = next
        }
        return dates
    }

    /// Keys for occurrences strictly after `pausedAt` through `through`, used so a paused gap is not backfilled.
    static func keysToSuppress(
        plan: RecurrencePlan,
        pausedAt: Date,
        through: Date,
        calendar: Calendar
    ) -> [String] {
        var keys: [String] = []
        var cursor = plan.start
        var steps = 0
        while cursor <= through && steps < stepLimit {
            steps += 1
            if let end = plan.end, cursor > end { break }
            if cursor > pausedAt {
                keys.append(occurrenceKey(ruleID: plan.id, date: cursor, calendar: calendar))
            }
            guard let next = advance(cursor, frequency: plan.frequency, calendar: calendar), next > cursor else { break }
            cursor = next
        }
        return keys
    }

    static func advance(_ date: Date, frequency: RecurrenceFrequency, calendar: Calendar) -> Date? {
        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date)
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}
