import Foundation

enum ReportBuilder {
    static func make(
        transactions: [FinanceTransaction],
        wallets: [FinanceWallet],
        categories: [FinanceCategory],
        budgets: [FinanceBudget],
        window: ReportingWindow,
        calendar: Calendar,
        baseCurrency: String,
        granularity: TrendGranularity,
        walletID: UUID? = nil
    ) -> FinanceReport {
        let currency = baseCurrency.uppercased()
        let income = LedgerCalculator.total(transactions, type: .income, window: window, baseCurrency: currency, walletID: walletID)
        let expense = LedgerCalculator.total(transactions, type: .expense, window: window, baseCurrency: currency, walletID: walletID)
        let opening = LedgerCalculator.netWorth(wallets: wallets, transactions: transactions, baseCurrency: currency, before: window.start)
        let closing = LedgerCalculator.netWorth(wallets: wallets, transactions: transactions, baseCurrency: currency, before: window.endExclusive)
        let current = LedgerCalculator.netWorth(wallets: wallets, transactions: transactions, baseCurrency: currency)
        let balances = LedgerCalculator.walletBalances(wallets: wallets, transactions: transactions)
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })

        let budgetLines = budgets
            .filter { !$0.isArchived && walletID == nil }
            .map { budget in
                BudgetCalculator.line(
                    for: budget,
                    transactions: transactions,
                    categoryName: budget.categoryID.flatMap { categoryNames[$0] }
                )
            }
            .sorted { lhs, rhs in
                let left = lhs.level == .exceeded || lhs.level == .reached
                let right = rhs.level == .exceeded || rhs.level == .reached
                if left != right { return left && !right }
                return lhs.name < rhs.name
            }

        let walletLines = wallets
            .sorted { lhs, rhs in
                if lhs.isArchived != rhs.isArchived { return !lhs.isArchived && rhs.isArchived }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { wallet in
                WalletBalanceLine(
                    id: wallet.id,
                    name: wallet.name,
                    type: wallet.type,
                    currencyCode: wallet.currencyCode,
                    balance: balances[wallet.id] ?? wallet.openingBalance,
                    isArchived: wallet.isArchived,
                    includedInNetWorth: wallet.currencyCode == currency,
                    iconName: wallet.iconName,
                    colorHex: wallet.colorHex
                )
            }

        return FinanceReport(
            currencyCode: currency,
            income: income,
            expense: expense,
            net: Money.rounded(income - expense, currencyCode: currency),
            openingNetWorth: opening,
            closingNetWorth: closing,
            currentNetWorth: current,
            excludedForeignWalletCount: wallets.filter { $0.currencyCode != currency }.count,
            cashFlow: LedgerCalculator.cashFlow(
                transactions,
                window: window,
                baseCurrency: currency,
                granularity: granularity,
                calendar: calendar,
                walletID: walletID
            ),
            expenseByCategory: LedgerCalculator.categoryTotals(
                transactions,
                type: .expense,
                window: window,
                baseCurrency: currency,
                categories: categories,
                walletID: walletID
            ),
            incomeByCategory: LedgerCalculator.categoryTotals(
                transactions,
                type: .income,
                window: window,
                baseCurrency: currency,
                categories: categories,
                walletID: walletID
            ),
            expenseByWallet: LedgerCalculator.walletExpenseTotals(
                transactions,
                window: window,
                baseCurrency: currency,
                wallets: wallets,
                walletID: walletID
            ),
            largestExpenses: LedgerCalculator.largestExpenses(
                transactions,
                window: window,
                baseCurrency: currency,
                categories: categories,
                wallets: wallets,
                walletID: walletID
            ),
            budgetLines: budgetLines,
            walletBalances: walletLines
        )
    }

    static func automaticGranularity(for window: ReportingWindow, calendar: Calendar) -> TrendGranularity {
        let days = calendar.dateComponents([.day], from: window.start, to: window.endExclusive).day ?? 0
        if days <= 45 { return .day }
        if days <= 200 { return .week }
        if days <= 800 { return .month }
        return .year
    }
}
