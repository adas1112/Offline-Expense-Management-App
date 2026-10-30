import Foundation
import SwiftData

@Model
final class Wallet {
    var id: UUID
    var name: String
    var typeRaw: String
    var currencyCode: String
    var openingBalance: Decimal
    var iconName: String
    var colorHex: String
    var createdAt: Date
    var isArchived: Bool
    var isDemo: Bool

    @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.wallet)
    var transactions: [LedgerTransaction] = []

    @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.destinationWallet)
    var incomingTransfers: [LedgerTransaction] = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.wallet)
    var recurringSources: [RecurringRule] = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.destinationWallet)
    var recurringDestinations: [RecurringRule] = []

    @Relationship(deleteRule: .nullify, inverse: \PhoneDeal.purchaseWallet)
    var purchaseDeals: [PhoneDeal] = []

    @Relationship(deleteRule: .nullify, inverse: \PhoneDeal.receiptWallet)
    var receiptDeals: [PhoneDeal] = []

    init(
        id: UUID = UUID(),
        name: String,
        type: WalletType,
        currencyCode: String,
        openingBalance: Decimal,
        iconName: String,
        colorHex: String,
        createdAt: Date = Date(),
        isArchived: Bool = false,
        isDemo: Bool = false
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.currencyCode = currencyCode.uppercased()
        self.openingBalance = openingBalance
        self.iconName = iconName
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.isDemo = isDemo
    }

    var walletType: WalletType {
        get { WalletType(rawValue: typeRaw) ?? .custom }
        set { typeRaw = newValue.rawValue }
    }
}
