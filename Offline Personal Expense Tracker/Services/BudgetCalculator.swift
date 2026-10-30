import Foundation

enum BudgetCalculator {
    static func spent(
        budget: FinanceBudget,
        transactions: [FinanceTransaction]
    ) -> Decimal {
        let window = ReportingWindow(start: budget.startDate, endExclusive: budget.endDate)
        return LedgerCalculator.total(
            transactions,
            type: .expense,
            window: window,
            baseCurrency: budget.currencyCode,
            categoryID: budget.isOverall ? nil : budget.categoryID
        )
    }

    static func utilization(spent: Decimal, limit: Decimal) -> Decimal {
        guard limit > 0 else { return spent > 0 ? 1 : 0 }
        return spent / limit
    }

    static func level(spent: Decimal, limit: Decimal, warningThreshold: Decimal) -> BudgetAlertLevel {
        if limit > 0, spent > limit { return .exceeded }
        if limit > 0, spent == limit { return .reached }
        if limit > 0, utilization(spent: spent, limit: limit) >= warningThreshold { return .warning }
        return .withinBudget
    }

    /// Paused and archived budgets do not produce alerts.
    static func alertLevel(for budget: FinanceBudget, transactions: [FinanceTransaction]) -> BudgetAlertLevel? {
        guard !budget.isPaused, !budget.isArchived else { return nil }
        let amount = spent(budget: budget, transactions: transactions)
        return level(spent: amount, limit: budget.amount, warningThreshold: budget.warningThreshold)
    }

    static func line(
        for budget: FinanceBudget,
        transactions: [FinanceTransaction],
        categoryName: String?
    ) -> BudgetLine {
        let amount = spent(budget: budget, transactions: transactions)
        let remaining = budget.amount - amount
        let activeLevel = alertLevel(for: budget, transactions: transactions)
        return BudgetLine(
            id: budget.id,
            name: budget.name,
            limit: budget.amount,
            spent: amount,
            remaining: remaining,
            utilization: utilization(spent: amount, limit: budget.amount),
            level: activeLevel,
            isOverall: budget.isOverall,
            categoryName: categoryName
        )
    }
}
