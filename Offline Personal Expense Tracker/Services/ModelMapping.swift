import Foundation

extension Wallet {
    func financeValue() -> FinanceWallet {
        FinanceWallet(
            id: id,
            name: name,
            type: walletType,
            currencyCode: currencyCode,
            openingBalance: openingBalance,
            isArchived: isArchived,
            iconName: iconName,
            colorHex: colorHex
        )
    }
}

extension Category {
    func financeValue() -> FinanceCategory {
        FinanceCategory(
            id: id,
            name: name,
            kind: kind,
            iconName: iconName,
            colorHex: colorHex,
            isArchived: isArchived
        )
    }
}

extension LedgerTransaction {
    func financeValue() -> FinanceTransaction {
        FinanceTransaction(
            id: id,
            type: transactionType,
            amount: amount,
            currencyCode: currencyCode,
            date: date,
            title: title,
            notes: notes,
            merchant: merchant,
            tags: tags,
            categoryID: category?.id,
            walletID: wallet?.id,
            destinationWalletID: destinationWallet?.id,
            paymentMethod: paymentMethod
        )
    }
}

extension Budget {
    func financeValue() -> FinanceBudget {
        FinanceBudget(
            id: id,
            name: name,
            amount: amount,
            currencyCode: currencyCode,
            startDate: Calendar.current.startOfDay(for: startDate),
            endDate: endExclusive,
            warningThreshold: Decimal(warningThreshold),
            isOverall: isOverall,
            categoryID: category?.id,
            isPaused: isPaused,
            isArchived: isArchived
        )
    }

    /// Budgets store an inclusive end date. Calculations use the start of the following day.
    var endExclusive: Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: endDate)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? endDate.addingTimeInterval(1)
    }
}

enum LedgerSnapshot {
    static func transactions(from rows: [LedgerTransaction]) -> [FinanceTransaction] {
        rows.map { $0.financeValue() }
    }

    static func wallets(from rows: [Wallet]) -> [FinanceWallet] {
        rows.map { $0.financeValue() }
    }

    static func categories(from rows: [Category]) -> [FinanceCategory] {
        rows.map { $0.financeValue() }
    }

    static func budgets(from rows: [Budget]) -> [FinanceBudget] {
        rows.map { $0.financeValue() }
    }
}
