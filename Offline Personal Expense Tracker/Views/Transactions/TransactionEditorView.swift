import CoreTransferable
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum TransactionEditorMode {
    case create(TransactionType)
    case edit(LedgerTransaction)
}

struct TransactionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var mode: TransactionEditorMode

    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var transactions: [LedgerTransaction]
    @Query private var settingsRows: [AppSettings]

    @State private var draft: TransactionDraft
    @State private var messages: [String] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var attachmentData: Data?
    @State private var attachmentExtension: String?
    @State private var removeAttachment = false
    @State private var showFileImporter = false
    @FocusState private var amountFocused: Bool

    init(mode: TransactionEditorMode) {
        self.mode = mode
        switch mode {
        case .create(let type):
            var draft = TransactionDraft()
            draft.type = type
            _draft = State(initialValue: draft)
        case .edit(let transaction):
            _draft = State(initialValue: TransactionDraft(transaction))
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $draft.type) {
                    ForEach(TransactionType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isEditing)
                TextField("Amount", text: $draft.amountText)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .accessibilityLabel("Amount")
                TextField("Title", text: $draft.title)
            }
            Section {
                if draft.type != .transfer {
                    Picker("Category", selection: $draft.categoryID) {
                        Text("Choose").tag(Optional<UUID>.none)
                        ForEach(matchingCategories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                }
                Picker("Wallet", selection: $draft.walletID) {
                    Text("Choose").tag(Optional<UUID>.none)
                    ForEach(activeWallets) { wallet in
                        Text("\(wallet.name) · \(wallet.currencyCode)").tag(Optional(wallet.id))
                    }
                }
                if draft.type == .transfer {
                    Picker("To wallet", selection: $draft.destinationWalletID) {
                        Text("Choose").tag(Optional<UUID>.none)
                        ForEach(activeWallets) { wallet in
                            Text("\(wallet.name) · \(wallet.currencyCode)").tag(Optional(wallet.id))
                        }
                    }
                }
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
            }
            Section("Details") {
                TextField("Merchant or recipient", text: $draft.merchant)
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Tags, separated by commas", text: $draft.tagsText)
                Picker("Payment method", selection: $draft.paymentMethod) {
                    Text("None").tag(Optional<PaymentMethod>.none)
                    ForEach(PaymentMethod.allCases) { method in
                        Text(method.title).tag(Optional(method))
                    }
                }
            }
            if !isEditing {
                Section("Repeat") {
                    Toggle("Repeat this transaction", isOn: $draft.makeRecurring)
                    if draft.makeRecurring {
                        Picker("Frequency", selection: $draft.frequency) {
                            ForEach(RecurrenceFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency)
                            }
                        }
                        Toggle("End date", isOn: $draft.recurrenceEnds)
                        if draft.recurrenceEnds {
                            DatePicker("Last date", selection: $draft.recurrenceEnd, displayedComponents: .date)
                        }
                    }
                }
            } else if case .edit(let transaction) = mode, transaction.recurringRule != nil {
                Section {
                    Text("This is one occurrence. Saving changes this entry only and does not change the schedule.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Attachment") {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose photo", systemImage: "photo")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("Choose file", systemImage: "doc")
                }
                if attachmentData != nil {
                    Text("A new attachment will be saved on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Remove selected attachment", role: .destructive) {
                        attachmentData = nil
                        attachmentExtension = nil
                    }
                } else if case .edit(let transaction) = mode, transaction.attachmentFileName != nil, !removeAttachment {
                    Text("An attachment is already stored on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Remove attachment", role: .destructive) {
                        removeAttachment = true
                    }
                }
            }
            if !messages.isEmpty {
                Section {
                    ForEach(messages, id: \.self) { message in
                        Text(message)
                            .foregroundStyle(Theme.expense)
                            .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle(isEditing ? "Edit transaction" : draft.type.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
            }
        }
        .onAppear {
            if draft.walletID == nil {
                draft.walletID = activeWallets.first?.id
            }
        }
        .onChange(of: draft.type) { _, _ in
            if let category = categories.first(where: { $0.id == draft.categoryID }),
               (draft.type == .income && category.kind != .income) || (draft.type == .expense && category.kind != .expense) {
                draft.categoryID = nil
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let picked = try? await item.loadTransferable(type: PickedPhoto.self) {
                    attachmentData = picked.data
                    attachmentExtension = "jpg"
                } else {
                    messages = ["That photo could not be read on this device."]
                }
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .pdf]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    attachmentData = data
                    attachmentExtension = url.pathExtension.isEmpty ? "bin" : url.pathExtension
                    removeAttachment = false
                } else {
                    messages = ["That file could not be read."]
                }
            case .failure:
                messages = ["That file could not be read."]
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var activeWallets: [Wallet] { wallets.filter { !$0.isArchived } }

    private var matchingCategories: [Category] {
        let kind: CategoryKind = draft.type == .income ? .income : .expense
        return categories.filter { $0.kind == kind && !$0.isArchived }
    }

    private func save() {
        let financeWallets = wallets.map { $0.financeValue() }
        let validation = ValidationService.parseTransaction(draft, wallets: financeWallets)
        guard let parsed = validation.parsed else {
            messages = validation.messages
            return
        }
        if parsed.type == .transfer, let source = wallets.first(where: { $0.id == parsed.walletID }) {
                let editingID = currentTransaction?.id
                let history = transactions
                    .filter { $0.id != editingID }
                    .map { $0.financeValue() }
                let balance = LedgerCalculator.balance(
                    of: source.financeValue(),
                    wallets: financeWallets,
                    transactions: history
                )
                if let message = ValidationService.transferFundsMessage(
                    source: source.financeValue(),
                    sourceBalance: balance,
                    amount: parsed.amount
                ) {
                    messages = [message]
                    return
                }
            }
            do {
                try write(parsed)
                try RecurringService.generateDue(in: modelContext, calendar: calendar)
                try modelContext.save()
                Task { await BudgetNotificationService.sync(context: modelContext) }
                dismiss()
            } catch let error as AttachmentError {
                messages = [error.message]
            } catch {
                messages = ["The transaction could not be saved."]
                AppLog.persistence("Transaction save failed.")
            }
    }

    private func write(_ parsed: ParsedTransaction) throws {
        let transaction: LedgerTransaction
        switch mode {
        case .create:
            transaction = LedgerTransaction(
                type: parsed.type,
                amount: parsed.amount,
                currencyCode: currencyCode(for: parsed.walletID),
                title: parsed.title,
                notes: parsed.notes,
                date: parsed.date,
                tags: parsed.tags,
                paymentMethod: parsed.paymentMethod,
                merchant: parsed.merchant
            )
            modelContext.insert(transaction)
        case .edit(let existing):
            transaction = existing
            transaction.transactionType = parsed.type
            transaction.amount = parsed.amount
            transaction.currencyCode = currencyCode(for: parsed.walletID)
            transaction.title = parsed.title
            transaction.notes = parsed.notes
            transaction.date = parsed.date
            transaction.tags = parsed.tags
            transaction.paymentMethod = parsed.paymentMethod
            transaction.merchant = parsed.merchant
            transaction.updatedAt = Date()
        }
        transaction.wallet = wallets.first { $0.id == parsed.walletID }
        transaction.destinationWallet = wallets.first { $0.id == parsed.destinationWalletID }
        transaction.category = parsed.type == .transfer ? nil : categories.first { $0.id == parsed.categoryID }

        if removeAttachment {
            AttachmentStore.delete(fileName: transaction.attachmentFileName)
            transaction.attachmentFileName = nil
        }
        if let attachmentData {
            if attachmentData.count > AttachmentStore.maximumBytes {
                throw AttachmentError.tooLarge
            }
            AttachmentStore.delete(fileName: transaction.attachmentFileName)
            transaction.attachmentFileName = try AttachmentStore.save(
                data: attachmentData,
                fileExtension: attachmentExtension ?? "bin"
            )
        }

        if case .create = mode, parsed.makeRecurring, let wallet = transaction.wallet {
            let rule = RecurringRule(
                frequency: parsed.frequency,
                startDate: parsed.date,
                endDate: parsed.recurrenceEnd,
                templateTitle: parsed.title,
                templateAmount: parsed.amount,
                templateType: parsed.type,
                templateNotes: parsed.notes,
                templateTags: parsed.tags,
                templateMerchant: parsed.merchant,
                templatePaymentMethod: parsed.paymentMethod,
                currencyCode: wallet.currencyCode
            )
            rule.category = transaction.category
            rule.wallet = wallet
            rule.destinationWallet = transaction.destinationWallet
            let key = RecurringScheduler.occurrenceKey(ruleID: rule.id, date: parsed.date, calendar: calendar)
            rule.emittedOccurrenceKeys = [key]
            transaction.occurrenceKey = key
            transaction.recurringRule = rule
            modelContext.insert(rule)
        }
        try modelContext.save()
    }

    private var currentTransaction: LedgerTransaction? {
        if case .edit(let transaction) = mode { return transaction }
        return nil
    }

    private var calendar: Calendar {
        ReportingPeriod.calendar(firstWeekday: settingsRows.first?.firstWeekday ?? 1)
    }

    private func currencyCode(for walletID: UUID) -> String {
        wallets.first { $0.id == walletID }?.currencyCode ?? settingsRows.first?.baseCurrencyCode ?? "USD"
    }
}

private struct PickedPhoto: Transferable {
    var data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedPhoto(data: data)
        }
    }
}

private extension TransactionDraft {
    init(_ transaction: LedgerTransaction) {
        type = transaction.transactionType
        amountText = Money.exportString(transaction.amount)
        title = transaction.title
        notes = transaction.notes
        categoryID = transaction.category?.id
        walletID = transaction.wallet?.id
        destinationWalletID = transaction.destinationWallet?.id
        date = transaction.date
        tagsText = transaction.tags.joined(separator: ", ")
        paymentMethod = transaction.paymentMethod
        merchant = transaction.merchant
        makeRecurring = false
        frequency = .monthly
        recurrenceEnds = false
        recurrenceEnd = transaction.date
    }
}
