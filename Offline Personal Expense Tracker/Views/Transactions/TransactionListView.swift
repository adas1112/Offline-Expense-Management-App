import SwiftData
import SwiftUI

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    @Query private var settingsRows: [AppSettings]
    @State private var model = TransactionListViewModel()
    @State private var showFilters = false
    @State private var pendingDelete: LedgerTransaction?

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    EmptyStateView(
                        title: "No transactions",
                        message: "Income, expenses, and transfers you add are saved on this device.",
                        systemImage: "list.bullet",
                        actionTitle: wallets.isEmpty ? nil : "Add transaction",
                        action: wallets.isEmpty ? nil : { router.createType = .expense }
                    )
                } else if visible.isEmpty {
                    EmptyStateView(
                        title: "Nothing matches",
                        message: "Try a different search or clear the filters.",
                        systemImage: "line.3.horizontal.decrease.circle",
                        actionTitle: "Clear filters",
                        action: resetFilters
                    )
                } else {
                    List {
                        ForEach(sections, id: \.title) { section in
                            Section(section.title) {
                                ForEach(section.rows) { transaction in
                                    NavigationLink {
                                        TransactionDetailView(transaction: transaction)
                                    } label: {
                                        TransactionRow(transaction: transaction, currencyDisplay: signed(transaction))
                                    }
                                    .swipeActions {
                                        Button("Delete", role: .destructive) {
                                            pendingDelete = transaction
                                        }
                                    }
                                }
                            }
                        }
                        if visible.count > model.pageSize {
                            Button("Load more") { model.pageSize += 40 }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $model.filter.query, prompt: "Title, merchant, notes, or tags")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter transactions")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.createType = .expense
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add transaction")
                    .disabled(wallets.filter { !$0.isArchived }.isEmpty)
                }
            }
            .sheet(isPresented: $showFilters) {
                TransactionFilterSheet(model: model, categories: categories, wallets: wallets)
            }
            .confirmationDialog(
                "Delete this transaction?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDelete {
                        delete(pendingDelete)
                    }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("The transaction will be removed from this device.")
            }
        }
    }

    private var calendar: Calendar {
        ReportingPeriod.calendar(firstWeekday: settingsRows.first?.firstWeekday ?? 1)
    }

    private var ordered: [LedgerTransaction] {
        model.visible(transactions, calendar: calendar)
    }

    private var visible: [LedgerTransaction] {
        Array(ordered.prefix(model.pageSize))
    }

    private var sections: [TransactionSection] {
        let format = settingsRows.first?.dateFormat ?? .medium
        var sections: [TransactionSection] = []
        for transaction in visible {
            let title: String
            if model.filter.sort == .dateNewest || model.filter.sort == .dateOldest {
                title = DisplayFormat.dateString(transaction.date, preference: format, calendar: calendar)
            } else {
                title = "Results"
            }
            if let index = sections.firstIndex(where: { $0.title == title }) {
                sections[index].rows.append(transaction)
            } else {
                sections.append(TransactionSection(title: title, rows: [transaction]))
            }
        }
        return sections
    }

    private func signed(_ transaction: LedgerTransaction) -> String {
        let direction: MoneyDirection
        switch transaction.transactionType {
        case .income: direction = .income
        case .expense: direction = .expense
        case .transfer: direction = .transfer
        }
        return DisplayFormat.money(transaction.amount, currencyCode: transaction.currencyCode, direction: direction)
    }

    private func resetFilters() {
        model.filter = .empty
        model.useDateFilter = false
        model.pageSize = 40
    }

    private func delete(_ transaction: LedgerTransaction) {
        AttachmentStore.delete(fileName: transaction.attachmentFileName)
        modelContext.delete(transaction)
        do {
            try modelContext.save()
        } catch {
            AppLog.persistence("Could not delete a transaction.")
        }
        pendingDelete = nil
        Task { await BudgetNotificationService.sync(context: modelContext) }
    }
}

private struct TransactionSection {
    var title: String
    var rows: [LedgerTransaction]
}

private struct TransactionFilterSheet: View {
    @Bindable var model: TransactionListViewModel
    var categories: [Category]
    var wallets: [Wallet]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Sort", selection: $model.filter.sort) {
                    ForEach(TransactionSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                Picker("Type", selection: $model.filter.type) {
                    Text("All").tag(Optional<TransactionType>.none)
                    ForEach(TransactionType.allCases) { type in
                        Text(type.title).tag(Optional(type))
                    }
                }
                Picker("Category", selection: $model.filter.categoryID) {
                    Text("All").tag(Optional<UUID>.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                Picker("Wallet", selection: $model.filter.walletID) {
                    Text("All").tag(Optional<UUID>.none)
                    ForEach(wallets) { wallet in
                        Text(wallet.name).tag(Optional(wallet.id))
                    }
                }
                Toggle("Date range", isOn: $model.useDateFilter)
                if model.useDateFilter {
                    DatePicker("From", selection: $model.rangeStart, displayedComponents: .date)
                    DatePicker("To", selection: $model.rangeEnd, displayedComponents: .date)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        model.filter = .empty
                        model.useDateFilter = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
