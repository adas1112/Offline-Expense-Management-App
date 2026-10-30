import SwiftData
import SwiftUI

struct WalletListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Wallet.createdAt) private var wallets: [Wallet]
    @Query private var transactions: [LedgerTransaction]
    @State private var showEditor = false
    @State private var editing: Wallet?

    var body: some View {
        List {
            if wallets.isEmpty {
                EmptyStateView(
                    title: "No wallets",
                    message: "Add cash, a bank account, savings, or a credit card to track.",
                    systemImage: "wallet.pass",
                    actionTitle: "Add wallet",
                    action: { showEditor = true }
                )
            } else {
                Section("Active") {
                    ForEach(wallets.filter { !$0.isArchived }) { wallet in
                        NavigationLink {
                            WalletDetailView(wallet: wallet)
                        } label: {
                            WalletSummaryRow(wallet: wallet, transactions: transactions, wallets: wallets)
                        }
                    }
                }
                let archived = wallets.filter(\.isArchived)
                if !archived.isEmpty {
                    Section("Archived") {
                        ForEach(archived) { wallet in
                            NavigationLink {
                                WalletDetailView(wallet: wallet)
                            } label: {
                                WalletSummaryRow(wallet: wallet, transactions: transactions, wallets: wallets)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Wallets")
        .toolbar {
            Button {
                editing = nil
                showEditor = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add wallet")
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                WalletEditorView(wallet: editing)
            }
        }
    }
}

struct WalletDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [LedgerTransaction]
    @Query private var wallets: [Wallet]
    @Query private var settingsRows: [AppSettings]
    var wallet: Wallet
    @State private var showEditor = false
    @State private var confirmArchive = false
    @State private var confirmDelete = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(wallet.walletType.isLiability ? "Amount owed" : "Current balance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(DisplayFormat.money(balance, currencyCode: wallet.currencyCode))
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                    Text(wallet.walletType.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                LabeledContent("Currency", value: wallet.currencyCode)
                LabeledContent("Opening", value: DisplayFormat.money(wallet.openingBalance, currencyCode: wallet.currencyCode))
                if wallet.isArchived {
                    Text("Archived wallets stay in your history and are hidden from new transactions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if wallet.currencyCode != (settingsRows.first?.baseCurrencyCode ?? wallet.currencyCode) {
                    Text("This wallet is excluded from consolidated totals because its currency differs from the base currency.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Activity") {
                if history.isEmpty {
                    Text("No transactions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            TransactionRow(transaction: transaction, currencyDisplay: signed(transaction))
                        }
                    }
                }
            }
            Section {
                Button("Edit wallet") { showEditor = true }
                Button(wallet.isArchived ? "Unarchive" : "Archive") {
                    confirmArchive = true
                }
                if history.isEmpty {
                    Button("Delete wallet", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(wallet.name)
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                WalletEditorView(wallet: wallet)
            }
        }
        .confirmationDialog(
            wallet.isArchived ? "Restore this wallet to active use?" : "Archive this wallet?",
            isPresented: $confirmArchive,
            titleVisibility: .visible
        ) {
            Button(wallet.isArchived ? "Unarchive" : "Archive") {
                wallet.isArchived.toggle()
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Existing transactions stay in the ledger.")
        }
        .confirmationDialog("Delete this wallet?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(wallet)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Wallet", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var balance: Decimal {
        LedgerCalculator.balance(
            of: wallet.financeValue(),
            wallets: wallets.map { $0.financeValue() },
            transactions: transactions.map { $0.financeValue() }
        )
    }

    private var history: [LedgerTransaction] {
        transactions
            .filter { $0.wallet?.id == wallet.id || $0.destinationWallet?.id == wallet.id }
            .sorted { $0.date > $1.date }
    }

    private func signed(_ transaction: LedgerTransaction) -> String {
        DisplayFormat.money(
            transaction.amount,
            currencyCode: transaction.currencyCode,
            direction: transaction.transactionType == .expense ? .expense : (transaction.transactionType == .income ? .income : .transfer)
        )
    }
}

private struct WalletSummaryRow: View {
    var wallet: Wallet
    var transactions: [LedgerTransaction]
    var wallets: [Wallet]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: wallet.iconName)
                .frame(width: 32, height: 32)
                .background(Color(hex: wallet.colorHex).opacity(0.15), in: Circle())
                .foregroundStyle(Color(hex: wallet.colorHex))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.name)
                Text(wallet.walletType.isLiability ? "Owed" : wallet.walletType.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DisplayFormat.money(balance, currencyCode: wallet.currencyCode))
                .font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private var balance: Decimal {
        LedgerCalculator.balance(
            of: wallet.financeValue(),
            wallets: wallets.map { $0.financeValue() },
            transactions: transactions.map { $0.financeValue() }
        )
    }
}

struct WalletEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    @Query private var settingsRows: [AppSettings]
    var wallet: Wallet?

    @State private var draft = WalletDraft()
    @State private var messages: [String] = []
    @State private var currencyLocked = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                Picker("Type", selection: $draft.type) {
                    ForEach(WalletType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                if currencyLocked {
                    LabeledContent("Currency", value: draft.currencyCode)
                } else {
                    Picker("Currency", selection: $draft.currencyCode) {
                        ForEach(DisplayFormat.currencyCodes, id: \.self) { code in
                            Text("\(code) · \(DisplayFormat.currencyName(for: code))").tag(code)
                        }
                    }
                }
                TextField(draft.type.isLiability ? "Amount owed" : "Opening balance", text: $draft.openingBalanceText)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                Text(draft.type.isLiability
                     ? "Enter what you already owe as a positive amount. Purchases increase it. Payments reduce it."
                     : "This is money already in the wallet before the transactions you record.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Appearance") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                    ForEach(Theme.icons, id: \.self) { icon in
                        Button {
                            draft.iconName = icon
                        } label: {
                            Image(systemName: icon)
                                .frame(width: 36, height: 36)
                                .background(draft.iconName == icon ? Color.accentColor.opacity(0.18) : Color.clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon)
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Theme.swatches, id: \.self) { hex in
                        Button {
                            draft.colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if draft.colorHex == hex {
                                        Circle().stroke(Color.primary, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(hex)")
                    }
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
        .navigationTitle(wallet == nil ? "New wallet" : "Edit wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let wallet else {
            draft.currencyCode = settingsRows.first?.baseCurrencyCode ?? Locale.current.currency?.identifier ?? "USD"
            draft.iconName = draft.type.systemImage
            return
        }
        draft = WalletDraft(
            name: wallet.name,
            type: wallet.walletType,
            currencyCode: wallet.currencyCode,
            openingBalanceText: Money.exportString(wallet.openingBalance),
            iconName: wallet.iconName,
            colorHex: wallet.colorHex
        )
        let used = wallet.transactions.isEmpty == false || wallet.incomingTransfers.isEmpty == false
        currencyLocked = used
    }

    private func save() {
        let names = wallets.map(\.name)
        let errors = ValidationService.walletMessages(draft, existingNames: names, ignoringName: wallet?.name)
        guard errors.isEmpty, let opening = ValidationService.parseOpeningBalance(draft.openingBalanceText, currencyCode: draft.currencyCode) else {
            messages = errors
            return
        }
        let target: Wallet
        if let wallet {
            target = wallet
        } else {
            target = Wallet(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: draft.type,
                currencyCode: draft.currencyCode,
                openingBalance: opening,
                iconName: draft.iconName,
                colorHex: draft.colorHex
            )
            modelContext.insert(target)
        }
        target.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.walletType = draft.type
        if !currencyLocked {
            target.currencyCode = draft.currencyCode.uppercased()
        }
        target.openingBalance = opening
        target.iconName = draft.iconName
        target.colorHex = draft.colorHex
        do {
            try modelContext.save()
            dismiss()
        } catch {
            messages = ["The wallet could not be saved."]
        }
    }
}
