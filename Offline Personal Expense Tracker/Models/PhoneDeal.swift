import Foundation
import SwiftData

enum ShopPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case amazon
    case flipkart
    case jioMart
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amazon: "Amazon"
        case .flipkart: "Flipkart"
        case .jioMart: "JioMart"
        case .other: "Other"
        }
    }
}

enum PhoneDealStage: String, Sendable, Equatable {
    case inStock
    case paymentPending
    case settled

    var title: String {
        switch self {
        case .inStock: "In stock"
        case .paymentPending: "Payment pending"
        case .settled: "Payment received"
        }
    }
}

/// One purchase of phones bought for a card offer and, once sold, the dealer settlement.
@Model
final class PhoneDeal {
    var id: UUID
    var phoneName: String
    var platformRaw: String
    var platformDetail: String
    var quantity: Int
    var orderReference: String
    var purchaseAmount: Decimal
    /// Discount from the card or site offer. Profit uses the amount you actually paid, not this figure.
    var offerDiscount: Decimal
    var purchaseDate: Date
    var currencyCode: String
    var notes: String
    var purchaseTransactionID: UUID?
    var isSold: Bool
    var dealerName: String
    var quantitySold: Int
    var saleAmount: Decimal
    var saleDate: Date?
    var createdAt: Date

    var purchaseWallet: Wallet?
    var receiptWallet: Wallet?

    @Relationship(deleteRule: .cascade, inverse: \DealerPayment.deal)
    var payments: [DealerPayment] = []

    init(
        id: UUID = UUID(),
        phoneName: String,
        platform: ShopPlatform,
        platformDetail: String = "",
        quantity: Int,
        orderReference: String = "",
        purchaseAmount: Decimal,
        offerDiscount: Decimal = 0,
        purchaseDate: Date = Date(),
        currencyCode: String,
        notes: String = "",
        purchaseTransactionID: UUID? = nil,
        isSold: Bool = false,
        dealerName: String = "",
        quantitySold: Int = 0,
        saleAmount: Decimal = 0,
        saleDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.phoneName = phoneName
        self.platformRaw = platform.rawValue
        self.platformDetail = platformDetail
        self.quantity = quantity
        self.orderReference = orderReference
        self.purchaseAmount = purchaseAmount
        self.offerDiscount = offerDiscount
        self.purchaseDate = purchaseDate
        self.currencyCode = currencyCode.uppercased()
        self.notes = notes
        self.purchaseTransactionID = purchaseTransactionID
        self.isSold = isSold
        self.dealerName = dealerName
        self.quantitySold = quantitySold
        self.saleAmount = saleAmount
        self.saleDate = saleDate
        self.createdAt = createdAt
    }

    var platform: ShopPlatform {
        get { ShopPlatform(rawValue: platformRaw) ?? .other }
        set { platformRaw = newValue.rawValue }
    }

    var platformTitle: String {
        if platform == .other {
            let detail = platformDetail.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Other" : detail
        }
        return platform.title
    }
}

@Model
final class DealerPayment {
    var id: UUID
    var amount: Decimal
    var date: Date
    var note: String
    var transactionID: UUID?
    var deal: PhoneDeal?

    init(
        id: UUID = UUID(),
        amount: Decimal,
        date: Date = Date(),
        note: String = "",
        transactionID: UUID? = nil
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.transactionID = transactionID
    }
}
