import PDFKit
import XCTest
@testable import OfflineFinance

@MainActor
final class FinanceCalculationTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    func testDecimalAdditionAvoidsBinaryError() {
        let total = Money.rounded(decimal("0.10") + decimal("0.20"), currencyCode: "USD")
        XCTAssertEqual(total, decimal("0.30"))
    }

    func testBankersRounding() {
        XCTAssertEqual(Money.rounded(decimal("100.4"), currencyCode: "JPY"), decimal("100"))
        XCTAssertEqual(Money.rounded(decimal("100.5"), currencyCode: "JPY"), decimal("100"))
        XCTAssertEqual(Money.rounded(decimal("101.5"), currencyCode: "JPY"), decimal("102"))
        XCTAssertEqual(Money.rounded(decimal("1.005"), currencyCode: "USD"), decimal("1.00"))
        XCTAssertEqual(Money.rounded(decimal("1.015"), currencyCode: "USD"), decimal("1.02"))
        XCTAssertEqual(Money.rounded(decimal("1.2345"), currencyCode: "KWD"), decimal("1.234"))
    }

    func testRejectsInvalidAmounts() {
        XCTAssertNil(AmountParser.parse("0", currencyCode: "USD"))
        XCTAssertNil(AmountParser.parse("-5", currencyCode: "USD"))
        XCTAssertNil(AmountParser.parse("abc", currencyCode: "USD"))
        XCTAssertNil(AmountParser.parse("0.001", currencyCode: "USD"))
        XCTAssertEqual(AmountParser.parse("1,234.50", currencyCode: "USD"), decimal("1234.50"))
        XCTAssertEqual(AmountParser.parse("1.234,50", currencyCode: "USD"), decimal("1234.50"))
    }

    func testIncomeExpenseAndTransfers() {
        let bank = wallet(name: "Bank", type: .bank, opening: "1000")
        let card = wallet(name: "Card", type: .creditCard, opening: "200")
        let groceries = UUID()
        let window = january()
        let rows = [
            transaction(type: .income, amount: "100", wallet: bank.id, category: groceries, day: 2),
            transaction(type: .expense, amount: "40", wallet: bank.id, category: groceries, day: 3),
            transaction(type: .expense, amount: "50", wallet: card.id, category: groceries, day: 4),
            transaction(type: .transfer, amount: "250", wallet: bank.id, destination: card.id, day: 5),
            transaction(type: .expense, amount: "999", wallet: bank.id, category: groceries, day: 40)
        ]
        XCTAssertEqual(LedgerCalculator.total(rows, type: .income, window: window, baseCurrency: "USD"), decimal("100"))
        XCTAssertEqual(LedgerCalculator.total(rows, type: .expense, window: window, baseCurrency: "USD"), decimal("90"))
        XCTAssertEqual(
            Money.rounded(
                LedgerCalculator.total(rows, type: .income, window: window, baseCurrency: "USD")
                    - LedgerCalculator.total(rows, type: .expense, window: window, baseCurrency: "USD"),
                currencyCode: "USD"
            ),
            decimal("10")
        )
        let report = ReportBuilder.make(
            transactions: rows,
            wallets: [bank, card],
            categories: [],
            budgets: [],
            window: window,
            calendar: calendar,
            baseCurrency: "USD",
            granularity: .month
        )
        XCTAssertEqual(report.net, decimal("10"))
        XCTAssertEqual(report.closingNetWorth - report.openingNetWorth, report.net)
    }

    func testCreditCardLiabilityAndTransferDoesNotChangeNetWorth() {
        let bank = wallet(name: "Bank", type: .bank, opening: "1000")
        let card = wallet(name: "Card", type: .creditCard, opening: "200")
        let before = [
            transaction(type: .expense, amount: "50", wallet: card.id, day: 1)
        ]
        let balances = LedgerCalculator.walletBalances(wallets: [bank, card], transactions: before)
        XCTAssertEqual(balances[card.id], decimal("250"))
        XCTAssertEqual(balances[bank.id], decimal("1000"))
        let afterPayment = before + [
            transaction(type: .transfer, amount: "250", wallet: bank.id, destination: card.id, day: 2)
        ]
        let paid = LedgerCalculator.walletBalances(wallets: [bank, card], transactions: afterPayment)
        XCTAssertEqual(paid[bank.id], decimal("750"))
        XCTAssertEqual(paid[card.id], decimal("0"))
        let worthBefore = LedgerCalculator.netWorth(wallets: [bank, card], transactions: before, baseCurrency: "USD")
        let worthAfter = LedgerCalculator.netWorth(wallets: [bank, card], transactions: afterPayment, baseCurrency: "USD")
        XCTAssertEqual(worthBefore, decimal("750"))
        XCTAssertEqual(worthAfter, worthBefore)
    }

    func testIncomeOnCreditCardReducesLiability() {
        let card = wallet(name: "Card", type: .creditCard, opening: "80")
        let rows = [transaction(type: .income, amount: "30", wallet: card.id, day: 1)]
        let balance = LedgerCalculator.balance(of: card, wallets: [card], transactions: rows)
        XCTAssertEqual(balance, decimal("50"))
    }

    func testForeignCurrencyIsExcludedFromConsolidation() {
        let usd = wallet(name: "USD", type: .bank, opening: "100")
        let eur = wallet(name: "EUR", type: .cash, opening: "50", currency: "EUR")
        let rows = [
            transaction(type: .expense, amount: "20", wallet: eur.id, currency: "EUR", day: 1),
            transaction(type: .income, amount: "10", wallet: usd.id, day: 1)
        ]
        let window = january()
        XCTAssertEqual(LedgerCalculator.total(rows, type: .expense, window: window, baseCurrency: "USD"), 0)
        XCTAssertEqual(LedgerCalculator.total(rows, type: .income, window: window, baseCurrency: "USD"), decimal("10"))
        let worth = LedgerCalculator.netWorth(wallets: [usd, eur], transactions: rows, baseCurrency: "USD")
        XCTAssertEqual(worth, decimal("110"))
        XCTAssertEqual(LedgerCalculator.balance(of: eur, wallets: [usd, eur], transactions: rows), decimal("30"))
    }

    func testArchivedWalletStillAffectsNetWorth() {
        var bank = wallet(name: "Old", type: .bank, opening: "40")
        bank.isArchived = true
        let worth = LedgerCalculator.netWorth(wallets: [bank], transactions: [], baseCurrency: "USD")
        XCTAssertEqual(worth, decimal("40"))
    }

    func testEmptyDataIsZero() {
        let window = january()
        XCTAssertEqual(LedgerCalculator.total([], type: .expense, window: window, baseCurrency: "USD"), 0)
        XCTAssertEqual(LedgerCalculator.netWorth(wallets: [], transactions: [], baseCurrency: "USD"), 0)
        XCTAssertTrue(LedgerCalculator.categoryTotals([], type: .expense, window: window, baseCurrency: "USD", categories: []).isEmpty)
    }

    func testDateCategoryAndWalletFilters() {
        let food = UUID()
        let rent = UUID()
        let bank = wallet(name: "Bank")
        let cash = wallet(name: "Cash")
        let rows = [
            transaction(type: .expense, amount: "10", wallet: bank.id, category: food, day: 1, title: "Market"),
            transaction(type: .expense, amount: "70", wallet: cash.id, category: rent, day: 2, title: "Rent"),
            transaction(type: .expense, amount: "5", wallet: bank.id, category: food, day: 31, hour: 23),
            transaction(type: .expense, amount: "8", wallet: bank.id, category: food, day: 32)
        ]
        let window = january()
        XCTAssertEqual(LedgerCalculator.total(rows, type: .expense, window: window, baseCurrency: "USD", categoryID: food), decimal("15"))
        XCTAssertEqual(LedgerCalculator.total(rows, type: .expense, window: window, baseCurrency: "USD", walletID: cash.id), decimal("70"))
        let boundary = ReportingWindow(
            start: date(2026, 1, 31),
            endExclusive: date(2026, 2, 1)
        )
        XCTAssertEqual(LedgerCalculator.total(rows, type: .expense, window: boundary, baseCurrency: "USD"), decimal("5"))
    }

    func testSearchSortAndLargeHistory() {
        let bank = wallet(name: "Bank")
        var rows: [FinanceTransaction] = []
        for index in 0..<3000 {
            rows.append(transaction(type: .expense, amount: "0.01", wallet: bank.id, day: 1, title: index == 10 ? "Special coffee" : "Item", notes: index == 11 ? "alpha note" : ""))
        }
        let window = january()
        XCTAssertEqual(LedgerCalculator.total(rows, type: .expense, window: window, baseCurrency: "USD"), decimal("30"))
        let filtered = TransactionQuery.apply(
            rows,
            filter: TransactionFilter(query: "coffee", walletID: bank.id, sort: .amountHighest),
            calendar: calendar
        )
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "Special coffee")
        let notes = TransactionQuery.apply(rows, filter: TransactionFilter(query: "alpha"), calendar: calendar)
        XCTAssertEqual(notes.count, 1)
    }

    func testBudgetThresholdsExcludeIncomeAndTransfers() {
        let food = UUID()
        let bank = wallet(name: "Bank")
        let budget = FinanceBudget(
            id: UUID(),
            name: "Groceries",
            amount: decimal("100"),
            currencyCode: "USD",
            startDate: date(2026, 1, 1),
            endDate: date(2026, 2, 1),
            warningThreshold: decimal("0.8"),
            isOverall: false,
            categoryID: food,
            isPaused: false,
            isArchived: false
        )
        var rows = [
            transaction(type: .income, amount: "1000", wallet: bank.id, day: 1),
            transaction(type: .transfer, amount: "500", wallet: bank.id, destination: UUID(), day: 1),
            transaction(type: .expense, amount: "40", wallet: bank.id, category: food, day: 2)
        ]
        XCTAssertEqual(BudgetCalculator.spent(budget: budget, transactions: rows), decimal("40"))
        XCTAssertEqual(BudgetCalculator.alertLevel(for: budget, transactions: rows), .withinBudget)
        rows.append(transaction(type: .expense, amount: "40", wallet: bank.id, category: food, day: 3))
        XCTAssertEqual(BudgetCalculator.alertLevel(for: budget, transactions: rows), .warning)
        rows.append(transaction(type: .expense, amount: "20", wallet: bank.id, category: food, day: 4))
        XCTAssertEqual(BudgetCalculator.alertLevel(for: budget, transactions: rows), .reached)
        rows.append(transaction(type: .expense, amount: "0.01", wallet: bank.id, category: food, day: 5))
        XCTAssertEqual(BudgetCalculator.alertLevel(for: budget, transactions: rows), .exceeded)
        var paused = budget
        paused.isPaused = true
        XCTAssertNil(BudgetCalculator.alertLevel(for: paused, transactions: rows))
    }

    func testTransferValidation() {
        let cash = wallet(name: "Cash", type: .cash, opening: "20")
        let message = ValidationService.transferFundsMessage(source: cash, sourceBalance: decimal("20"), amount: decimal("25"))
        XCTAssertNotNil(message)
        XCTAssertNil(ValidationService.transferFundsMessage(source: cash, sourceBalance: decimal("30"), amount: decimal("25")))
        let card = wallet(name: "Card", type: .creditCard, opening: "0")
        XCTAssertNil(ValidationService.transferFundsMessage(source: card, sourceBalance: decimal("0"), amount: decimal("25")))
    }

    func testCSVEscapingAndColumns() {
        let bank = wallet(name: "Bank")
        let row = FinanceTransaction(
            id: UUID(),
            type: .expense,
            amount: decimal("12.50"),
            currencyCode: "USD",
            date: date(2026, 1, 5),
            title: "Cafe, \"Main\"",
            notes: "Line one\nLine two",
            merchant: "Cafe",
            tags: ["food", "weekly"],
            categoryID: nil,
            walletID: bank.id,
            destinationWalletID: nil,
            paymentMethod: .cash
        )
        let csv = CSVExporter.make(transactions: [row], categories: [], wallets: [bank], calendar: calendar)
        XCTAssertTrue(csv.hasPrefix("Date,Type,Title,Category,Wallet,Amount,Currency,Payment method,Notes,Tags"))
        XCTAssertTrue(csv.contains("\"Cafe, \"\"Main\"\"\""))
        XCTAssertTrue(csv.contains("\"Line one\nLine two\""))
        XCTAssertTrue(csv.contains("2026-01-05"))
        XCTAssertTrue(csv.contains("12.5"))
        let data = CSVExporter.data(transactions: [row], categories: [], wallets: [bank], calendar: calendar)
        XCTAssertEqual(String(data: data, encoding: .utf8), csv)
    }

    func testPDFContainsSummaryAndMultiplePages() {
        let bank = wallet(name: "Bank", type: .bank, opening: "500")
        var rows: [FinanceTransaction] = []
        for index in 0..<80 {
            rows.append(transaction(type: .expense, amount: "3.25", wallet: bank.id, day: (index % 27) + 1, title: "Expense \(index)"))
        }
        let window = january()
        let report = ReportBuilder.make(
            transactions: rows,
            wallets: [bank],
            categories: [],
            budgets: [],
            window: window,
            calendar: calendar,
            baseCurrency: "USD",
            granularity: .month
        )
        let data = PDFExporter.make(PDFReportRequest(
            title: "Finance report",
            periodLabel: "January 2026",
            generatedAt: date(2026, 2, 1),
            report: report,
            transactions: rows,
            categories: [],
            wallets: [bank],
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        ))
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let document = PDFExporter.document(from: data)
        XCTAssertGreaterThan(document?.pageCount ?? 0, 1)
        XCTAssertTrue(document?.string?.contains("Net cash flow") == true)
        XCTAssertTrue(document?.string?.contains("Opening balance") == true)
    }

    func testBackupRoundTripAndRejection() throws {
        let document = sampleBackup()
        let data = try BackupCodec.encode(document)
        let decoded = try BackupCodec.decode(data)
        XCTAssertEqual(decoded.transactions.first?.amount, "19.95")
        XCTAssertEqual(decoded.version, 1)
        var duplicate = document
        duplicate.transactions.append(document.transactions[0])
        XCTAssertThrowsError(try BackupCodec.validate(duplicate)) { error in
            XCTAssertEqual(error as? BackupError, .invalid("The backup contains duplicate transactions."))
        }
        var badVersion = document
        badVersion.version = 99
        XCTAssertThrowsError(try BackupCodec.validate(badVersion))
        var corrupt = document
        corrupt.format = "something-else"
        XCTAssertThrowsError(try BackupCodec.decode(try BackupCodec.encode(corrupt)))
    }

    func testBackupWithoutPhoneDealsStillDecodes() throws {
        let data = try BackupCodec.encode(sampleBackup())
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        root.removeValue(forKey: "phoneDeals")
        let stripped = try JSONSerialization.data(withJSONObject: root)
        let decoded = try BackupCodec.decode(stripped)
        XCTAssertEqual(decoded.phoneDeals, [])
        XCTAssertEqual(decoded.transactions.first?.amount, "19.95")
    }

    func testUnsoldPhoneStaysInStockWithNoPendingPayment() {
        let position = PhoneDealCalculator.position(for: phoneLot(purchase: 45000))
        XCTAssertEqual(position.stage, .inStock)
        XCTAssertEqual(position.stockCost, 45000)
        XCTAssertEqual(position.soldCost, 0)
        XCTAssertEqual(position.pendingPayment, 0)
        XCTAssertEqual(position.successfulPayment, 0)
        XCTAssertEqual(position.profit, 0)
    }

    func testSoldPhoneWithNoReceiptIsFullyPending() {
        let position = PhoneDealCalculator.position(for: phoneLot(purchase: 45000, sold: true, quantitySold: 1, sale: 47000))
        XCTAssertEqual(position.stage, .paymentPending)
        XCTAssertEqual(position.pendingPayment, 47000)
        XCTAssertEqual(position.successfulPayment, 0)
        XCTAssertEqual(position.profit, 2000)
        XCTAssertEqual(position.stockCost, 0)
    }

    func testPartialDealerPaymentLeavesTheRemainderPending() {
        let position = PhoneDealCalculator.position(for: phoneLot(purchase: 45000, sold: true, quantitySold: 1, sale: 47000, received: 20000))
        XCTAssertEqual(position.stage, .paymentPending)
        XCTAssertEqual(position.pendingPayment, 27000)
        XCTAssertEqual(position.successfulPayment, 20000)
        XCTAssertEqual(position.profit, 2000)
    }

    func testFullDealerPaymentIsSettled() {
        let position = PhoneDealCalculator.position(for: phoneLot(purchase: 45000, sold: true, quantitySold: 1, sale: 47000, received: 47000))
        XCTAssertEqual(position.stage, .settled)
        XCTAssertEqual(position.pendingPayment, 0)
        XCTAssertEqual(position.successfulPayment, 47000)
    }

    func testPartialQuantitySplitsCostBetweenStockAndSoldPhones() {
        let position = PhoneDealCalculator.position(for: phoneLot(quantity: 2, purchase: 90000, sold: true, quantitySold: 1, sale: 48000))
        XCTAssertEqual(position.soldCost, 45000)
        XCTAssertEqual(position.stockCost, 45000)
        XCTAssertEqual(position.pendingPayment, 48000)
        XCTAssertEqual(position.profit, 3000)
    }

    func testOverpaymentDoesNotShowANegativePendingBalance() {
        let position = PhoneDealCalculator.position(for: phoneLot(purchase: 45000, sold: true, quantitySold: 1, sale: 47000, received: 50000))
        XCTAssertEqual(position.pendingPayment, 0)
        XCTAssertEqual(position.successfulPayment, 50000)
        XCTAssertEqual(position.stage, .settled)
    }

    func testRecurringOccurrencesDoNotDuplicate() {
        let ruleID = UUID()
        let plan = RecurrencePlan(
            id: ruleID,
            frequency: .weekly,
            start: date(2026, 1, 1, 9),
            end: nil,
            isPaused: false,
            emittedKeys: []
        )
        let dates = RecurringScheduler.occurrenceDates(plan: plan, through: date(2026, 1, 22, 12), calendar: calendar)
        XCTAssertEqual(dates.count, 4)
        let keys = Set(dates.map { RecurringScheduler.occurrenceKey(ruleID: ruleID, date: $0, calendar: calendar) })
        XCTAssertEqual(keys.count, 4)
        var emitted = plan
        emitted.emittedKeys = keys
        XCTAssertTrue(RecurringScheduler.occurrenceDates(plan: emitted, through: date(2026, 1, 22, 12), calendar: calendar).isEmpty)
        var paused = plan
        paused.isPaused = true
        XCTAssertTrue(RecurringScheduler.occurrenceDates(plan: paused, through: date(2026, 1, 22, 12), calendar: calendar).isEmpty)
    }

    func testPausedGapIsSuppressedOnResume() {
        let ruleID = UUID()
        let plan = RecurrencePlan(
            id: ruleID,
            frequency: .weekly,
            start: date(2026, 1, 1),
            end: nil,
            isPaused: false,
            emittedKeys: []
        )
        let keys = RecurringScheduler.keysToSuppress(
            plan: plan,
            pausedAt: date(2026, 1, 1),
            through: date(2026, 1, 20),
            calendar: calendar
        )
        XCTAssertEqual(keys.count, 2)
        XCTAssertFalse(keys.contains(RecurringScheduler.occurrenceKey(ruleID: ruleID, date: date(2026, 1, 1), calendar: calendar)))
    }

    private func january() -> ReportingWindow {
        ReportingWindow(start: date(2026, 1, 1), endExclusive: date(2026, 2, 1))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func wallet(
        name: String,
        type: WalletType = .bank,
        opening: String = "0",
        currency: String = "USD"
    ) -> FinanceWallet {
        FinanceWallet(
            id: UUID(),
            name: name,
            type: type,
            currencyCode: currency,
            openingBalance: decimal(opening),
            isArchived: false,
            iconName: "banknote",
            colorHex: "1A6B4A"
        )
    }

    private func transaction(
        type: TransactionType,
        amount: String,
        wallet: UUID,
        destination: UUID? = nil,
        category: UUID? = nil,
        currency: String = "USD",
        day: Int,
        hour: Int = 12,
        title: String = "Transaction",
        notes: String = ""
    ) -> FinanceTransaction {
        let resolvedDay = day > 31 ? day - 31 : day
        let month = day > 31 ? 2 : 1
        return FinanceTransaction(
            id: UUID(),
            type: type,
            amount: decimal(amount),
            currencyCode: currency,
            date: date(2026, month, resolvedDay, hour),
            title: title,
            notes: notes,
            merchant: "",
            tags: [],
            categoryID: category,
            walletID: wallet,
            destinationWalletID: destination,
            paymentMethod: nil
        )
    }

    private func phoneLot(
        quantity: Int = 1,
        purchase: Decimal,
        sold: Bool = false,
        quantitySold: Int = 0,
        sale: Decimal = 0,
        received: Decimal = 0
    ) -> PhoneLot {
        PhoneLot(
            id: UUID(),
            quantity: quantity,
            purchaseAmount: purchase,
            currencyCode: "INR",
            isSold: sold,
            quantitySold: quantitySold,
            saleAmount: sale,
            amountReceived: received
        )
    }

    private func sampleBackup() -> BackupDocument {
        let categoryID = UUID()
        let walletID = UUID()
        let settingsID = UUID()
        return BackupDocument(
            format: BackupCodec.formatIdentifier,
            version: 1,
            exportedAt: date(2026, 1, 15, 8),
            appVersion: "1.0",
            settings: SettingsRecord(
                id: settingsID,
                baseCurrencyCode: "USD",
                dateFormat: DateFormatPreference.medium.rawValue,
                firstWeekday: 2,
                appearance: AppearancePreference.system.rawValue,
                biometricLockEnabled: false,
                budgetNotificationsEnabled: false,
                warningThreshold: "0.8",
                didSeedCategories: true,
                demoDataInstalled: false
            ),
            categories: [
                CategoryRecord(id: categoryID, name: "Food", kind: CategoryKind.expense.rawValue, iconName: "fork.knife", colorHex: "8C4A32", sortOrder: 0, isArchived: false, createdAt: date(2026, 1, 1))
            ],
            wallets: [
                WalletRecord(id: walletID, name: "Cash", type: WalletType.cash.rawValue, currencyCode: "USD", openingBalance: "10", iconName: "banknote", colorHex: "1A6B4A", createdAt: date(2026, 1, 1), isArchived: false, isDemo: false)
            ],
            budgets: [],
            recurringRules: [],
            transactions: [
                TransactionRecord(
                    id: UUID(),
                    type: TransactionType.expense.rawValue,
                    amount: "19.95",
                    currencyCode: "USD",
                    title: "Lunch",
                    notes: "",
                    date: date(2026, 1, 3, 12),
                    createdAt: date(2026, 1, 3, 12),
                    updatedAt: date(2026, 1, 3, 12),
                    tags: [],
                    paymentMethod: nil,
                    merchant: "",
                    attachmentFileName: nil,
                    attachmentBase64: nil,
                    isDemo: false,
                    occurrenceKey: nil,
                    categoryID: categoryID,
                    walletID: walletID,
                    destinationWalletID: nil,
                    recurringRuleID: nil
                )
            ]
        )
    }
}
