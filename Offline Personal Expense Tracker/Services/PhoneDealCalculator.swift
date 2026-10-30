import Foundation

struct PhoneLot: Equatable, Sendable, Identifiable {
    var id: UUID
    var quantity: Int
    var purchaseAmount: Decimal
    var currencyCode: String
    var isSold: Bool
    var quantitySold: Int
    var saleAmount: Decimal
    var amountReceived: Decimal
}

struct PhoneLotPosition: Equatable, Sendable {
    var stage: PhoneDealStage
    /// Cost of phones not yet sold.
    var stockCost: Decimal
    /// Cost of the phones that were sold, taken as a share of the purchase amount.
    var soldCost: Decimal
    /// Money the dealer still owes.
    var pendingPayment: Decimal
    /// Money the dealer has paid.
    var successfulPayment: Decimal
    /// Agreed sale minus the cost of the phones that were sold. Zero while the phones are still in stock.
    var profit: Decimal
}

struct PhoneBookSummary: Equatable, Sendable {
    var currencyCode: String
    var purchaseCost: Decimal
    var stockCost: Decimal
    var pendingPayment: Decimal
    var successfulPayment: Decimal
    var profit: Decimal
    var inStockCount: Int
    var pendingCount: Int
    var settledCount: Int
    var phoneCount: Int
}

enum PhoneDealCalculator {
    static func position(for lot: PhoneLot) -> PhoneLotPosition {
        let currency = lot.currencyCode
        let quantity = max(lot.quantity, 1)
        let soldUnits = lot.isSold ? min(max(lot.quantitySold, 0), quantity) : 0
        let purchase = Money.rounded(max(lot.purchaseAmount, 0), currencyCode: currency)
        let soldCost: Decimal
        if soldUnits <= 0 {
            soldCost = 0
        } else if soldUnits >= quantity {
            soldCost = purchase
        } else {
            soldCost = Money.rounded(purchase * Decimal(soldUnits) / Decimal(quantity), currencyCode: currency)
        }
        let stockCost = purchase - soldCost
        let sale = lot.isSold ? Money.rounded(max(lot.saleAmount, 0), currencyCode: currency) : 0
        let received = Money.rounded(max(lot.amountReceived, 0), currencyCode: currency)
        let pending = max(sale - received, 0)
        let stage: PhoneDealStage
        if !lot.isSold || soldUnits == 0 {
            stage = .inStock
        } else if pending > 0 {
            stage = .paymentPending
        } else {
            stage = .settled
        }
        return PhoneLotPosition(
            stage: stage,
            stockCost: stockCost,
            soldCost: soldCost,
            pendingPayment: pending,
            successfulPayment: received,
            profit: sale - soldCost
        )
    }

    static func summary(lots: [PhoneLot], currencyCode: String) -> PhoneBookSummary {
        let currency = currencyCode.uppercased()
        var purchase = Decimal.zero
        var stock = Decimal.zero
        var pending = Decimal.zero
        var successful = Decimal.zero
        var profit = Decimal.zero
        var inStock = 0
        var pendingCount = 0
        var settled = 0
        var phones = 0
        for lot in lots where lot.currencyCode.uppercased() == currency {
            let position = position(for: lot)
            purchase += Money.rounded(lot.purchaseAmount, currencyCode: currency)
            stock += position.stockCost
            pending += position.pendingPayment
            successful += position.successfulPayment
            profit += position.profit
            phones += max(lot.quantity, 0)
            switch position.stage {
            case .inStock: inStock += 1
            case .paymentPending: pendingCount += 1
            case .settled: settled += 1
            }
        }
        return PhoneBookSummary(
            currencyCode: currency,
            purchaseCost: Money.rounded(purchase, currencyCode: currency),
            stockCost: Money.rounded(stock, currencyCode: currency),
            pendingPayment: Money.rounded(pending, currencyCode: currency),
            successfulPayment: Money.rounded(successful, currencyCode: currency),
            profit: Money.rounded(profit, currencyCode: currency),
            inStockCount: inStock,
            pendingCount: pendingCount,
            settledCount: settled,
            phoneCount: phones
        )
    }
}

extension PhoneDeal {
    func lot() -> PhoneLot {
        let received = payments.reduce(Decimal.zero) { $0 + $1.amount }
        return PhoneLot(
            id: id,
            quantity: quantity,
            purchaseAmount: purchaseAmount,
            currencyCode: currencyCode,
            isSold: isSold,
            quantitySold: quantitySold,
            saleAmount: saleAmount,
            amountReceived: received
        )
    }
}
