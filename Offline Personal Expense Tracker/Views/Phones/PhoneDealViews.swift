import SwiftData
import SwiftUI

private enum PhoneListFilter: String, CaseIterable, Identifiable {
    case all
    case inStock
    case pending
    case settled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .inStock: "In stock"
        case .pending: "Pending"
        case .settled: "Received"
        }
    }
}

struct PhoneDealListView: View {
    @Query(sort: \PhoneDeal.purchaseDate, order: .reverse) private var deals: [PhoneDeal]
    @Query private var settingsRows: [AppSettings]
    @State private var filter: PhoneListFilter = .all
    @State private var showEditor = false
    @State private var saleRequest: ListSaleRequest?

    var body: some View {
        NavigationStack {
            Group {
                if deals.isEmpty {
                    EmptyStateView(
                        title: "No phone purchases",
                        message: "Record a phone you buy on Amazon, Flipkart, or JioMart with a card offer. When a dealer buys it, track whether their payment is still pending or already received.",
                        systemImage: "iphone",
                        actionTitle: "Add purchase",
                        action: { showEditor = true }
                    )
                } else {
                    List {
                        Section {
                            summary
                        }
                        Section {
                            Picker("Show", selection: $filter) {
                                ForEach(PhoneListFilter.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        Section {
                            if visible.isEmpty {
                                Text("Nothing in this group.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(visible) { deal in
                                    VStack(alignment: .leading, spacing: 10) {
                                        NavigationLink {
                                            PhoneDealDetailView(deal: deal)
                                        } label: {
                                            PhoneDealRow(deal: deal)
                                        }
                                        listActions(for: deal)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        if canMarkPending(deal) {
                                            Button("Pending") { saleRequest = ListSaleRequest(deal: deal, kind: .pending) }
                                                .tint(.orange)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Phones")
            .toolbar {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add phone purchase")
            }
            .sheet(isPresented: $showEditor) {
                NavigationStack {
                    PhoneDealEditorView(deal: nil)
                }
            }
            .sheet(item: $saleRequest) { request in
                NavigationStack {
                    if let deal = deals.first(where: { $0.persistentModelID == request.dealID }) {
                        ListSaleSheet(deal: deal, recordsPayment: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func listActions(for deal: PhoneDeal) -> some View {
        if canMarkPending(deal) {
            Button("Pending") { saleRequest = ListSaleRequest(deal: deal, kind: .pending) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
        }
    }

    /// One sale entry from the list. After the dealer and price are saved, the payment is received and the row has no second sale button.
    private func canMarkPending(_ deal: PhoneDeal) -> Bool {
        !deal.isSold && deal.lotPosition.stage == .inStock
    }

    private var currency: String { settingsRows.first?.baseCurrencyCode ?? "USD" }

    private var summary: some View {
        let book = PhoneDealCalculator.summary(lots: deals.map { $0.lot() }, currencyCode: currency)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                summaryMetric("Pending", value: book.pendingPayment, caption: "\(book.pendingCount) deals", tint: .orange)
                summaryMetric("Received", value: book.successfulPayment, caption: "\(book.settledCount) settled", tint: Theme.income)
            }
            HStack {
                summaryMetric("Profit", value: book.profit, caption: "On phones already sold", tint: book.profit < 0 ? Theme.expense : Theme.income)
                summaryMetric("In stock", value: book.stockCost, caption: "\(book.inStockCount) purchases not sold", tint: .primary)
            }
            Text("Pending is what dealers still owe you. Received is money they have already paid. Profit is the sale price minus what you paid for the phones that were sold.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func summaryMetric(_ title: String, value: Decimal, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(DisplayFormat.money(value, currencyCode: currency))
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var visible: [PhoneDeal] {
        deals.filter { deal in
            switch filter {
            case .all: return true
            case .inStock: return deal.lotPosition.stage == .inStock
            case .pending: return deal.lotPosition.stage == .paymentPending
            case .settled: return deal.lotPosition.stage == .settled
            }
        }
    }
}

private struct PhoneDealRow: View {
    var deal: PhoneDeal

    var body: some View {
        let position = deal.lotPosition
        HStack(spacing: 12) {
            Image(systemName: "iphone")
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(deal.phoneName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(position.stage.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: position.stage))
                Text(trailingAmount(position))
                    .font(.subheadline.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [deal.platformTitle]
        if deal.quantity > 1 { parts.append("\(deal.quantity) phones") }
        if deal.isSold, !deal.dealerName.isEmpty { parts.append(deal.dealerName) }
        return parts.joined(separator: " · ")
    }

    private func trailingAmount(_ position: PhoneLotPosition) -> String {
        switch position.stage {
        case .inStock:
            return DisplayFormat.money(deal.purchaseAmount, currencyCode: deal.currencyCode)
        case .paymentPending:
            return DisplayFormat.money(position.pendingPayment, currencyCode: deal.currencyCode)
        case .settled:
            return DisplayFormat.money(position.profit, currencyCode: deal.currencyCode, direction: position.profit < 0 ? .expense : .income)
        }
    }

    private func color(for stage: PhoneDealStage) -> Color {
        switch stage {
        case .inStock: .secondary
        case .paymentPending: .orange
        case .settled: Theme.income
        }
    }
}

struct PhoneDealDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    var deal: PhoneDeal
    @State private var showEditor = false
    @State private var showPayment = false
    @State private var confirmDelete = false
    @State private var message: String?

    var body: some View {
        let position = deal.lotPosition
        List {
            Section {
                LabeledContent("Status", value: position.stage.title)
                LabeledContent("Bought from", value: deal.platformTitle)
                LabeledContent("Amount paid", value: DisplayFormat.money(deal.purchaseAmount, currencyCode: deal.currencyCode))
                if deal.offerDiscount > 0 {
                    LabeledContent("Card offer", value: DisplayFormat.money(deal.offerDiscount, currencyCode: deal.currencyCode))
                }
                LabeledContent("Quantity", value: "\(deal.quantity)")
                if !deal.orderReference.isEmpty {
                    LabeledContent("Order", value: deal.orderReference)
                }
                if let card = deal.purchaseWallet?.name {
                    LabeledContent("Paid with", value: card)
                }
            }
            Section("Dealer") {
                if deal.isSold {
                    LabeledContent("Dealer", value: deal.dealerName)
                    LabeledContent("Sold", value: "\(deal.quantitySold) of \(deal.quantity)")
                    LabeledContent("Sale price", value: DisplayFormat.money(deal.saleAmount, currencyCode: deal.currencyCode))
                    LabeledContent("Received", value: DisplayFormat.money(position.successfulPayment, currencyCode: deal.currencyCode))
                    LabeledContent("Pending", value: DisplayFormat.money(position.pendingPayment, currencyCode: deal.currencyCode))
                    LabeledContent("Profit", value: DisplayFormat.money(position.profit, currencyCode: deal.currencyCode, direction: position.profit < 0 ? .expense : .income))
                    if position.stockCost > 0 {
                        LabeledContent("Still in stock", value: DisplayFormat.money(position.stockCost, currencyCode: deal.currencyCode))
                    }
                } else {
                    Text("These phones are still with you. Record the dealer sale when you hand them over.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if deal.isSold {
                Section("Payments") {
                    if deal.payments.isEmpty {
                        Text("No payment recorded yet. The full sale price is pending.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(deal.payments.sorted { $0.date > $1.date }) { payment in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(DisplayFormat.money(payment.amount, currencyCode: deal.currencyCode))
                                        .monospacedDigit()
                                    if !payment.note.isEmpty {
                                        Text(payment.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(payment.date, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    delete(payment)
                                }
                            }
                        }
                    }
                    Button("Record dealer payment") { showPayment = true }
                }
            }
            Section {
                Button("Edit") { showEditor = true }
                Button("Delete purchase", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(deal.phoneName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            NavigationStack { PhoneDealEditorView(deal: deal) }
        }
        .sheet(isPresented: $showPayment) {
            NavigationStack { DealerPaymentSheet(deal: deal) }
        }
        .confirmationDialog("Delete this phone purchase?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteDeal)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The purchase and any dealer payments posted to your wallets are removed with it.")
        }
        .alert("Phones", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func delete(_ payment: DealerPayment) {
        do {
            try PhoneDealService.delete(payment: payment, in: modelContext)
        } catch {
            message = "That payment could not be removed."
        }
    }

    private func deleteDeal() {
        do {
            try PhoneDealService.delete(deal: deal, in: modelContext)
            dismiss()
        } catch {
            message = "This purchase could not be deleted."
        }
    }
}

private enum ReceiptChannel: String, CaseIterable, Identifiable {
    case cash
    case online

    var id: String { rawValue }
    var title: String { self == .cash ? "Cash" : "Online" }

    var walletType: WalletType { self == .cash ? .cash : .digital }

    static func matching(_ wallet: Wallet?) -> ReceiptChannel {
        wallet?.walletType == .digital ? .online : .cash
    }

    @MainActor
    static func wallet(
        for channel: ReceiptChannel,
        currencyCode: String,
        wallets: [Wallet],
        context: ModelContext
    ) -> Wallet {
        let code = currencyCode.uppercased()
        if let existing = wallets.first(where: {
            !$0.isArchived
                && !$0.walletType.isLiability
                && $0.currencyCode == code
                && $0.name.caseInsensitiveCompare(channel.title) == .orderedSame
        }) {
            return existing
        }
        let created = Wallet(
            name: channel.title,
            type: channel.walletType,
            currencyCode: code,
            openingBalance: 0,
            iconName: channel.walletType.systemImage,
            colorHex: channel == .cash ? "1A6B4A" : "1D4E89"
        )
        context.insert(created)
        return created
    }
}

private struct ListSaleRequest: Identifiable {
    enum Kind {
        case pending
        case sold
    }

    let dealID: PersistentIdentifier
    let kind: Kind

    init(deal: PhoneDeal, kind: Kind) {
        dealID = deal.persistentModelID
        self.kind = kind
    }

    var id: String { "\(dealID)-\(kind == .sold ? "sold" : "pending")" }
}

private struct ListSaleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    var deal: PhoneDeal
    var recordsPayment: Bool

    @State private var dealerName = ""
    @State private var quantitySold = 1
    @State private var saleText = ""
    @State private var date = Date()
    @State private var channel: ReceiptChannel = .cash
    @State private var messages: [String] = []

    var body: some View {
        Form {
            if deal.isSold, recordsPayment {
                Section {
                    LabeledContent("Dealer", value: deal.dealerName)
                    LabeledContent("Still pending", value: DisplayFormat.money(deal.lotPosition.pendingPayment, currencyCode: deal.currencyCode))
                }
            } else {
                Section {
                    TextField("Dealer name", text: $dealerName)
                    if deal.quantity > 1 {
                        Stepper("Sold: \(quantitySold) of \(deal.quantity)", value: $quantitySold, in: 1...deal.quantity)
                    }
                    TextField("Sale price", text: $saleText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    DatePicker(recordsPayment ? "Payment date" : "Sale date", selection: $date, displayedComponents: .date)
                }
            }
            if recordsPayment {
                Section("Received in") {
                    Picker("Received in", selection: $channel) {
                        ForEach(ReceiptChannel.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("This records the sale once and marks the dealer payment as received.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !messages.isEmpty {
                Section {
                    ForEach(messages, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.expense) }
                }
            }
        }
        .navigationTitle("Pending")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear {
            dealerName = deal.dealerName
            quantitySold = deal.isSold ? max(deal.quantitySold, 1) : deal.quantity
            if deal.saleAmount > 0 { saleText = Money.exportString(deal.saleAmount) }
            date = deal.saleDate ?? Date()
            channel = ReceiptChannel.matching(deal.receiptWallet)
        }
    }

    private func save() {
        if recordsPayment, deal.isSold {
            saveReceiptOfRemaining()
            return
        }
        var errors: [String] = []
        let dealer = dealerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if dealer.isEmpty { errors.append("Enter the dealer name.") }
        guard let sale = AmountParser.parse(saleText, currencyCode: deal.currencyCode) else {
            errors.append("Enter the price the dealer agreed to pay.")
            messages = errors
            return
        }
        if quantitySold < 1 || quantitySold > deal.quantity {
            errors.append("The number sold cannot be more than the number you bought.")
        }
        guard errors.isEmpty else {
            messages = errors
            return
        }
        deal.isSold = true
        deal.dealerName = dealer
        deal.quantitySold = quantitySold
        deal.saleAmount = sale
        deal.saleDate = date
        if recordsPayment {
            let wallet = receiptWallet(for: channel)
            deal.receiptWallet = wallet
            let payment = DealerPayment(amount: sale, date: date, note: channel.title)
            payment.deal = deal
            modelContext.insert(payment)
        }
        do {
            try PhoneDealService.syncLedger(deal: deal, in: modelContext)
            dismiss()
        } catch {
            messages = ["This sale could not be saved."]
        }
    }

    private func saveReceiptOfRemaining() {
        let pending = deal.lotPosition.pendingPayment
        guard pending > 0 else {
            messages = ["This dealer has already paid."]
            return
        }
        let wallet = receiptWallet(for: channel)
        deal.receiptWallet = wallet
        let payment = DealerPayment(amount: pending, date: date, note: channel.title)
        payment.deal = deal
        modelContext.insert(payment)
        do {
            try PhoneDealService.syncLedger(deal: deal, in: modelContext)
            dismiss()
        } catch {
            messages = ["This payment could not be saved."]
        }
    }

    private func receiptWallet(for channel: ReceiptChannel) -> Wallet {
        ReceiptChannel.wallet(for: channel, currencyCode: deal.currencyCode, wallets: wallets, context: modelContext)
    }
}

private struct DealerPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    var deal: PhoneDeal
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var channel: ReceiptChannel = .cash
    @State private var messages: [String] = []

    var body: some View {
        Form {
            TextField("Amount received", text: $amountText)
                .keyboardType(.decimalPad)
                .monospacedDigit()
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Note", text: $note)
            Picker("Received in", selection: $channel) {
                ForEach(ReceiptChannel.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            if !messages.isEmpty {
                ForEach(messages, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.expense) }
            }
        }
        .navigationTitle("Dealer payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear {
            channel = ReceiptChannel.matching(deal.receiptWallet)
        }
    }

    private func save() {
        guard let amount = AmountParser.parse(amountText, currencyCode: deal.currencyCode) else {
            messages = ["Enter the amount the dealer paid."]
            return
        }
        let wallet = ReceiptChannel.wallet(for: channel, currencyCode: deal.currencyCode, wallets: wallets, context: modelContext)
        deal.receiptWallet = wallet
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let payment = DealerPayment(amount: amount, date: date, note: trimmed.isEmpty ? channel.title : trimmed)
        payment.deal = deal
        modelContext.insert(payment)
        do {
            try PhoneDealService.syncLedger(deal: deal, in: modelContext)
            dismiss()
        } catch {
            messages = ["The payment could not be saved."]
        }
    }
}

struct PhoneDealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    @Query private var settingsRows: [AppSettings]
    var deal: PhoneDeal?

    @State private var phoneName = ""
    @State private var platform: ShopPlatform = .flipkart
    @State private var platformDetail = ""
    @State private var quantity = 1
    @State private var orderReference = ""
    @State private var purchaseText = ""
    @State private var offerText = ""
    @State private var purchaseDate = Date()
    @State private var purchaseWalletID: UUID?
    @State private var notes = ""
    @State private var isSold = false
    @State private var dealerName = ""
    @State private var quantitySold = 1
    @State private var saleText = ""
    @State private var saleDate = Date()
    @State private var messages: [String] = []

    var body: some View {
        Form {
            Section("Purchase") {
                TextField("Phone name", text: $phoneName)
                Picker("Bought from", selection: $platform) {
                    ForEach(ShopPlatform.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                if platform == .other {
                    TextField("Store name", text: $platformDetail)
                }
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                TextField("Amount you paid", text: $purchaseText)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                TextField("Card offer discount (optional)", text: $offerText)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                DatePicker("Purchase date", selection: $purchaseDate, displayedComponents: .date)
                TextField("Order ID", text: $orderReference)
                Picker("Credit card or wallet", selection: $purchaseWalletID) {
                    Text("Choose").tag(Optional<UUID>.none)
                    ForEach(activeWallets) { wallet in
                        Text("\(wallet.name) · \(wallet.currencyCode)").tag(Optional(wallet.id))
                    }
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                Text("The amount you paid is charged to the selected card, so the card balance shows what you owe for this purchase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Sale to dealer") {
                Toggle("Sold to a dealer", isOn: $isSold)
                if isSold {
                    TextField("Dealer name", text: $dealerName)
                    Stepper("Sold: \(quantitySold) of \(quantity)", value: $quantitySold, in: 1...quantity)
                    TextField("Sale price", text: $saleText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    DatePicker("Sale date", selection: $saleDate, displayedComponents: .date)
                    Text("After you save, record each payment the dealer sends. Pending is the sale price minus those payments.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if !messages.isEmpty {
                Section {
                    ForEach(messages, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.expense) }
                }
            }
        }
        .navigationTitle(deal == nil ? "New purchase" : "Edit purchase")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
        }
        .onAppear(perform: load)
        .onChange(of: quantity) { _, newValue in
            if quantitySold > newValue { quantitySold = newValue }
        }
    }

    private var activeWallets: [Wallet] { wallets.filter { !$0.isArchived } }
    private var currency: String {
        activeWallets.first { $0.id == purchaseWalletID }?.currencyCode
            ?? settingsRows.first?.baseCurrencyCode
            ?? "USD"
    }

    private func load() {
        purchaseWalletID = activeWallets.first { $0.walletType == .creditCard }?.id ?? activeWallets.first?.id
        guard let deal else { return }
        phoneName = deal.phoneName
        platform = deal.platform
        platformDetail = deal.platformDetail
        quantity = max(deal.quantity, 1)
        orderReference = deal.orderReference
        purchaseText = Money.exportString(deal.purchaseAmount)
        offerText = deal.offerDiscount > 0 ? Money.exportString(deal.offerDiscount) : ""
        purchaseDate = deal.purchaseDate
        purchaseWalletID = deal.purchaseWallet?.id ?? purchaseWalletID
        notes = deal.notes
        isSold = deal.isSold
        dealerName = deal.dealerName
        quantitySold = deal.isSold ? max(deal.quantitySold, 1) : 1
        saleText = deal.saleAmount > 0 ? Money.exportString(deal.saleAmount) : ""
        saleDate = deal.saleDate ?? Date()
    }

    private func save() {
        var errors: [String] = []
        let name = phoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { errors.append("Enter the phone name.") }
        guard let paid = AmountParser.parse(purchaseText, currencyCode: currency) else {
            errors.append("Enter the amount you paid after the card offer.")
            messages = errors
            return
        }
        var offer = Decimal.zero
        if !offerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if offerText == "0" || offerText == "0.0" || offerText == "0,0" {
                offer = 0
            } else if let parsed = AmountParser.parse(offerText, currencyCode: currency) {
                offer = parsed
            } else {
                errors.append("Enter the offer discount as zero or a positive amount.")
            }
        }
        if activeWallets.isEmpty == false && purchaseWalletID == nil {
            errors.append("Choose the card or wallet you used to pay.")
        }
        var sale = Decimal.zero
        if isSold {
            if dealerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Enter the dealer name.")
            }
            if quantitySold < 1 || quantitySold > quantity {
                errors.append("The number sold cannot be more than the number you bought.")
            }
            if let parsed = AmountParser.parse(saleText, currencyCode: currency) {
                sale = parsed
            } else {
                errors.append("Enter the price the dealer agreed to pay.")
            }
        }
        guard errors.isEmpty else {
            messages = errors
            return
        }
        let target: PhoneDeal
        if let deal {
            target = deal
        } else {
            target = PhoneDeal(
                phoneName: name,
                platform: platform,
                quantity: quantity,
                purchaseAmount: paid,
                currencyCode: currency
            )
            modelContext.insert(target)
        }
        target.phoneName = name
        target.platform = platform
        target.platformDetail = platformDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        target.quantity = quantity
        target.orderReference = orderReference.trimmingCharacters(in: .whitespacesAndNewlines)
        target.purchaseAmount = paid
        target.offerDiscount = offer
        target.purchaseDate = purchaseDate
        target.currencyCode = currency
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.purchaseWallet = wallets.first { $0.id == purchaseWalletID }
        target.isSold = isSold
        if isSold {
            target.dealerName = dealerName.trimmingCharacters(in: .whitespacesAndNewlines)
            target.quantitySold = quantitySold
            target.saleAmount = sale
            target.saleDate = saleDate
        } else {
            target.dealerName = ""
            target.quantitySold = 0
            target.saleAmount = 0
            target.saleDate = nil
        }
        do {
            try PhoneDealService.syncLedger(deal: target, in: modelContext)
            dismiss()
        } catch {
            messages = ["This purchase could not be saved."]
        }
    }
}

private extension PhoneDeal {
    var lotPosition: PhoneLotPosition {
        PhoneDealCalculator.position(for: lot())
    }
}
