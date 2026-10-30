import Foundation

/// Version 1 backup document.
///
/// File format: UTF-8 JSON.
/// `format` must be `offline-finance-backup` and `version` must be `1`.
/// Decimal amounts are strings, so values such as `0.10` are not stored as binary floating point.
/// Dates are ISO-8601 with fractional seconds.
/// Restoring a backup replaces the on-device database; it does not merge, so records are not duplicated.
struct BackupDocument: Codable, Equatable {
    var format: String
    var version: Int
    var exportedAt: Date
    var appVersion: String
    var settings: SettingsRecord
    var categories: [CategoryRecord]
    var wallets: [WalletRecord]
    var budgets: [BudgetRecord]
    var recurringRules: [RecurringRuleRecord]
    var transactions: [TransactionRecord]
    /// Phone purchases and dealer payments. Missing in backups made before this field existed.
    var phoneDeals: [PhoneDealRecord] = []
}

struct PhoneDealRecord: Codable, Equatable {
    var id: UUID
    var phoneName: String
    var platform: String
    var platformDetail: String
    var quantity: Int
    var orderReference: String
    var purchaseAmount: String
    var offerDiscount: String
    var purchaseDate: Date
    var currencyCode: String
    var notes: String
    var purchaseWalletID: UUID?
    var purchaseTransactionID: UUID?
    var isSold: Bool
    var dealerName: String
    var quantitySold: Int
    var saleAmount: String
    var saleDate: Date?
    var receiptWalletID: UUID?
    var payments: [DealerPaymentRecord]
    var createdAt: Date
}

struct DealerPaymentRecord: Codable, Equatable {
    var id: UUID
    var amount: String
    var date: Date
    var note: String
    var transactionID: UUID?
}

struct SettingsRecord: Codable, Equatable {
    var id: UUID
    var baseCurrencyCode: String
    var dateFormat: String
    var firstWeekday: Int
    var appearance: String
    var biometricLockEnabled: Bool
    var budgetNotificationsEnabled: Bool
    var warningThreshold: String
    var didSeedCategories: Bool
    var demoDataInstalled: Bool
}

struct CategoryRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var kind: String
    var iconName: String
    var colorHex: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date
}

struct WalletRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var type: String
    var currencyCode: String
    var openingBalance: String
    var iconName: String
    var colorHex: String
    var createdAt: Date
    var isArchived: Bool
    var isDemo: Bool
}

struct BudgetRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var amount: String
    var currencyCode: String
    var startDate: Date
    var endDate: Date
    var warningThreshold: String
    var isOverall: Bool
    var categoryID: UUID?
    var isPaused: Bool
    var isArchived: Bool
    var isDemo: Bool
    var notifyAtWarning: Bool
    var notifyAtExceeded: Bool
    var createdAt: Date
}

struct RecurringRuleRecord: Codable, Equatable {
    var id: UUID
    var frequency: String
    var startDate: Date
    var endDate: Date?
    var isPaused: Bool
    var pausedAt: Date?
    var templateTitle: String
    var templateAmount: String
    var templateType: String
    var templateNotes: String
    var templateTags: [String]
    var templateMerchant: String
    var templatePaymentMethod: String?
    var currencyCode: String
    var emittedOccurrenceKeys: [String]
    var isDemo: Bool
    var createdAt: Date
    var categoryID: UUID?
    var walletID: UUID?
    var destinationWalletID: UUID?
}

struct TransactionRecord: Codable, Equatable {
    var id: UUID
    var type: String
    var amount: String
    var currencyCode: String
    var title: String
    var notes: String
    var date: Date
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]
    var paymentMethod: String?
    var merchant: String
    var attachmentFileName: String?
    var attachmentBase64: String?
    var isDemo: Bool
    var occurrenceKey: String?
    var categoryID: UUID?
    var walletID: UUID?
    var destinationWalletID: UUID?
    var recurringRuleID: UUID?
}

enum BackupError: Error, Equatable, CustomStringConvertible {
    case unreadable
    case unsupportedFormat
    case unsupportedVersion(Int)
    case invalid(String)

    var description: String {
        switch self {
        case .unreadable:
            "This file could not be read as a finance backup."
        case .unsupportedFormat:
            "This file is not an Offline Personal Expense Tracker backup."
        case .unsupportedVersion(let version):
            "Backup version \(version) is not supported. This app restores version 1."
        case .invalid(let message):
            message
        }
    }
}

enum BackupCodec {
    static let formatIdentifier = "offline-finance-backup"
    static let version = 1

    static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.formatter.string(from: date))
        }
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = formatter.date(from: value) ?? fallbackFormatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            return date
        }
        let document: BackupDocument
        do {
            document = try decoder.decode(BackupDocument.self, from: try withPhoneDealsKey(data))
        } catch {
            throw BackupError.unreadable
        }
        try validate(document)
        return document
    }

    static func validate(_ document: BackupDocument) throws {
        guard document.format == formatIdentifier else { throw BackupError.unsupportedFormat }
        guard document.version == version else { throw BackupError.unsupportedVersion(document.version) }
        try uniqueIDs(document.categories.map(\.id), label: "categories")
        try uniqueIDs(document.wallets.map(\.id), label: "wallets")
        try uniqueIDs(document.budgets.map(\.id), label: "budgets")
        try uniqueIDs(document.recurringRules.map(\.id), label: "recurring rules")
        try uniqueIDs(document.transactions.map(\.id), label: "transactions")
        try uniqueIDs(document.phoneDeals.map(\.id), label: "phone purchases")
        try uniqueIDs(document.phoneDeals.flatMap { $0.payments.map(\.id) }, label: "dealer payments")

        let categoryIDs = Set(document.categories.map(\.id))
        let walletIDs = Set(document.wallets.map(\.id))
        let ruleIDs = Set(document.recurringRules.map(\.id))

        guard DateFormatPreference(rawValue: document.settings.dateFormat) != nil else {
            throw BackupError.invalid("The backup settings use an unknown date format.")
        }
        guard AppearancePreference(rawValue: document.settings.appearance) != nil else {
            throw BackupError.invalid("The backup settings use an unknown appearance.")
        }
        guard (1...7).contains(document.settings.firstWeekday) else {
            throw BackupError.invalid("The first day of the week is invalid.")
        }
        guard decimal(document.settings.warningThreshold) != nil else {
            throw BackupError.invalid("The warning threshold is invalid.")
        }

        for category in document.categories {
            guard CategoryKind(rawValue: category.kind) != nil else {
                throw BackupError.invalid("A category has an unknown type.")
            }
            if category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BackupError.invalid("A category is missing a name.")
            }
        }
        for wallet in document.wallets {
            guard WalletType(rawValue: wallet.type) != nil else {
                throw BackupError.invalid("A wallet has an unknown type.")
            }
            guard let opening = decimal(wallet.openingBalance), opening >= 0 else {
                throw BackupError.invalid("A wallet opening balance is invalid.")
            }
            if wallet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BackupError.invalid("A wallet is missing a name.")
            }
        }
        for budget in document.budgets {
            guard let amount = decimal(budget.amount), amount > 0 else {
                throw BackupError.invalid("A budget amount is invalid.")
            }
            if let categoryID = budget.categoryID, !categoryIDs.contains(categoryID) {
                throw BackupError.invalid("A budget refers to a missing category.")
            }
            if !budget.isOverall && budget.categoryID == nil {
                throw BackupError.invalid("A category budget is missing its category.")
            }
        }
        for rule in document.recurringRules {
            guard RecurrenceFrequency(rawValue: rule.frequency) != nil,
                  TransactionType(rawValue: rule.templateType) != nil else {
                throw BackupError.invalid("A repeating rule is invalid.")
            }
            guard let amount = decimal(rule.templateAmount), amount > 0 else {
                throw BackupError.invalid("A repeating rule has an invalid amount.")
            }
            if let walletID = rule.walletID, !walletIDs.contains(walletID) {
                throw BackupError.invalid("A repeating rule refers to a missing wallet.")
            }
            if let destination = rule.destinationWalletID, !walletIDs.contains(destination) {
                throw BackupError.invalid("A repeating rule refers to a missing wallet.")
            }
            if let categoryID = rule.categoryID, !categoryIDs.contains(categoryID) {
                throw BackupError.invalid("A repeating rule refers to a missing category.")
            }
        }
        var occurrenceKeys = Set<String>()
        for transaction in document.transactions {
            guard let type = TransactionType(rawValue: transaction.type) else {
                throw BackupError.invalid("A transaction has an unknown type.")
            }
            guard let amount = decimal(transaction.amount), amount > 0 else {
                throw BackupError.invalid("A transaction amount is invalid.")
            }
            guard let walletID = transaction.walletID, walletIDs.contains(walletID) else {
                throw BackupError.invalid("A transaction refers to a missing wallet.")
            }
            if let categoryID = transaction.categoryID, !categoryIDs.contains(categoryID) {
                throw BackupError.invalid("A transaction refers to a missing category.")
            }
            if let ruleID = transaction.recurringRuleID, !ruleIDs.contains(ruleID) {
                throw BackupError.invalid("A transaction refers to a missing repeating rule.")
            }
            if type == .transfer {
                guard let destination = transaction.destinationWalletID, walletIDs.contains(destination), destination != walletID else {
                    throw BackupError.invalid("A transfer is missing a valid destination wallet.")
                }
            }
            if transaction.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BackupError.invalid("A transaction is missing a title.")
            }
            if let key = transaction.occurrenceKey {
                guard occurrenceKeys.insert(key).inserted else {
                    throw BackupError.invalid("The backup contains duplicate repeating transactions.")
                }
            }
            if let encoded = transaction.attachmentBase64, Data(base64Encoded: encoded) == nil {
                throw BackupError.invalid("A transaction attachment is damaged.")
            }
        }
        let transactionIDs = Set(document.transactions.map(\.id))
        for deal in document.phoneDeals {
            guard ShopPlatform(rawValue: deal.platform) != nil else {
                throw BackupError.invalid("A phone purchase has an unknown store.")
            }
            if deal.phoneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw BackupError.invalid("A phone purchase is missing a name.")
            }
            guard deal.quantity >= 1 else {
                throw BackupError.invalid("A phone purchase has an invalid quantity.")
            }
            guard let purchase = decimal(deal.purchaseAmount), purchase > 0 else {
                throw BackupError.invalid("A phone purchase amount is invalid.")
            }
            guard let offer = decimal(deal.offerDiscount), offer >= 0 else {
                throw BackupError.invalid("A card offer amount is invalid.")
            }
            if let walletID = deal.purchaseWalletID, !walletIDs.contains(walletID) {
                throw BackupError.invalid("A phone purchase refers to a missing wallet.")
            }
            if let walletID = deal.receiptWalletID, !walletIDs.contains(walletID) {
                throw BackupError.invalid("A dealer payment refers to a missing wallet.")
            }
            if let transactionID = deal.purchaseTransactionID, !transactionIDs.contains(transactionID) {
                throw BackupError.invalid("A phone purchase refers to a missing transaction.")
            }
            if deal.isSold {
                guard deal.quantitySold >= 1, deal.quantitySold <= deal.quantity else {
                    throw BackupError.invalid("A phone sale quantity is invalid.")
                }
                guard let sale = decimal(deal.saleAmount), sale > 0 else {
                    throw BackupError.invalid("A phone sale price is invalid.")
                }
                if deal.dealerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw BackupError.invalid("A phone sale is missing the dealer name.")
                }
            }
            for payment in deal.payments {
                guard let amount = decimal(payment.amount), amount > 0 else {
                    throw BackupError.invalid("A dealer payment amount is invalid.")
                }
                if let transactionID = payment.transactionID, !transactionIDs.contains(transactionID) {
                    throw BackupError.invalid("A dealer payment refers to a missing transaction.")
                }
            }
        }
    }

    /// Older backups have no phone-deal list. Treat that as an empty list.
    private static func withPhoneDealsKey(_ data: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.unreadable
        }
        if root["phoneDeals"] == nil {
            root["phoneDeals"] = [Any]()
        }
        return try JSONSerialization.data(withJSONObject: root)
    }

    private static func uniqueIDs(_ ids: [UUID], label: String) throws {
        if Set(ids).count != ids.count {
            throw BackupError.invalid("The backup contains duplicate \(label).")
        }
    }

    static func decimal(_ string: String) -> Decimal? {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
