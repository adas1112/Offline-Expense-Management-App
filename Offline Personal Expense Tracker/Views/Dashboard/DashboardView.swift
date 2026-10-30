import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query(sort: \Budget.name) private var budgets: [Budget]
    @Query(sort: \PhoneDeal.purchaseDate, order: .reverse) private var phoneDeals: [PhoneDeal]
    @Query private var settingsRows: [AppSettings]
    @State private var model = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if activeWallets.isEmpty {
                        SectionCard(title: "Get started", subtitle: "Your ledger is stored only on this device.") {
                            EmptyStateView(
                                title: "Add a wallet",
                                message: "Create a cash, bank, or credit card wallet before recording transactions.",
                                systemImage: "wallet.pass",
                                actionTitle: "New wallet",
                                action: { showWallets = true }
                            )
                        }
                        phoneCard
                    } else {
                        summaryCard
                        quickActions
                        phoneCard
                        if report.excludedForeignWalletCount > 0 {
                            Text("Wallets in other currencies are shown on their own cards and are not added into these totals.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        cashFlowCard
                        categoryCard
                        budgetCard
                        walletCard
                        recentCard
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PeriodMenu(preset: $model.preset)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.createType = .expense
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add transaction")
                    .disabled(activeWallets.isEmpty)
                }
            }
            .navigationDestination(isPresented: $showWallets) {
                WalletListView()
            }
        }
    }

    @State private var showWallets = false

    private var settings: AppSettings? { settingsRows.first }
    private var calendar: Calendar {
        ReportingPeriod.calendar(firstWeekday: settings?.firstWeekday ?? 1)
    }
    private var currency: String { settings?.baseCurrencyCode ?? "USD" }
    private var activeWallets: [Wallet] { wallets.filter { !$0.isArchived } }
    private var window: ReportingWindow { model.window(calendar: calendar) }
    private var report: FinanceReport {
        ReportBuilder.make(
            transactions: transactions.map { $0.financeValue() },
            wallets: wallets.map { $0.financeValue() },
            categories: categories.map { $0.financeValue() },
            budgets: budgets.map { $0.financeValue() },
            window: window,
            calendar: calendar,
            baseCurrency: currency,
            granularity: ReportBuilder.automaticGranularity(for: window, calendar: calendar)
        )
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Net worth")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(DisplayFormat.money(report.currentNetWorth, currencyCode: currency))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(ReportingPeriod.label(for: window, calendar: calendar, style: settings?.dateFormat ?? .medium))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if model.preset == .custom {
                CustomRangeFields(start: $model.customStart, end: $model.customEnd)
            }
            HStack(spacing: 0) {
                MetricColumn(title: "Income", value: DisplayFormat.money(report.income, currencyCode: currency), tint: Theme.income)
                MetricColumn(title: "Expenses", value: DisplayFormat.money(report.expense, currencyCode: currency), tint: Theme.expense)
                MetricColumn(
                    title: "Cash flow",
                    value: DisplayFormat.money(report.net, currencyCode: currency, direction: report.net < 0 ? .expense : .income),
                    tint: report.net < 0 ? Theme.expense : Theme.income
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var phoneCard: some View {
        let book = PhoneDealCalculator.summary(lots: phoneDeals.map { $0.lot() }, currencyCode: currency)
        return SectionCard(title: "Phone resale", subtitle: "Card-offer purchases sold to dealers.") {
            if phoneDeals.isEmpty {
                Text("Track phones you buy on Amazon, Flipkart, or JioMart, then see which dealer payments are still pending.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    MetricColumn(title: "Pending", value: DisplayFormat.money(book.pendingPayment, currencyCode: currency), tint: .orange)
                    MetricColumn(title: "Received", value: DisplayFormat.money(book.successfulPayment, currencyCode: currency), tint: Theme.income)
                }
            }
            Button("Open phones") { router.tab = .phones }
                .font(.subheadline.weight(.semibold))
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            QuickAction(title: "Income", systemImage: "arrow.down.circle") { router.createType = .income }
            QuickAction(title: "Expense", systemImage: "arrow.up.circle") { router.createType = .expense }
            QuickAction(title: "Transfer", systemImage: "arrow.left.arrow.right") { router.createType = .transfer }
            QuickAction(title: "Reports", systemImage: "chart.bar") { router.tab = .reports }
        }
    }

    private var cashFlowCard: some View {
        SectionCard(title: "Income and expenses", subtitle: "Transfers are not included.") {
            if report.income == 0 && report.expense == 0 {
                Text("No income or expenses in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(report.cashFlow) { point in
                    BarMark(
                        x: .value("Period", point.label),
                        y: .value("Amount", chartDouble(point.income))
                    )
                    .foregroundStyle(by: .value("Series", "Income"))
                    BarMark(
                        x: .value("Period", point.label),
                        y: .value("Amount", chartDouble(point.expense))
                    )
                    .foregroundStyle(by: .value("Series", "Expenses"))
                }
                .chartForegroundStyleScale([
                    "Income": Theme.income,
                    "Expenses": Theme.expense
                ])
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
                .accessibilityLabel("Income \(DisplayFormat.money(report.income, currencyCode: currency)), expenses \(DisplayFormat.money(report.expense, currencyCode: currency))")
            }
        }
    }

    private var categoryCard: some View {
        SectionCard(title: "Spending by category") {
            if report.expenseByCategory.isEmpty {
                Text("No expenses in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(report.expenseByCategory) { row in
                    SectorMark(
                        angle: .value("Amount", chartDouble(row.amount)),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.2
                    )
                    .foregroundStyle(Color(hex: row.colorHex))
                }
                .frame(height: 180)
                .accessibilityLabel(categoryAccessibility)
                VStack(spacing: 8) {
                    ForEach(report.expenseByCategory.prefix(5)) { row in
                        HStack {
                            Circle()
                                .fill(Color(hex: row.colorHex))
                                .frame(width: 8, height: 8)
                            Text(row.name)
                                .font(.subheadline)
                            Spacer()
                            Text(DisplayFormat.money(row.amount, currencyCode: currency))
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private var categoryAccessibility: String {
        report.expenseByCategory.prefix(5).map { "\($0.name) \(DisplayFormat.money($0.amount, currencyCode: currency))" }.joined(separator: ", ")
    }

    private var budgetCard: some View {
        SectionCard(title: "Budgets") {
            let lines = report.budgetLines.filter { $0.level != nil }.prefix(3)
            if lines.isEmpty {
                Text("No active budgets.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(lines)) { line in
                        BudgetProgress(line: line, currencyCode: currency)
                    }
                }
            }
            Button("View budgets") { router.tab = .budgets }
                .font(.subheadline.weight(.semibold))
        }
    }

    private var walletCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wallets")
                    .font(.headline)
                Spacer()
                Button("Manage") { showWallets = true }
                    .font(.subheadline.weight(.semibold))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(wallets.filter { !$0.isArchived }) { wallet in
                        NavigationLink {
                            WalletDetailView(wallet: wallet)
                        } label: {
                            walletTile(wallet)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func walletTile(_ wallet: Wallet) -> some View {
        let line = report.walletBalances.first { $0.id == wallet.id }
        let balance = line?.balance ?? wallet.openingBalance
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: wallet.iconName)
                Spacer()
                Circle().fill(Color(hex: wallet.colorHex)).frame(width: 8, height: 8)
            }
            .foregroundStyle(.secondary)
            Text(wallet.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(wallet.walletType.isLiability ? "Owed" : "Balance")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(DisplayFormat.money(balance, currencyCode: wallet.currencyCode))
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(width: 168, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var recentCard: some View {
        SectionCard(title: "Recent transactions") {
            let recent = transactions
                .filter { window.contains($0.date) }
                .sorted { $0.date > $1.date }
                .prefix(5)
            if recent.isEmpty {
                Text("No transactions in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(recent)) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            TransactionRow(
                                transaction: transaction,
                                currencyDisplay: signedAmount(transaction)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func signedAmount(_ transaction: LedgerTransaction) -> String {
        let direction: MoneyDirection
        switch transaction.transactionType {
        case .income: direction = .income
        case .expense: direction = .expense
        case .transfer: direction = .transfer
        }
        return DisplayFormat.money(transaction.amount, currencyCode: transaction.currencyCode, direction: direction)
    }
}
