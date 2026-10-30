import Foundation

/// Single accounting implementation for the dashboard, wallets, charts, and exports.
///
/// Rules for a reporting window:
/// - Income is the sum of income transactions in the base currency.
/// - Expenses are the sum of expense transactions in the base currency.
/// - Net cash flow is income minus expenses.
/// - Transfers never change consolidated income, expenses, or net worth.
/// - Asset balance = opening + inflows − outflows.
/// - Credit-card balance is a liability (amount owed) = opening + charges − payments/refunds.
/// - Net worth = asset balances − credit-card liabilities, in the base currency only.
/// - Wallets in another currency are excluded. The app does not invent an exchange rate.
enum LedgerCalculator {
    static func walletBalances(
        wallets: [FinanceWallet],
        transactions: [FinanceTransaction]
    ) -> [UUID: Decimal] {
        var balances: [UUID: Decimal] = [:]
        for wallet in wallets {
            balances[wallet.id] = Money.rounded(wallet.openingBalance, currencyCode: wallet.currencyCode)
        }
        let walletMap = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        for transaction in transactions {
            apply(transaction, wallets: walletMap, balances: &balances)
        }
        for wallet in wallets {
            if let balance = balances[wallet.id] {
                balances[wallet.id] = Money.rounded(balance, currencyCode: wallet.currencyCode)
            }
        }
        return balances
    }

    static func balance(
        of wallet: FinanceWallet,
        wallets: [FinanceWallet],
        transactions: [FinanceTransaction]
    ) -> Decimal {
        walletBalances(wallets: wallets, transactions: transactions)[wallet.id]
            ?? Money.rounded(wallet.openingBalance, currencyCode: wallet.currencyCode)
    }

    static func netWorth(
        wallets: [FinanceWallet],
        transactions: [FinanceTransaction],
        baseCurrency: String,
        before: Date? = nil
    ) -> Decimal {
        let filtered: [FinanceTransaction]
        if let before {
            filtered = transactions.filter { $0.date < before }
        } else {
            filtered = transactions
        }
        let balances = walletBalances(wallets: wallets, transactions: filtered)
        var total = Decimal.zero
        for wallet in wallets where wallet.currencyCode == baseCurrency {
            let balance = balances[wallet.id] ?? wallet.openingBalance
            total += wallet.isLiability ? -balance : balance
        }
        return Money.rounded(total, currencyCode: baseCurrency)
    }

    static func qualifying(
        _ transactions: [FinanceTransaction],
        type: TransactionType,
        window: ReportingWindow,
        baseCurrency: String,
        categoryID: UUID? = nil,
        walletID: UUID? = nil
    ) -> [FinanceTransaction] {
        transactions.filter { transaction in
            guard transaction.type == type else { return false }
            guard transaction.currencyCode == baseCurrency else { return false }
            guard window.contains(transaction.date) else { return false }
            if let categoryID, transaction.categoryID != categoryID { return false }
            if let walletID, transaction.walletID != walletID, transaction.destinationWalletID != walletID {
                return false
            }
            if type != .transfer, let walletID, transaction.walletID != walletID { return false }
            return true
        }
    }

    static func total(
        _ transactions: [FinanceTransaction],
        type: TransactionType,
        window: ReportingWindow,
        baseCurrency: String,
        categoryID: UUID? = nil,
        walletID: UUID? = nil
    ) -> Decimal {
        let rows = qualifying(
            transactions,
            type: type,
            window: window,
            baseCurrency: baseCurrency,
            categoryID: categoryID,
            walletID: walletID
        )
        let sum = rows.reduce(Decimal.zero) { $0 + $1.amount }
        return Money.rounded(sum, currencyCode: baseCurrency)
    }

    static func categoryTotals(
        _ transactions: [FinanceTransaction],
        type: TransactionType,
        window: ReportingWindow,
        baseCurrency: String,
        categories: [FinanceCategory],
        walletID: UUID? = nil
    ) -> [CategoryTotal] {
        let rows = qualifying(
            transactions,
            type: type,
            window: window,
            baseCurrency: baseCurrency,
            walletID: walletID
        )
        var sums: [UUID: Decimal] = [:]
        let uncategorized = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        for row in rows {
            let key = row.categoryID ?? uncategorized
            sums[key, default: .zero] += row.amount
        }
        let grand = sums.values.reduce(Decimal.zero, +)
        let lookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let totals = sums.map { key, amount -> CategoryTotal in
            let rounded = Money.rounded(amount, currencyCode: baseCurrency)
            let fraction: Decimal = grand > 0 ? rounded / Money.rounded(grand, currencyCode: baseCurrency) : 0
            if key == uncategorized {
                return CategoryTotal(
                    id: key,
                    name: "Uncategorized",
                    amount: rounded,
                    colorHex: "8E8E93",
                    iconName: "questionmark.circle",
                    fraction: fraction
                )
            }
            let category = lookup[key]
            return CategoryTotal(
                id: key,
                name: category?.name ?? "Category",
                amount: rounded,
                colorHex: category?.colorHex ?? "1A6B4A",
                iconName: category?.iconName ?? "tag",
                fraction: fraction
            )
        }
        return totals.sorted { lhs, rhs in
            if lhs.amount == rhs.amount { return lhs.name < rhs.name }
            return lhs.amount > rhs.amount
        }
    }

    static func walletExpenseTotals(
        _ transactions: [FinanceTransaction],
        window: ReportingWindow,
        baseCurrency: String,
        wallets: [FinanceWallet],
        walletID: UUID? = nil
    ) -> [WalletTotal] {
        let rows = qualifying(
            transactions,
            type: .expense,
            window: window,
            baseCurrency: baseCurrency,
            walletID: walletID
        )
        var sums: [UUID: Decimal] = [:]
        for row in rows {
            guard let id = row.walletID else { continue }
            if let walletID, id != walletID { continue }
            sums[id, default: .zero] += row.amount
        }
        let lookup = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        return sums.compactMap { id, amount in
            guard let wallet = lookup[id] else { return nil }
            return WalletTotal(
                id: id,
                name: wallet.name,
                amount: Money.rounded(amount, currencyCode: baseCurrency),
                colorHex: wallet.colorHex,
                iconName: wallet.iconName
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    static func cashFlow(
        _ transactions: [FinanceTransaction],
        window: ReportingWindow,
        baseCurrency: String,
        granularity: TrendGranularity,
        calendar: Calendar,
        walletID: UUID? = nil
    ) -> [CashFlowPoint] {
        let income = qualifying(transactions, type: .income, window: window, baseCurrency: baseCurrency, walletID: walletID)
        let expenses = qualifying(transactions, type: .expense, window: window, baseCurrency: baseCurrency, walletID: walletID)
        var incomeSums: [Date: Decimal] = [:]
        var expenseSums: [Date: Decimal] = [:]
        for row in income {
            let bucket = bucketStart(for: row.date, granularity: granularity, calendar: calendar)
            incomeSums[bucket, default: .zero] += row.amount
        }
        for row in expenses {
            let bucket = bucketStart(for: row.date, granularity: granularity, calendar: calendar)
            expenseSums[bucket, default: .zero] += row.amount
        }

        var starts = Set(incomeSums.keys).union(expenseSums.keys)
        if estimatedBucketCount(window: window, granularity: granularity, calendar: calendar) <= 366 {
            var cursor = bucketStart(for: window.start, granularity: granularity, calendar: calendar)
            var steps = 0
            while cursor < window.endExclusive && steps < 400 {
                starts.insert(cursor)
                guard let next = advanceBucket(cursor, granularity: granularity, calendar: calendar), next > cursor else { break }
                cursor = next
                steps += 1
            }
        }

        return starts.sorted().map { start in
            CashFlowPoint(
                start: start,
                label: bucketLabel(start, granularity: granularity, calendar: calendar),
                income: Money.rounded(incomeSums[start] ?? 0, currencyCode: baseCurrency),
                expense: Money.rounded(expenseSums[start] ?? 0, currencyCode: baseCurrency)
            )
        }
    }

    static func largestExpenses(
        _ transactions: [FinanceTransaction],
        window: ReportingWindow,
        baseCurrency: String,
        categories: [FinanceCategory],
        wallets: [FinanceWallet],
        walletID: UUID? = nil,
        limit: Int = 8
    ) -> [RankedTransaction] {
        let categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let walletLookup = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0) })
        return qualifying(transactions, type: .expense, window: window, baseCurrency: baseCurrency, walletID: walletID)
            .sorted { lhs, rhs in
                if lhs.amount == rhs.amount { return lhs.date > rhs.date }
                return lhs.amount > rhs.amount
            }
            .prefix(limit)
            .map { row in
                RankedTransaction(
                    id: row.id,
                    title: row.title,
                    date: row.date,
                    amount: row.amount,
                    categoryName: row.categoryID.flatMap { categoryLookup[$0]?.name } ?? "Uncategorized",
                    walletName: row.walletID.flatMap { walletLookup[$0]?.name } ?? "Wallet"
                )
            }
    }

    static func bucketStart(for date: Date, granularity: TrendGranularity, calendar: Calendar) -> Date {
        switch granularity {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        case .year:
            return calendar.dateInterval(of: .year, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    private static func apply(
        _ transaction: FinanceTransaction,
        wallets: [UUID: FinanceWallet],
        balances: inout [UUID: Decimal]
    ) {
        switch transaction.type {
        case .income:
            guard let walletID = transaction.walletID, let wallet = wallets[walletID] else { return }
            guard transaction.currencyCode == wallet.currencyCode else { return }
            balances[walletID, default: .zero] += signedInflow(wallet, amount: transaction.amount)
        case .expense:
            guard let walletID = transaction.walletID, let wallet = wallets[walletID] else { return }
            guard transaction.currencyCode == wallet.currencyCode else { return }
            balances[walletID, default: .zero] += signedOutflow(wallet, amount: transaction.amount)
        case .transfer:
            guard
                let sourceID = transaction.walletID,
                let destinationID = transaction.destinationWalletID,
                sourceID != destinationID,
                let source = wallets[sourceID],
                let destination = wallets[destinationID],
                source.currencyCode == destination.currencyCode,
                transaction.currencyCode == source.currencyCode
            else { return }
            balances[sourceID, default: .zero] += signedOutflow(source, amount: transaction.amount)
            balances[destinationID, default: .zero] += signedInflow(destination, amount: transaction.amount)
        }
    }

    /// Money arriving: increases an asset, and reduces a credit-card liability.
    private static func signedInflow(_ wallet: FinanceWallet, amount: Decimal) -> Decimal {
        wallet.isLiability ? -amount : amount
    }

    /// Money leaving: decreases an asset, and increases a credit-card liability.
    private static func signedOutflow(_ wallet: FinanceWallet, amount: Decimal) -> Decimal {
        wallet.isLiability ? amount : -amount
    }

    private static func advanceBucket(_ date: Date, granularity: TrendGranularity, calendar: Calendar) -> Date? {
        switch granularity {
        case .day: return calendar.date(byAdding: .day, value: 1, to: date)
        case .week: return calendar.date(byAdding: .day, value: 7, to: date)
        case .month: return calendar.date(byAdding: .month, value: 1, to: date)
        case .year: return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }

    private static func estimatedBucketCount(
        window: ReportingWindow,
        granularity: TrendGranularity,
        calendar: Calendar
    ) -> Int {
        let components: DateComponents
        switch granularity {
        case .day: components = calendar.dateComponents([.day], from: window.start, to: window.endExclusive)
        case .week: components = calendar.dateComponents([.weekOfYear], from: window.start, to: window.endExclusive)
        case .month: components = calendar.dateComponents([.month], from: window.start, to: window.endExclusive)
        case .year: components = calendar.dateComponents([.year], from: window.start, to: window.endExclusive)
        }
        let dayCount = components.day ?? components.weekOfYear ?? components.month ?? components.year ?? 0
        return max(dayCount, 0)
    }

    private static func bucketLabel(_ date: Date, granularity: TrendGranularity, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.timeZone = calendar.timeZone
        switch granularity {
        case .day: formatter.setLocalizedDateFormatFromTemplate("d MMM")
        case .week: formatter.setLocalizedDateFormatFromTemplate("d MMM yy")
        case .month: formatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
        case .year: formatter.setLocalizedDateFormatFromTemplate("yyyy")
        }
        return formatter.string(from: date)
    }
}
