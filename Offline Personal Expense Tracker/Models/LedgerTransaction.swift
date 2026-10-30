import Foundation
import SwiftData

@Model
final class LedgerTransaction {
    var id: UUID
    var typeRaw: String
    var amount: Decimal
    var currencyCode: String
    var title: String
    var notes: String
    var date: Date
    var createdAt: Date
    var updatedAt: Date
    var tags: [String]
    var paymentMethodRaw: String?
    var merchant: String
    var attachmentFileName: String?
    var isDemo: Bool
    /// Stable id for one generated occurrence: `<ruleID>#<yyyy-MM-dd>`.
    var occurrenceKey: String?

    var category: Category?
    var wallet: Wallet?
    var destinationWallet: Wallet?
    var recurringRule: RecurringRule?

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Decimal,
        currencyCode: String,
        title: String,
        notes: String = "",
        date: Date,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        tags: [String] = [],
        paymentMethod: PaymentMethod? = nil,
        merchant: String = "",
        attachmentFileName: String? = nil,
        isDemo: Bool = false,
        occurrenceKey: String? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.title = title
        self.notes = notes
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.paymentMethodRaw = paymentMethod?.rawValue
        self.merchant = merchant
        self.attachmentFileName = attachmentFileName
        self.isDemo = isDemo
        self.occurrenceKey = occurrenceKey
    }

    var transactionType: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var paymentMethod: PaymentMethod? {
        get {
            guard let paymentMethodRaw else { return nil }
            return PaymentMethod(rawValue: paymentMethodRaw)
        }
        set { paymentMethodRaw = newValue?.rawValue }
    }
}
