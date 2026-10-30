import SwiftData
import SwiftUI

struct BudgetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Budget.createdAt, order: .reverse) private var budgets: [Budget]
    @Query private var transactions: [LedgerTransaction]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var settingsRows: [AppSettings]
    @State private var showEditor = false
    @State private var editing: Budget?

    var body: some View {
        NavigationStack {
            Group {
                if budgets.isEmpty {
                    EmptyStateView(
                        title: "No budgets",
                        message: "Set a spending limit for the month or for one category. Income and transfers are not counted.",
                        systemImage: "chart.pie",
                        actionTitle: "Add budget",
                        action: { editing = nil; showEditor = true }
                    )
                } else {
                    List {
                        budgetSection("Active", rows: budgets.filter { !$0.isArchived && !$0.isPaused })
                        budgetSection("Paused", rows: budgets.filter { $0.isPaused && !$0.isArchived })
                        budgetSection("Archived", rows: budgets.filter(\.isArchived))
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Budgets")
            .toolbar {
                Button {
                    editing = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add budget")
            }
            .sheet(isPresented: $showEditor) {
                NavigationStack {
                    BudgetEditorView(budget: editing)
                }
            }
        }
    }

    @ViewBuilder
    private func budgetSection(_ title: String, rows: [Budget]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { budget in
                    Button {
                        editing = budget
                        showEditor = true
                    } label: {
                        BudgetProgress(line: line(for: budget), currencyCode: budget.currencyCode)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if !budget.isArchived {
                            Button(budget.isPaused ? "Resume" : "Pause") {
                                budget.isPaused.toggle()
                                try? modelContext.save()
                            }
                            .tint(.orange)
                        }
                        Button("Archive", role: .destructive) {
                            budget.isArchived = true
                            budget.isPaused = true
                            try? modelContext.save()
                        }
                    }
                }
            }
        }
    }

    private func line(for budget: Budget) -> BudgetLine {
        BudgetCalculator.line(
            for: budget.financeValue(),
            transactions: transactions.map { $0.financeValue() },
            categoryName: budget.category?.name
        )
    }
}

struct BudgetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var settingsRows: [AppSettings]
    var budget: Budget?

    @State private var draft = BudgetDraft()
    @State private var messages: [String] = []
    @State private var isPaused = false
    @State private var isArchived = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                TextField("Amount", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                Picker("Applies to", selection: $draft.isOverall) {
                    Text("All spending").tag(true)
                    Text("One category").tag(false)
                }
                if !draft.isOverall {
                    Picker("Category", selection: $draft.categoryID) {
                        Text("Choose").tag(Optional<UUID>.none)
                        ForEach(categories.filter { $0.kind == .expense && !$0.isArchived }) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                }
                DatePicker("Starts", selection: $draft.startDate, displayedComponents: .date)
                DatePicker("Ends", selection: $draft.endDate, displayedComponents: .date)
            }
            Section {
                VStack(alignment: .leading) {
                    Text("Warn at \(Int(draft.warningThreshold * 100))%")
                    Slider(value: $draft.warningThreshold, in: 0.5...1, step: 0.05)
                }
                Toggle("Notify at warning", isOn: $draft.notifyAtWarning)
                Toggle("Notify when reached", isOn: $draft.notifyAtExceeded)
                Text("Notifications are scheduled on this device and do not use the internet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if budget != nil {
                Section {
                    Toggle("Paused", isOn: $isPaused)
                    Toggle("Archived", isOn: $isArchived)
                }
            }
            if !messages.isEmpty {
                Section {
                    ForEach(messages, id: \.self) { message in
                        Text(message).font(.footnote).foregroundStyle(Theme.expense)
                    }
                }
            }
        }
        .navigationTitle(budget == nil ? "New budget" : "Edit budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear(perform: load)
    }

    private var currency: String { settingsRows.first?.baseCurrencyCode ?? "USD" }

    private func load() {
        let calendar = Calendar.current
        let month = ReportingPeriod.monthWindow(containing: Date(), calendar: calendar)
        draft.startDate = month.start
        draft.endDate = calendar.date(byAdding: .day, value: -1, to: month.endExclusive) ?? Date()
        draft.warningThreshold = settingsRows.first?.warningThreshold ?? 0.8
        guard let budget else { return }
        draft = BudgetDraft(
            name: budget.name,
            amountText: Money.exportString(budget.amount),
            isOverall: budget.isOverall,
            categoryID: budget.category?.id,
            startDate: budget.startDate,
            endDate: budget.endDate,
            warningThreshold: budget.warningThreshold,
            notifyAtWarning: budget.notifyAtWarning,
            notifyAtExceeded: budget.notifyAtExceeded
        )
        isPaused = budget.isPaused
        isArchived = budget.isArchived
    }

    private func save() {
        let errors = ValidationService.budgetMessages(draft, currencyCode: currency)
        guard errors.isEmpty, let amount = AmountParser.parse(draft.amountText, currencyCode: currency) else {
            messages = errors
            return
        }
        let target: Budget
        if let budget {
            target = budget
        } else {
            target = Budget(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount,
                currencyCode: currency,
                startDate: draft.startDate,
                endDate: draft.endDate,
                warningThreshold: draft.warningThreshold,
                isOverall: draft.isOverall
            )
            modelContext.insert(target)
        }
        target.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.amount = amount
        target.currencyCode = currency
        target.startDate = draft.startDate
        target.endDate = draft.endDate
        target.warningThreshold = draft.warningThreshold
        target.isOverall = draft.isOverall
        target.category = draft.isOverall ? nil : categories.first { $0.id == draft.categoryID }
        target.notifyAtWarning = draft.notifyAtWarning
        target.notifyAtExceeded = draft.notifyAtExceeded
        target.isPaused = isPaused
        target.isArchived = isArchived
        if draft.notifyAtWarning || draft.notifyAtExceeded, let settings = settingsRows.first {
            settings.budgetNotificationsEnabled = true
        }
        do {
            try modelContext.save()
            Task {
                if draft.notifyAtWarning || draft.notifyAtExceeded {
                    _ = await BudgetNotificationService.requestAuthorization()
                }
                await BudgetNotificationService.sync(context: modelContext)
            }
            dismiss()
        } catch {
            messages = ["The budget could not be saved."]
        }
    }
}
