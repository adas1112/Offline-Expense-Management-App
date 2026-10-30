import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [AppSettings]
    @Query private var transactions: [LedgerTransaction]
    @Query private var wallets: [Wallet]
    @Query private var categories: [Category]
    @Query private var budgets: [Budget]
    @State private var lockOn = false
    @State private var authMessage: String?
    @State private var exportFile: ExportedFile?
    @State private var statusMessage: String?
    @State private var showImporter = false
    @State private var pendingRestore: BackupDocument?
    @State private var confirmErase = false
    @State private var confirmEraseFinal = false
    @State private var confirmDemo = false
    @State private var confirmRemoveDemo = false

    var body: some View {
        NavigationStack {
            Form {
                if let settings = settingsRows.first {
                    preferences(settings)
                    security(settings)
                    notifications(settings)
                    data(settings)
                }
                Section {
                    NavigationLink("Repeating transactions") { RecurringRulesView() }
                    NavigationLink("Wallets") { WalletListView() }
                    NavigationLink("About") { AboutView() }
                    NavigationLink("Privacy") { PrivacyView() }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                lockOn = KeychainStore.isAppLockEnabled() || (settingsRows.first?.biometricLockEnabled ?? false)
            }
            .sheet(item: $exportFile) { ExportPreviewSheet(file: $0) }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    loadBackup(url)
                case .failure:
                    statusMessage = "The backup file could not be opened."
                }
            }
            .confirmationDialog("Replace all data with this backup?", isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ), titleVisibility: .visible) {
                Button("Replace existing data", role: .destructive) { restore() }
                Button("Cancel", role: .cancel) { pendingRestore = nil }
            } message: {
                Text("Wallets, transactions, budgets, categories, repeating rules, and settings on this device will be replaced. This does not merge with what is already here.")
            }
            .confirmationDialog("Load example data?", isPresented: $confirmDemo, titleVisibility: .visible) {
                Button("Load example data") { installDemo() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Example wallets and transactions are marked as demo data and can be removed later.")
            }
            .confirmationDialog("Remove example data?", isPresented: $confirmRemoveDemo, titleVisibility: .visible) {
                Button("Remove example data", role: .destructive) { removeDemo() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only records created as example data are removed. Records you added are kept.")
            }
            .confirmationDialog("Delete all application data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Continue", role: .destructive) { confirmEraseFinal = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes wallets, transactions, budgets, and settings stored on this device.")
            }
            .alert("Delete everything stored in this app?", isPresented: $confirmEraseFinal) {
                Button("Delete all data", role: .destructive) { erase() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Make a backup first if you want to keep this ledger. Deleting the app later can also remove data that was not backed up.")
            }
            .alert("Settings", isPresented: Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func preferences(_ settings: AppSettings) -> some View {
        Section("Preferences") {
            Picker("Base currency", selection: Binding(
                get: { settings.baseCurrencyCode },
                set: { settings.baseCurrencyCode = $0; save() }
            )) {
                ForEach(DisplayFormat.currencyCodes, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            Text("Consolidated totals use this currency only. Amounts in other currencies are not converted, because this app does not download exchange rates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Date format", selection: Binding(
                get: { settings.dateFormat },
                set: { settings.dateFormat = $0; save() }
            )) {
                ForEach(DateFormatPreference.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            Picker("First day of the week", selection: Binding(
                get: { settings.firstWeekday },
                set: { settings.firstWeekday = $0; save() }
            )) {
                ForEach(1...7, id: \.self) { day in
                    Text(weekdayName(day)).tag(day)
                }
            }
            Picker("Appearance", selection: Binding(
                get: { settings.appearance },
                set: { settings.appearance = $0; save() }
            )) {
                ForEach(AppearancePreference.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
        }
    }

    @ViewBuilder
    private func security(_ settings: AppSettings) -> some View {
        Section("Security") {
            Toggle("App lock", isOn: Binding(
                get: { lockOn },
                set: { newValue in Task { await setLock(newValue, settings: settings) } }
            ))
            Text("Uses \(BiometricAuthService.availability().title), with the device passcode as a fallback. A PIN is not stored in the app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let authMessage {
                Text(authMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.expense)
            }
        }
    }

    @ViewBuilder
    private func notifications(_ settings: AppSettings) -> some View {
        Section("Budget reminders") {
            Toggle("Local budget notifications", isOn: Binding(
                get: { settings.budgetNotificationsEnabled },
                set: { enabled in
                    settings.budgetNotificationsEnabled = enabled
                    save()
                    Task {
                        if enabled {
                            let granted = await BudgetNotificationService.requestAuthorization()
                            if !granted {
                                statusMessage = "Notifications are off for this app. You can allow them in iOS Settings."
                            }
                        }
                        await BudgetNotificationService.sync(context: modelContext)
                    }
                }
            ))
            Text("Warnings stay on this device. The app does not send budget data to a server.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func data(_ settings: AppSettings) -> some View {
        Section("Your data") {
            Button("Export transactions (CSV)") { exportCSV() }
            Button("Export this year’s report (PDF)") { exportPDF() }
            Button("Back up data") { backup() }
            Button("Restore from backup") { showImporter = true }
            if settings.demoDataInstalled {
                Button("Remove example data", role: .destructive) { confirmRemoveDemo = true }
            } else {
                Button("Load example data") { confirmDemo = true }
            }
            Button("Delete all application data", role: .destructive) { confirmErase = true }
        }
    }

    private func weekdayName(_ day: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        let symbols = calendar.weekdaySymbols
        let index = day - 1
        guard symbols.indices.contains(index) else { return "Day \(day)" }
        return symbols[index]
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            statusMessage = "The setting could not be saved."
        }
    }

    private func setLock(_ enabled: Bool, settings: AppSettings) async {
        let availability = BiometricAuthService.availability()
        guard availability.available else {
            lockOn = false
            authMessage = availability.message
            return
        }
        let reason = enabled ? "Turn on app lock" : "Turn off app lock"
        let result = await BiometricAuthService.authenticate(reason: reason)
        switch result {
        case .success:
            settings.biometricLockEnabled = enabled
            KeychainStore.setAppLockEnabled(enabled)
            lockOn = enabled
            authMessage = nil
            save()
        case .failure(.canceled):
            lockOn = settings.biometricLockEnabled
            authMessage = "Authentication was canceled."
        case .failure(.unavailable(let text)), .failure(.failed(let text)):
            lockOn = settings.biometricLockEnabled
            authMessage = text
        }
    }

    private func exportCSV() {
        let calendar = ReportingPeriod.calendar(firstWeekday: settingsRows.first?.firstWeekday ?? 1)
        let data = CSVExporter.data(
            transactions: transactions.map { $0.financeValue() }.sorted { $0.date > $1.date },
            categories: categories.map { $0.financeValue() },
            wallets: wallets.map { $0.financeValue() },
            calendar: calendar
        )
        publish(data: data, name: "Transactions-\(stamp).csv", folder: "Exports", showsPDF: false)
    }

    private func exportPDF() {
        let calendar = ReportingPeriod.calendar(firstWeekday: settingsRows.first?.firstWeekday ?? 1)
        let currency = settingsRows.first?.baseCurrencyCode ?? "USD"
        let window = ReportingPeriod.window(for: .thisYear, customStart: Date(), customEnd: Date(), calendar: calendar)
        let report = ReportBuilder.make(
            transactions: transactions.map { $0.financeValue() },
            wallets: wallets.map { $0.financeValue() },
            categories: categories.map { $0.financeValue() },
            budgets: budgets.map { $0.financeValue() },
            window: window,
            calendar: calendar,
            baseCurrency: currency,
            granularity: .month
        )
        let rows = transactions.map { $0.financeValue() }.filter { window.contains($0.date) && $0.currencyCode == currency }
        let data = PDFExporter.make(PDFReportRequest(
            title: "Finance report",
            periodLabel: ReportingPeriod.label(for: window, calendar: calendar, style: settingsRows.first?.dateFormat ?? .medium),
            generatedAt: Date(),
            report: report,
            transactions: rows,
            categories: categories.map { $0.financeValue() },
            wallets: wallets.map { $0.financeValue() },
            calendar: calendar
        ))
        publish(data: data, name: "FinanceReport-\(stamp).pdf", folder: "Exports", showsPDF: true)
    }

    private func backup() {
        do {
            let document = try BackupApplier.makeDocument(context: modelContext)
            let data = try BackupCodec.encode(document)
            publish(data: data, name: "FinanceBackup-\(stamp).json", folder: "Backups", showsPDF: false)
        } catch {
            statusMessage = "The backup could not be created."
        }
    }

    private func publish(data: Data, name: String, folder: String, showsPDF: Bool) {
        do {
            let url = try ExportFiles.write(data: data, name: name, folder: folder)
            exportFile = ExportedFile(url: url, showsPDF: showsPDF)
        } catch {
            statusMessage = "The file could not be saved on this device."
        }
    }

    private func loadBackup(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            statusMessage = BackupError.unreadable.description
            return
        }
        do {
            pendingRestore = try BackupCodec.decode(data)
        } catch let error as BackupError {
            statusMessage = error.description
        } catch {
            statusMessage = BackupError.unreadable.description
        }
    }

    private func restore() {
        guard let document = pendingRestore else { return }
        do {
            try BackupApplier.replaceAll(with: document, in: modelContext)
            pendingRestore = nil
            statusMessage = "Backup restored on this device."
        } catch let error as BackupError {
            modelContext.rollback()
            pendingRestore = nil
            statusMessage = error.description
        } catch {
            modelContext.rollback()
            pendingRestore = nil
            statusMessage = "The backup could not be restored."
        }
    }

    private func installDemo() {
        do {
            try DemoDataService.install(in: modelContext)
            statusMessage = "Example data was added. You can remove it from Settings."
        } catch {
            statusMessage = "Example data could not be added."
        }
    }

    private func removeDemo() {
        do {
            try DemoDataService.remove(in: modelContext)
            statusMessage = "Example data was removed."
        } catch {
            statusMessage = "Example data could not be removed."
        }
    }

    private func erase() {
        do {
            try DataEraseService.eraseAll(in: modelContext)
            lockOn = false
            statusMessage = "All application data was deleted from this device."
        } catch {
            statusMessage = "The data could not be deleted."
        }
    }

    private var stamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

struct RecurringRulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecurringRule.startDate, order: .reverse) private var rules: [RecurringRule]
    @State private var pendingDelete: RecurringRule?

    var body: some View {
        List {
            if rules.isEmpty {
                Text("When you save a transaction with Repeat turned on, its schedule appears here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rules) { rule in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.templateTitle).font(.body.weight(.semibold))
                        Text("\(rule.frequency.title) · \(DisplayFormat.money(rule.templateAmount, currencyCode: rule.currencyCode))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(rule.isPaused ? "Paused" : "Active")
                            .font(.caption)
                            .foregroundStyle(rule.isPaused ? .orange : Theme.income)
                    }
                    .swipeActions {
                        Button(rule.isPaused ? "Resume" : "Pause") {
                            if rule.isPaused {
                                RecurringService.resume(rule)
                                try? RecurringService.generateDue(in: modelContext)
                            } else {
                                RecurringService.pause(rule)
                            }
                            try? modelContext.save()
                        }
                        .tint(.orange)
                        Button("Delete", role: .destructive) { pendingDelete = rule }
                    }
                }
            }
        }
        .navigationTitle("Repeating")
        .confirmationDialog("Delete this schedule?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete schedule", role: .destructive) {
                if let pendingDelete {
                    modelContext.delete(pendingDelete)
                    try? modelContext.save()
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Transactions already recorded stay in the ledger. Future ones will not be created.")
        }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
            }
            Section {
                Text("Offline Personal Expense Tracker is a private ledger for one device. It records wallets, transactions, budgets, and reports without an account or a network connection.")
            }
        }
        .navigationTitle("About")
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On this device") {
                Text("Transactions, wallets, budgets, categories, attachments, and settings are stored in the app’s local database and files. The app does not have an account, does not sync to a server, and does not include ads or remote analytics.")
            }
            Section("Protection") {
                Text("iOS protects the app’s files with the device’s data protection. The optional app lock uses Face ID, Touch ID, or the device passcode through the system. The app does not store a PIN. This is not a claim of end-to-end encryption.")
            }
            Section("Backups") {
                Text("A backup file contains your financial records. If you share that file, you are choosing where it goes. Deleting the app can remove data that has not been backed up.")
            }
            Section("Notifications") {
                Text("Budget reminders are local notifications. They are created on the device and do not require an internet connection.")
            }
        }
        .navigationTitle("Privacy")
    }
}
