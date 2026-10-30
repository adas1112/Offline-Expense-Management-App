import Foundation
import SwiftData

@MainActor
enum DemoDataService {
    static func install(in context: ModelContext, now: Date = Date()) throws {
        let settings = try BootstrapService.ensureSettings(context: context)
        guard !settings.demoDataInstalled else { return }
        let currency = settings.baseCurrencyCode
        let calendar = Calendar(identifier: .gregorian)
        let categories = try context.fetch(FetchDescriptor<Category>())

        func category(_ name: String) -> Category? {
            categories.first { $0.name == name }
        }

        func decimal(_ value: String) -> Decimal { Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }

        let cash = Wallet(name: "Cash", type: .cash, currencyCode: currency, openingBalance: decimal("120"), iconName: "banknote", colorHex: "1A6B4A", isDemo: true)
        let checking = Wallet(name: "Main account", type: .bank, currencyCode: currency, openingBalance: decimal("2400"), iconName: "building.columns", colorHex: "1D4E89", isDemo: true)
        let savings = Wallet(name: "Savings", type: .savings, currencyCode: currency, openingBalance: decimal("5000"), iconName: "tray.full", colorHex: "2F6F73", isDemo: true)
        let card = Wallet(name: "Credit card", type: .creditCard, currencyCode: currency, openingBalance: decimal("180"), iconName: "creditcard", colorHex: "8E3140", isDemo: true)
        let travel = Wallet(name: "Travel cash", type: .cash, currencyCode: currency == "EUR" ? "USD" : "EUR", openingBalance: decimal("80"), iconName: "airplane", colorHex: "6B4C9A", isDemo: true)
        for wallet in [cash, checking, savings, card, travel] {
            context.insert(wallet)
        }

        func add(
            _ title: String,
            type: TransactionType,
            amount: Decimal,
            wallet: Wallet,
            destination: Wallet? = nil,
            category: Category?,
            daysAgo: Int,
            merchant: String = "",
            notes: String = "",
            currencyCode: String? = nil
        ) {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            let transaction = LedgerTransaction(
                type: type,
                amount: amount,
                currencyCode: currencyCode ?? wallet.currencyCode,
                title: title,
                notes: notes,
                date: date,
                merchant: merchant,
                isDemo: true
            )
            transaction.wallet = wallet
            transaction.destinationWallet = destination
            transaction.category = category
            context.insert(transaction)
        }

        add("Monthly salary", type: .income, amount: decimal("3200"), wallet: checking, category: category("Salary"), daysAgo: 12, merchant: "Employer")
        add("Freelance invoice", type: .income, amount: decimal("450"), wallet: checking, category: category("Freelance"), daysAgo: 40)
        add("Grocery run", type: .expense, amount: decimal("86.40"), wallet: cash, category: category("Groceries"), daysAgo: 2, merchant: "Market")
        add("Dinner", type: .expense, amount: decimal("42.15"), wallet: card, category: category("Food"), daysAgo: 4, merchant: "Neighborhood bistro")
        add("Rent", type: .expense, amount: decimal("1400"), wallet: checking, category: category("Housing"), daysAgo: 10, merchant: "Landlord")
        add("Transit pass", type: .expense, amount: decimal("64"), wallet: checking, category: category("Transport"), daysAgo: 18)
        add("Electric bill", type: .expense, amount: decimal("73.20"), wallet: checking, category: category("Utilities"), daysAgo: 21)
        add("Pharmacy", type: .expense, amount: decimal("18.90"), wallet: cash, category: category("Healthcare"), daysAgo: 6)
        add("Cinema", type: .expense, amount: decimal("16"), wallet: card, category: category("Entertainment"), daysAgo: 8)
        add("Savings transfer", type: .transfer, amount: decimal("300"), wallet: checking, destination: savings, category: nil, daysAgo: 11, notes: "Monthly savings")
        add("Card payment", type: .transfer, amount: decimal("180"), wallet: checking, destination: card, category: nil, daysAgo: 9, notes: "Pay credit card")
        add("Last month groceries", type: .expense, amount: decimal("210.55"), wallet: checking, category: category("Groceries"), daysAgo: 35)
        add("Train tickets", type: .expense, amount: decimal("48"), wallet: travel, category: category("Travel"), daysAgo: 15, currencyCode: travel.currencyCode)

        let month = ReportingPeriod.monthWindow(containing: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: -1, to: month.endExclusive) ?? now
        if let groceries = category("Groceries") {
            let groceryBudget = Budget(
                name: "Groceries",
                amount: decimal("400"),
                currencyCode: currency,
                startDate: month.start,
                endDate: end,
                isOverall: false,
                isDemo: true,
                notifyAtWarning: true
            )
            groceryBudget.category = groceries
            context.insert(groceryBudget)
        }
        context.insert(
            Budget(
                name: "Monthly spending",
                amount: decimal("2500"),
                currencyCode: currency,
                startDate: month.start,
                endDate: end,
                isOverall: true,
                isDemo: true,
                notifyAtExceeded: true
            )
        )

        settings.demoDataInstalled = true
        try context.save()
    }

    static func remove(in context: ModelContext) throws {
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        for transaction in transactions where transaction.isDemo {
            AttachmentStore.delete(fileName: transaction.attachmentFileName)
            context.delete(transaction)
        }
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        for budget in budgets where budget.isDemo {
            context.delete(budget)
        }
        let rules = try context.fetch(FetchDescriptor<RecurringRule>())
        for rule in rules where rule.isDemo {
            context.delete(rule)
        }
        try context.save()
        let wallets = try context.fetch(FetchDescriptor<Wallet>())
        for wallet in wallets where wallet.isDemo {
            let stillUsed = wallet.transactions.isEmpty == false || wallet.incomingTransfers.isEmpty == false
            if stillUsed {
                wallet.isDemo = false
            } else {
                context.delete(wallet)
            }
        }
        if let settings = try context.fetch(FetchDescriptor<AppSettings>()).first {
            settings.demoDataInstalled = false
        }
        try context.save()
    }
}
