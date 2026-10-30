import SwiftData
import XCTest
@testable import OfflineFinance

@MainActor
final class FinancePersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try AppPersistence.makeInMemoryContainer()
        context = container.mainContext
        try BootstrapService.bootstrap(context: context)
    }

    func testAddEditAndDeleteTransaction() throws {
        let wallet = Wallet(name: "Cash", type: .cash, currencyCode: "USD", openingBalance: 100, iconName: "banknote", colorHex: "1A6B4A")
        context.insert(wallet)
        let category = try context.fetch(FetchDescriptor<OfflineFinance.Category>()).first { $0.name == "Groceries" }
        let transaction = LedgerTransaction(type: .expense, amount: decimal("12.40"), currencyCode: "USD", title: "Market", date: Date())
        transaction.wallet = wallet
        transaction.category = category
        context.insert(transaction)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<LedgerTransaction>())
        XCTAssertEqual(stored.count, 1)
        stored[0].amount = decimal("15")
        stored[0].title = "Updated market"
        try context.save()
        let edited = try context.fetch(FetchDescriptor<LedgerTransaction>())
        XCTAssertEqual(edited[0].amount, decimal("15"))
        XCTAssertEqual(edited[0].title, "Updated market")

        context.delete(edited[0])
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<LedgerTransaction>()).isEmpty)
        let balance = LedgerCalculator.balance(
            of: wallet.financeValue(),
            wallets: [wallet.financeValue()],
            transactions: []
        )
        XCTAssertEqual(balance, decimal("100"))
    }

    func testTransferAndCreditCardPersistence() throws {
        let bank = Wallet(name: "Bank", type: .bank, currencyCode: "USD", openingBalance: decimal("1000"), iconName: "building.columns", colorHex: "1D4E89")
        let card = Wallet(name: "Card", type: .creditCard, currencyCode: "USD", openingBalance: decimal("200"), iconName: "creditcard", colorHex: "8E3140")
        context.insert(bank)
        context.insert(card)
        let charge = LedgerTransaction(type: .expense, amount: decimal("50"), currencyCode: "USD", title: "Dinner", date: Date())
        charge.wallet = card
        context.insert(charge)
        let payment = LedgerTransaction(type: .transfer, amount: decimal("250"), currencyCode: "USD", title: "Card payment", date: Date())
        payment.wallet = bank
        payment.destinationWallet = card
        context.insert(payment)
        try context.save()

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>()).map { $0.financeValue() }
        let wallets = [bank.financeValue(), card.financeValue()]
        let balances = LedgerCalculator.walletBalances(wallets: wallets, transactions: transactions)
        XCTAssertEqual(balances[bank.id], decimal("750"))
        XCTAssertEqual(balances[card.id], decimal("0"))
        XCTAssertEqual(LedgerCalculator.total(transactions, type: .expense, window: wideWindow(), baseCurrency: "USD"), decimal("50"))
        XCTAssertEqual(LedgerCalculator.total(transactions, type: .income, window: wideWindow(), baseCurrency: "USD"), 0)
    }

    func testRecurringGenerationDoesNotDuplicate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let wallet = Wallet(name: "Bank", type: .bank, currencyCode: "USD", openingBalance: 0, iconName: "building.columns", colorHex: "1D4E89")
        context.insert(wallet)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 9))!
        let rule = RecurringRule(
            frequency: .weekly,
            startDate: start,
            templateTitle: "Rent",
            templateAmount: decimal("10"),
            templateType: .expense,
            currencyCode: "USD"
        )
        rule.wallet = wallet
        context.insert(rule)
        try context.save()
        let through = calendar.date(from: DateComponents(year: 2026, month: 1, day: 22))!
        try RecurringService.generateDue(in: context, now: through, calendar: calendar)
        try context.save()
        let first = try context.fetch(FetchDescriptor<LedgerTransaction>())
        XCTAssertEqual(first.count, 4)
        try RecurringService.generateDue(in: context, now: through, calendar: calendar)
        try context.save()
        let second = try context.fetch(FetchDescriptor<LedgerTransaction>())
        XCTAssertEqual(second.count, 4)
        XCTAssertEqual(Set(second.compactMap(\.occurrenceKey)).count, 4)
    }

    func testBackupRestoreReplacesWithoutDuplicating() throws {
        let wallet = Wallet(name: "Keep me", type: .cash, currencyCode: "USD", openingBalance: 5, iconName: "banknote", colorHex: "1A6B4A")
        context.insert(wallet)
        try context.save()
        let document = try BackupApplier.makeDocument(context: context)
        context.insert(Wallet(name: "Extra", type: .cash, currencyCode: "USD", openingBalance: 1, iconName: "banknote", colorHex: "1A6B4A"))
        try context.save()
        try BackupApplier.replaceAll(with: document, in: context)
        try BackupApplier.replaceAll(with: document, in: context)
        let wallets = try context.fetch(FetchDescriptor<Wallet>())
        XCTAssertEqual(wallets.count, 1)
        XCTAssertEqual(wallets.first?.name, "Keep me")
        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(settings.count, 1)
    }

    func testDemoDataCanBeRemovedWithoutDeletingUserData() throws {
        let personal = Wallet(name: "Personal", type: .cash, currencyCode: "USD", openingBalance: 20, iconName: "banknote", colorHex: "1A6B4A")
        context.insert(personal)
        try context.save()
        try DemoDataService.install(in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Wallet>()).contains { $0.isDemo })
        try DemoDataService.remove(in: context)
        let wallets = try context.fetch(FetchDescriptor<Wallet>())
        XCTAssertEqual(wallets.map(\.name), ["Personal"])
        XCTAssertFalse(try context.fetch(FetchDescriptor<LedgerTransaction>()).contains { $0.isDemo })
    }

    func testBootstrapDoesNotDuplicateCategories() throws {
        let first = try context.fetch(FetchDescriptor<OfflineFinance.Category>()).count
        try BootstrapService.bootstrap(context: context)
        let second = try context.fetch(FetchDescriptor<OfflineFinance.Category>()).count
        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(first, 0)
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func wideWindow() -> ReportingWindow {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)
        return ReportingWindow(start: start, endExclusive: end)
    }
}
