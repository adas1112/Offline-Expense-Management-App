import Foundation
import SwiftData

@Model
final class Budget {
    var id: UUID
    var name: String
    var amount: Decimal
    var currencyCode: String
    var startDate: Date
    var endDate: Date
    /// Fraction of the budget, from 0.5 through 1, that triggers a warning.
    var warningThreshold: Double
    var isOverall: Bool
    var isPaused: Bool
    var isArchived: Bool
    var isDemo: Bool
    var notifyAtWarning: Bool
    var notifyAtExceeded: Bool
    var warningNotifiedKey: String?
    var exceededNotifiedKey: String?
    var createdAt: Date

    var category: Category?

    init(
        id: UUID = UUID(),
        name: String,
        amount: Decimal,
        currencyCode: String,
        startDate: Date,
        endDate: Date,
        warningThreshold: Double = 0.8,
        isOverall: Bool,
        isPaused: Bool = false,
        isArchived: Bool = false,
        isDemo: Bool = false,
        notifyAtWarning: Bool = false,
        notifyAtExceeded: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.startDate = startDate
        self.endDate = endDate
        self.warningThreshold = warningThreshold
        self.isOverall = isOverall
        self.isPaused = isPaused
        self.isArchived = isArchived
        self.isDemo = isDemo
        self.notifyAtWarning = notifyAtWarning
        self.notifyAtExceeded = notifyAtExceeded
        self.createdAt = createdAt
    }
}
