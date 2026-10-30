import Foundation
import SwiftData

@Model
final class RecurringRule {
    var id: UUID
    var frequencyRaw: String
    var startDate: Date
    var endDate: Date?
    var isPaused: Bool
    /// Set when the user pauses the rule. Occurrences in the paused gap are suppressed on resume.
    var pausedAt: Date?
    var templateTitle: String
    var templateAmount: Decimal
    var templateTypeRaw: String
    var templateNotes: String
    var templateTags: [String]
    var templateMerchant: String
    var templatePaymentMethodRaw: String?
    var currencyCode: String
    /// Occurrence keys that have already been created or intentionally skipped.
    var emittedOccurrenceKeys: [String]
    var isDemo: Bool
    var createdAt: Date

    var category: Category?
    var wallet: Wallet?
    var destinationWallet: Wallet?

    init(
        id: UUID = UUID(),
        frequency: RecurrenceFrequency,
        startDate: Date,
        endDate: Date? = nil,
        isPaused: Bool = false,
        pausedAt: Date? = nil,
        templateTitle: String,
        templateAmount: Decimal,
        templateType: TransactionType,
        templateNotes: String = "",
        templateTags: [String] = [],
        templateMerchant: String = "",
        templatePaymentMethod: PaymentMethod? = nil,
        currencyCode: String,
        emittedOccurrenceKeys: [String] = [],
        isDemo: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.frequencyRaw = frequency.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.isPaused = isPaused
        self.pausedAt = pausedAt
        self.templateTitle = templateTitle
        self.templateAmount = templateAmount
        self.templateTypeRaw = templateType.rawValue
        self.templateNotes = templateNotes
        self.templateTags = templateTags
        self.templateMerchant = templateMerchant
        self.templatePaymentMethodRaw = templatePaymentMethod?.rawValue
        self.currencyCode = currencyCode.uppercased()
        self.emittedOccurrenceKeys = emittedOccurrenceKeys
        self.isDemo = isDemo
        self.createdAt = createdAt
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var templateType: TransactionType {
        get { TransactionType(rawValue: templateTypeRaw) ?? .expense }
        set { templateTypeRaw = newValue.rawValue }
    }

    var templatePaymentMethod: PaymentMethod? {
        get {
            guard let templatePaymentMethodRaw else { return nil }
            return PaymentMethod(rawValue: templatePaymentMethodRaw)
        }
        set { templatePaymentMethodRaw = newValue?.rawValue }
    }
}
