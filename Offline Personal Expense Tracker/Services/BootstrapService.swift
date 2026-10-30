import Foundation
import SwiftData

enum BootstrapService {
    struct SeedCategory {
        var name: String
        var kind: CategoryKind
        var icon: String
        var color: String
    }

    static let defaultCategories: [SeedCategory] = [
        SeedCategory(name: "Salary", kind: .income, icon: "briefcase", color: "1A6B4A"),
        SeedCategory(name: "Freelance", kind: .income, icon: "laptopcomputer", color: "1D4E89"),
        SeedCategory(name: "Investments", kind: .income, icon: "chart.line.uptrend.xyaxis", color: "2F6F73"),
        SeedCategory(name: "Gifts", kind: .income, icon: "gift", color: "6B4C9A"),
        SeedCategory(name: "Refunds", kind: .income, icon: "arrow.uturn.backward", color: "3E5C4A"),
        SeedCategory(name: "Other income", kind: .income, icon: "plus.circle", color: "8C4A32"),
        SeedCategory(name: "Groceries", kind: .expense, icon: "cart", color: "1A6B4A"),
        SeedCategory(name: "Food", kind: .expense, icon: "fork.knife", color: "8C4A32"),
        SeedCategory(name: "Transport", kind: .expense, icon: "car", color: "1D4E89"),
        SeedCategory(name: "Housing", kind: .expense, icon: "house", color: "6B4C9A"),
        SeedCategory(name: "Utilities", kind: .expense, icon: "bolt", color: "9A6B2F"),
        SeedCategory(name: "Healthcare", kind: .expense, icon: "cross.case", color: "8E3140"),
        SeedCategory(name: "Entertainment", kind: .expense, icon: "film", color: "6B4C9A"),
        SeedCategory(name: "Shopping", kind: .expense, icon: "bag", color: "8E3140"),
        SeedCategory(name: "Education", kind: .expense, icon: "book", color: "1D4E89"),
        SeedCategory(name: "Travel", kind: .expense, icon: "airplane", color: "2F6F73"),
        SeedCategory(name: "Personal", kind: .expense, icon: "person", color: "3E5C4A"),
        SeedCategory(name: "Subscriptions", kind: .expense, icon: "repeat", color: "8C4A32"),
        SeedCategory(name: "Other", kind: .expense, icon: "ellipsis.circle", color: "8E8E93")
    ]

    @MainActor
    static func bootstrap(context: ModelContext) throws {
        let settings = try ensureSettings(context: context)
        if !settings.didSeedCategories {
            let existing = try context.fetch(FetchDescriptor<Category>())
            if existing.isEmpty {
                for (index, seed) in defaultCategories.enumerated() {
                    context.insert(
                        Category(
                            name: seed.name,
                            kind: seed.kind,
                            iconName: seed.icon,
                            colorHex: seed.color,
                            sortOrder: index
                        )
                    )
                }
            }
            settings.didSeedCategories = true
        }
        try PhoneDealService.ensureCategories(in: context)
        try context.save()
    }

    @MainActor
    static func ensureSettings(context: ModelContext) throws -> AppSettings {
        let existing = try context.fetch(FetchDescriptor<AppSettings>())
        if let settings = existing.first {
            return settings
        }
        let code = Locale.current.currency?.identifier ?? "USD"
        let settings = AppSettings(baseCurrencyCode: code, firstWeekday: Calendar.current.firstWeekday)
        context.insert(settings)
        return settings
    }
}
