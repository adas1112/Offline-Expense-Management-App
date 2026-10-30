import Foundation

enum TransactionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case income
    case expense
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        case .transfer: "Transfer"
        }
    }

    var systemImage: String {
        switch self {
        case .income: "arrow.down.circle"
        case .expense: "arrow.up.circle"
        case .transfer: "arrow.left.arrow.right"
        }
    }
}

enum WalletType: String, Codable, CaseIterable, Identifiable, Sendable {
    case cash
    case bank
    case savings
    case creditCard
    case digital
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: "Cash"
        case .bank: "Bank account"
        case .savings: "Savings"
        case .creditCard: "Credit card"
        case .digital: "Digital wallet"
        case .custom: "Custom"
        }
    }

    var systemImage: String {
        switch self {
        case .cash: "banknote"
        case .bank: "building.columns"
        case .savings: "tray.full"
        case .creditCard: "creditcard"
        case .digital: "wallet.pass"
        case .custom: "square.stack.3d.up"
        }
    }

    /// Credit cards are liabilities. A positive balance means an amount owed.
    var isLiability: Bool { self == .creditCard }
}

enum CategoryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case income
    case expense

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        }
    }
}

enum PaymentMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case cash
    case debitCard
    case creditCard
    case bankTransfer
    case digitalWallet
    case check
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: "Cash"
        case .debitCard: "Debit card"
        case .creditCard: "Credit card"
        case .bankTransfer: "Bank transfer"
        case .digitalWallet: "Digital wallet"
        case .check: "Check"
        case .other: "Other"
        }
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly
    case biweekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }
}

enum AppearancePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum DateFormatPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case short
    case medium
    case long
    case iso

    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: "Short"
        case .medium: "Medium"
        case .long: "Long"
        case .iso: "ISO (yyyy-MM-dd)"
        }
    }
}

enum PeriodPreset: String, CaseIterable, Identifiable, Sendable {
    case thisMonth
    case lastMonth
    case last3Months
    case thisYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .last3Months: "Last 3 months"
        case .thisYear: "This year"
        case .custom: "Custom"
        }
    }
}

enum TrendGranularity: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }
}

enum TransactionSort: String, CaseIterable, Identifiable, Sendable {
    case dateNewest
    case dateOldest
    case amountHighest
    case amountLowest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateNewest: "Newest"
        case .dateOldest: "Oldest"
        case .amountHighest: "Highest amount"
        case .amountLowest: "Lowest amount"
        }
    }
}

enum BudgetAlertLevel: String, Sendable, Equatable {
    case withinBudget
    case warning
    case reached
    case exceeded

    var title: String {
        switch self {
        case .withinBudget: "On track"
        case .warning: "Nearing limit"
        case .reached: "Limit reached"
        case .exceeded: "Over budget"
        }
    }
}
