import Charts
import SwiftData
import SwiftUI

struct ReportsView: View {
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Budget.name) private var budgets: [Budget]
    @Query private var settingsRows: [AppSettings]
    @State private var model = ReportViewModel()
    @State private var exportFile: ExportedFile?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.preset == .custom {
                        SectionCard(title: "Custom range") {
                            CustomRangeFields(start: $model.customStart, end: $model.customEnd)
                        }
                    }
                    summary
                    cashFlow
                    trend
                    expenseCategories
                    incomeCategories
                    walletSpending
                    budgetComparison
                    largest
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PeriodMenu(preset: $model.preset)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Wallet", selection: $model.walletID) {
                            Text("All wallets").tag(Optional<UUID>.none)
                            ForEach(wallets.filter { !$0.isArchived }) { wallet in
                                Text(wallet.name).tag(Optional(wallet.id))
                            }
                        }
                        Button("Export PDF") { exportPDF() }
                        Button("Export CSV") { exportCSV() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export report")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Picker("Trend", selection: $model.granularity) {
                    ForEach(TrendGranularity.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .sheet(item: $exportFile) { file in
                ExportPreviewSheet(file: file)
            }
            .alert("Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private var settings: AppSettings? { settingsRows.first }
    private var calendar: Calendar { ReportingPeriod.calendar(firstWeekday: settings?.firstWeekday ?? 1) }
    private var currency: String { settings?.baseCurrencyCode ?? "USD" }
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
            granularity: model.granularity,
            walletID: model.walletID
        )
    }
    private var periodTransactions: [FinanceTransaction] {
        let values = transactions.map { $0.financeValue() }
        return values.filter { transaction in
            window.contains(transaction.date) && transaction.currencyCode == currency && (model.walletID == nil || transaction.walletID == model.walletID || transaction.destinationWalletID == model.walletID)
        }
    }

    private var summary: some View {
        SectionCard(title: "Summary", subtitle: ReportingPeriod.label(for: window, calendar: calendar, style: settings?.dateFormat ?? .medium)) {
            HStack {
                MetricColumn(title: "Income", value: DisplayFormat.money(report.income, currencyCode: currency), tint: Theme.income)
                MetricColumn(title: "Expenses", value: DisplayFormat.money(report.expense, currencyCode: currency), tint: Theme.expense)
                MetricColumn(title: "Net", value: DisplayFormat.money(report.net, currencyCode: currency), tint: .primary)
            }
            LabeledContent("Opening balance", value: DisplayFormat.money(report.openingNetWorth, currencyCode: currency))
            LabeledContent("Closing balance", value: DisplayFormat.money(report.closingNetWorth, currencyCode: currency))
        }
    }

    private var cashFlow: some View {
        SectionCard(title: "Income versus expenses") {
            chartOrEmpty(isEmpty: report.cashFlow.allSatisfy { $0.income == 0 && $0.expense == 0 }) {
                Chart(report.cashFlow) { point in
                    BarMark(x: .value("Period", point.label), y: .value("Amount", chartDouble(point.income)))
                        .foregroundStyle(by: .value("Series", "Income"))
                    BarMark(x: .value("Period", point.label), y: .value("Amount", chartDouble(point.expense)))
                        .foregroundStyle(by: .value("Series", "Expenses"))
                }
                .chartForegroundStyleScale(["Income": Theme.income, "Expenses": Theme.expense])
                .frame(height: 200)
            }
        }
    }

    private var trend: some View {
        SectionCard(title: "Cash flow trend") {
            chartOrEmpty(isEmpty: report.cashFlow.allSatisfy { $0.net == 0 }) {
                Chart(report.cashFlow) { point in
                    LineMark(
                        x: .value("Period", point.label),
                        y: .value("Net", chartDouble(point.net))
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 180)
                .accessibilityLabel("Net cash flow over the selected period is \(DisplayFormat.money(report.net, currencyCode: currency))")
            }
        }
    }

    private var expenseCategories: some View {
        SectionCard(title: "Expenses by category") {
            donut(report.expenseByCategory, empty: "No expenses in this period.")
        }
    }

    private var incomeCategories: some View {
        SectionCard(title: "Income by category") {
            donut(report.incomeByCategory, empty: "No income in this period.")
        }
    }

    private var walletSpending: some View {
        SectionCard(title: "Spending by wallet") {
            chartOrEmpty(isEmpty: report.expenseByWallet.isEmpty) {
                Chart(report.expenseByWallet) { row in
                    BarMark(
                        x: .value("Amount", chartDouble(row.amount)),
                        y: .value("Wallet", row.name)
                    )
                    .foregroundStyle(Color(hex: row.colorHex))
                }
                .frame(height: CGFloat(max(report.expenseByWallet.count, 1)) * 36 + 20)
            }
        }
    }

    private var budgetComparison: some View {
        SectionCard(title: "Budget versus actual", subtitle: "Based on each budget’s own dates.") {
            let lines = report.budgetLines.filter { !$0.isOverall || true }
            if lines.isEmpty {
                Text("No budgets to compare.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(lines) { line in
                    BarMark(x: .value("Kind", "Budget"), y: .value("Amount", chartDouble(line.limit)))
                        .foregroundStyle(by: .value("Series", "Budget"))
                        .position(by: .value("Budget", line.name))
                    BarMark(x: .value("Kind", "Actual"), y: .value("Amount", chartDouble(line.spent)))
                        .foregroundStyle(by: .value("Series", "Actual"))
                        .position(by: .value("Budget", line.name))
                }
                .chartForegroundStyleScale(["Budget": Color.accentColor.opacity(0.45), "Actual": Theme.expense])
                .frame(height: 200)
            }
        }
    }

    private var largest: some View {
        SectionCard(title: "Largest expenses") {
            if report.largestExpenses.isEmpty {
                Text("No expenses in this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(report.largestExpenses) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title).font(.subheadline.weight(.semibold))
                                Text("\(row.categoryName) · \(row.walletName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DisplayFormat.money(row.amount, currencyCode: currency, direction: .expense))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.expense)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func donut(_ rows: [CategoryTotal], empty: String) -> some View {
        if rows.isEmpty {
            Text(empty).font(.subheadline).foregroundStyle(.secondary)
        } else {
            Chart(rows) { row in
                SectorMark(
                    angle: .value("Amount", chartDouble(row.amount)),
                    innerRadius: .ratio(0.6),
                    angularInset: 1.2
                )
                .foregroundStyle(Color(hex: row.colorHex))
            }
            .frame(height: 180)
            .accessibilityLabel(rows.map { "\($0.name) \(DisplayFormat.percent($0.fraction))" }.joined(separator: ", "))
            ForEach(rows.prefix(6)) { row in
                HStack {
                    Text(row.name)
                    Spacer()
                    Text(DisplayFormat.percent(row.fraction))
                        .foregroundStyle(.secondary)
                    Text(DisplayFormat.money(row.amount, currencyCode: currency))
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func chartOrEmpty(isEmpty: Bool, @ViewBuilder chart: () -> some View) -> some View {
        if isEmpty {
            Text("No data for this period.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            chart()
        }
    }

    private func exportPDF() {
        let request = PDFReportRequest(
            title: "Finance report",
            periodLabel: ReportingPeriod.label(for: window, calendar: calendar, style: settings?.dateFormat ?? .medium),
            generatedAt: Date(),
            report: report,
            transactions: periodTransactions.sorted { $0.date > $1.date },
            categories: categories.map { $0.financeValue() },
            wallets: wallets.map { $0.financeValue() },
            calendar: calendar
        )
        let data = PDFExporter.make(request)
        write(data: data, name: "FinanceReport-\(stamp).pdf", folder: "Exports", showsPDF: true)
    }

    private func exportCSV() {
        let data = CSVExporter.data(
            transactions: periodTransactions.sorted { $0.date > $1.date },
            categories: categories.map { $0.financeValue() },
            wallets: wallets.map { $0.financeValue() },
            calendar: calendar
        )
        write(data: data, name: "Transactions-\(stamp).csv", folder: "Exports", showsPDF: false)
    }

    private func write(data: Data, name: String, folder: String, showsPDF: Bool) {
        do {
            let url = try ExportFiles.write(data: data, name: name, folder: folder)
            exportFile = ExportedFile(url: url, showsPDF: showsPDF)
        } catch {
            exportError = "The file could not be created on this device."
        }
    }

    private var stamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
