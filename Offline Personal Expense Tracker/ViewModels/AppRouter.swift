import Foundation

enum AppTab: Hashable {
    case dashboard
    case phones
    case transactions
    case budgets
    case reports
    case settings
}

@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .dashboard
    var createType: TransactionType?
}

@MainActor
@Observable
final class DashboardViewModel {
    var preset: PeriodPreset = .thisMonth
    var customStart: Date = Date()
    var customEnd: Date = Date()

    func window(calendar: Calendar, now: Date = Date()) -> ReportingWindow {
        ReportingPeriod.window(
            for: preset,
            customStart: customStart,
            customEnd: customEnd,
            calendar: calendar,
            now: now
        )
    }
}

@MainActor
@Observable
final class TransactionListViewModel {
    var filter = TransactionFilter()
    var pageSize = 40
    var useDateFilter = false
    var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var rangeEnd = Date()

    func preparedFilter() -> TransactionFilter {
        var current = filter
        if useDateFilter {
            current.start = rangeStart
            current.end = rangeEnd
        } else {
            current.start = nil
            current.end = nil
        }
        return current
    }

    func visible(
        _ transactions: [LedgerTransaction],
        calendar: Calendar
    ) -> [LedgerTransaction] {
        let values = transactions.map { $0.financeValue() }
        let ordered = TransactionQuery.apply(values, filter: preparedFilter(), calendar: calendar)
        let lookup = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        return ordered.compactMap { lookup[$0.id] }
    }
}

@MainActor
@Observable
final class ReportViewModel {
    var preset: PeriodPreset = .thisMonth
    var customStart: Date = Date()
    var customEnd: Date = Date()
    var granularity: TrendGranularity = .month
    var walletID: UUID?

    func window(calendar: Calendar, now: Date = Date()) -> ReportingWindow {
        ReportingPeriod.window(
            for: preset,
            customStart: customStart,
            customEnd: customEnd,
            calendar: calendar,
            now: now
        )
    }
}
