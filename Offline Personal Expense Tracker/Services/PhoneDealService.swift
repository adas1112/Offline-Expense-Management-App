import Foundation
import SwiftData

enum PhoneDealService {
    static let purchaseCategoryName = "Phone purchase"
    static let resaleCategoryName = "Phone resale"

    @MainActor
    static func ensureCategories(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Category>())
        if !existing.contains(where: { $0.name == purchaseCategoryName && $0.kind == .expense }) {
            context.insert(
                Category(
                    name: purchaseCategoryName,
                    kind: .expense,
                    iconName: "iphone",
                    colorHex: "1D4E89",
                    sortOrder: existing.count
                )
            )
        }
        if !existing.contains(where: { $0.name == resaleCategoryName && $0.kind == .income }) {
            context.insert(
                Category(
                    name: resaleCategoryName,
                    kind: .income,
                    iconName: "iphone",
                    colorHex: "1A6B4A",
                    sortOrder: existing.count + 1
                )
            )
        }
    }

    @MainActor
    static func syncLedger(deal: PhoneDeal, in context: ModelContext) throws {
        try ensureCategories(in: context)
        try syncPurchase(deal: deal, in: context)
        for payment in deal.payments {
            try syncPayment(payment, deal: deal, in: context)
        }
        try context.save()
    }

    @MainActor
    static func delete(deal: PhoneDeal, in context: ModelContext) throws {
        if let transaction = try transaction(id: deal.purchaseTransactionID, in: context) {
            context.delete(transaction)
        }
        for payment in deal.payments {
            if let transaction = try transaction(id: payment.transactionID, in: context) {
                context.delete(transaction)
            }
            context.delete(payment)
        }
        context.delete(deal)
        try context.save()
    }

    @MainActor
    static func delete(payment: DealerPayment, in context: ModelContext) throws {
        if let transaction = try transaction(id: payment.transactionID, in: context) {
            context.delete(transaction)
        }
        context.delete(payment)
        try context.save()
    }

    @MainActor
    private static func syncPurchase(deal: PhoneDeal, in context: ModelContext) throws {
        guard let wallet = deal.purchaseWallet else { return }
        deal.currencyCode = wallet.currencyCode
        let category = try context.fetch(FetchDescriptor<Category>()).first {
            $0.name == purchaseCategoryName && $0.kind == .expense
        }
        let transaction: LedgerTransaction
        if let existing = try existingTransaction(id: deal.purchaseTransactionID, in: context) {
            transaction = existing
        } else {
            transaction = LedgerTransaction(
                type: .expense,
                amount: deal.purchaseAmount,
                currencyCode: wallet.currencyCode,
                title: purchaseTitle(deal),
                date: deal.purchaseDate
            )
            context.insert(transaction)
        }
        transaction.transactionType = .expense
        transaction.amount = deal.purchaseAmount
        transaction.currencyCode = wallet.currencyCode
        transaction.title = purchaseTitle(deal)
        transaction.notes = purchaseNotes(deal)
        transaction.date = deal.purchaseDate
        transaction.merchant = deal.platformTitle
        transaction.wallet = wallet
        transaction.category = category
        transaction.paymentMethod = wallet.walletType == .creditCard ? .creditCard : transaction.paymentMethod
        transaction.tags = ["phone"]
        transaction.updatedAt = Date()
        deal.purchaseTransactionID = transaction.id
    }

    @MainActor
    private static func syncPayment(_ payment: DealerPayment, deal: PhoneDeal, in context: ModelContext) throws {
        guard let wallet = deal.receiptWallet else { return }
        let category = try context.fetch(FetchDescriptor<Category>()).first {
            $0.name == resaleCategoryName && $0.kind == .income
        }
        let transaction: LedgerTransaction
        if let existing = try existingTransaction(id: payment.transactionID, in: context) {
            transaction = existing
        } else {
            transaction = LedgerTransaction(
                type: .income,
                amount: payment.amount,
                currencyCode: wallet.currencyCode,
                title: "Dealer payment · \(deal.phoneName)",
                date: payment.date
            )
            context.insert(transaction)
        }
        transaction.transactionType = .income
        transaction.amount = payment.amount
        transaction.currencyCode = wallet.currencyCode
        transaction.title = "Dealer payment · \(deal.phoneName)"
        transaction.notes = payment.note
        transaction.date = payment.date
        transaction.merchant = deal.dealerName
        transaction.wallet = wallet
        transaction.category = category
        transaction.paymentMethod = wallet.walletType == .cash ? .cash : (wallet.walletType == .digital ? .digitalWallet : transaction.paymentMethod)
        transaction.tags = ["phone"]
        transaction.updatedAt = Date()
        payment.transactionID = transaction.id
    }

    @MainActor
    private static func existingTransaction(id: UUID?, in context: ModelContext) throws -> LedgerTransaction? {
        guard let id else { return nil }
        return try context.fetch(FetchDescriptor<LedgerTransaction>()).first { $0.id == id }
    }

    @MainActor
    private static func transaction(id: UUID?, in context: ModelContext) throws -> LedgerTransaction? {
        try existingTransaction(id: id, in: context)
    }

    private static func purchaseTitle(_ deal: PhoneDeal) -> String {
        let count = deal.quantity == 1 ? "" : " ×\(deal.quantity)"
        return "Phone purchase · \(deal.phoneName)\(count)"
    }

    private static func purchaseNotes(_ deal: PhoneDeal) -> String {
        var lines: [String] = []
        if !deal.orderReference.isEmpty { lines.append("Order \(deal.orderReference)") }
        if deal.offerDiscount > 0 {
            lines.append("Card offer \(Money.exportString(deal.offerDiscount))")
        }
        if !deal.notes.isEmpty { lines.append(deal.notes) }
        return lines.joined(separator: "\n")
    }
}
