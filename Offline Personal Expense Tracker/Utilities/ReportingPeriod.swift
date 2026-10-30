import Foundation

enum ReportingPeriod {
    static func calendar(firstWeekday: Int, timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = .current
        calendar.firstWeekday = min(7, max(1, firstWeekday))
        return calendar
    }

    static func window(
        for preset: PeriodPreset,
        customStart: Date,
        customEnd: Date,
        calendar: Calendar,
        now: Date = Date()
    ) -> ReportingWindow {
        switch preset {
        case .thisMonth:
            return monthWindow(containing: now, calendar: calendar)
        case .lastMonth:
            let thisMonth = monthWindow(containing: now, calendar: calendar)
            let previousAnchor = calendar.date(byAdding: .day, value: -1, to: thisMonth.start) ?? now
            return monthWindow(containing: previousAnchor, calendar: calendar)
        case .last3Months:
            let thisMonth = monthWindow(containing: now, calendar: calendar)
            let start = calendar.date(byAdding: .month, value: -2, to: thisMonth.start) ?? thisMonth.start
            return ReportingWindow(start: start, endExclusive: thisMonth.endExclusive)
        case .thisYear:
            let start = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
            return ReportingWindow(start: start, endExclusive: end)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let inclusiveEnd = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
            return ReportingWindow(start: start, endExclusive: end)
        }
    }

    static func monthWindow(containing date: Date, calendar: Calendar) -> ReportingWindow {
        let start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return ReportingWindow(start: start, endExclusive: end)
    }

    static func dayWindow(containing date: Date, calendar: Calendar) -> ReportingWindow {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return ReportingWindow(start: start, endExclusive: end)
    }

    static func label(for window: ReportingWindow, calendar: Calendar, style: DateFormatPreference) -> String {
        let endShown = calendar.date(byAdding: .second, value: -1, to: window.endExclusive) ?? window.start
        let startText = DisplayFormat.dateString(window.start, preference: style, calendar: calendar)
        let endText = DisplayFormat.dateString(endShown, preference: style, calendar: calendar)
        return "\(startText) – \(endText)"
    }
}
