import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var kindRaw: String
    var iconName: String
    var colorHex: String
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \LedgerTransaction.category)
    var transactions: [LedgerTransaction] = []

    @Relationship(deleteRule: .nullify, inverse: \Budget.category)
    var budgets: [Budget] = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.category)
    var recurringRules: [RecurringRule] = []

    init(
        id: UUID = UUID(),
        name: String,
        kind: CategoryKind,
        iconName: String,
        colorHex: String,
        sortOrder: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.iconName = iconName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }
}
