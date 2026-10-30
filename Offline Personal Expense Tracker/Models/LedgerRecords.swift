import Foundation

/// Value types used by every financial calculation. Views map SwiftData models into these records
/// so totals, charts, exports, and tests share one accounting implementation.
struct FinanceWallet: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var type: WalletType
    var currencyCode: String
    var openingBalance: Decimal
    var isArchived: Bool
    var iconName: String
    var colorHex: String

    var isLiability: Bool { type.isLiability }
}

struct FinanceCategory: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var kind: CategoryKind
    var iconName: String
    var colorHex: String
    var isArchived: Bool
}

struct FinanceTransaction: Equatable, Sendable, Identifiable {
    var id: UUID
    var type: TransactionType
    var amount: Decimal
    var currencyCode: String
    var date: Date
    var title: String
    var notes: String
    var merchant: String
    var tags: [String]
    var categoryID: UUID?
    var walletID: UUID?
    var destinationWalletID: UUID?
    var paymentMethod: PaymentMethod?
}

struct FinanceBudget: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var amount: Decimal
    var currencyCode: String
    var startDate: Date
    var endDate: Date
    var warningThreshold: Decimal
    var isOverall: Bool
    var categoryID: UUID?
    var isPaused: Bool
    var isArchived: Bool
}

struct ReportingWindow: Equatable, Sendable {
    var start: Date
    /// First instant that is no longer included. A calendar day is included through its end.
    var endExclusive: Date

    func contains(_ date: Date) -> Bool {
        date >= start && date < endExclusive
    }
}

struct CategoryTotal: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var amount: Decimal
    var colorHex: String
    var iconName: String
    var fraction: Decimal
}

struct WalletTotal: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var amount: Decimal
    var colorHex: String
    var iconName: String
}

struct CashFlowPoint: Equatable, Sendable, Identifiable {
    var id: Date { start }
    var start: Date
    var label: String
    var income: Decimal
    var expense: Decimal

    var net: Decimal { income - expense }
}

struct RankedTransaction: Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var date: Date
    var amount: Decimal
    var categoryName: String
    var walletName: String
}

struct WalletBalanceLine: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var type: WalletType
    var currencyCode: String
    var balance: Decimal
    var isArchived: Bool
    var includedInNetWorth: Bool
    var iconName: String
    var colorHex: String
}

struct BudgetLine: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var limit: Decimal
    var spent: Decimal
    var remaining: Decimal
    var utilization: Decimal
    var level: BudgetAlertLevel?
    var isOverall: Bool
    var categoryName: String?
}

struct FinanceReport: Equatable, Sendable {
    var currencyCode: String
    var income: Decimal
    var expense: Decimal
    var net: Decimal
    var openingNetWorth: Decimal
    var closingNetWorth: Decimal
    var currentNetWorth: Decimal
    var excludedForeignWalletCount: Int
    var cashFlow: [CashFlowPoint]
    var expenseByCategory: [CategoryTotal]
    var incomeByCategory: [CategoryTotal]
    var expenseByWallet: [WalletTotal]
    var largestExpenses: [RankedTransaction]
    var budgetLines: [BudgetLine]
    var walletBalances: [WalletBalanceLine]
}

struct TransactionFilter: Equatable, Sendable {
    var query: String = ""
    var type: TransactionType?
    var categoryID: UUID?
    var walletID: UUID?
    var start: Date?
    var end: Date?
    var sort: TransactionSort = .dateNewest

    static let empty = TransactionFilter()
}
