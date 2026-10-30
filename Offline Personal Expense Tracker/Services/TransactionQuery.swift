import Foundation

enum TransactionQuery {
    static func apply(
        _ transactions: [FinanceTransaction],
        filter: TransactionFilter,
        calendar: Calendar
    ) -> [FinanceTransaction] {
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows = transactions.filter { transaction in
            if let type = filter.type, transaction.type != type { return false }
            if let categoryID = filter.categoryID, transaction.categoryID != categoryID { return false }
            if let walletID = filter.walletID,
               transaction.walletID != walletID,
               transaction.destinationWalletID != walletID {
                return false
            }
            if let start = filter.start, transaction.date < calendar.startOfDay(for: start) { return false }
            if let end = filter.end {
                let exclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
                if transaction.date >= exclusive { return false }
            }
            if !query.isEmpty {
                let haystack = ([transaction.title, transaction.merchant, transaction.notes] + transaction.tags)
                    .joined(separator: "\n")
                if !haystack.localizedStandardContains(query) { return false }
            }
            return true
        }
        switch filter.sort {
        case .dateNewest:
            rows.sort { lhs, rhs in
                if lhs.date == rhs.date { return lhs.title < rhs.title }
                return lhs.date > rhs.date
            }
        case .dateOldest:
            rows.sort { lhs, rhs in
                if lhs.date == rhs.date { return lhs.title < rhs.title }
                return lhs.date < rhs.date
            }
        case .amountHighest:
            rows.sort { lhs, rhs in
                if lhs.amount == rhs.amount { return lhs.date > rhs.date }
                return lhs.amount > rhs.amount
            }
        case .amountLowest:
            rows.sort { lhs, rhs in
                if lhs.amount == rhs.amount { return lhs.date > rhs.date }
                return lhs.amount < rhs.amount
            }
        }
        return rows
    }
}
