import Foundation

struct TransactionDraft: Equatable, Sendable {
    var type: TransactionType = .expense
    var amountText: String = ""
    var title: String = ""
    var notes: String = ""
    var categoryID: UUID?
    var walletID: UUID?
    var destinationWalletID: UUID?
    var date: Date = Date()
    var tagsText: String = ""
    var paymentMethod: PaymentMethod?
    var merchant: String = ""
    var makeRecurring: Bool = false
    var frequency: RecurrenceFrequency = .monthly
    var recurrenceEnds: Bool = false
    var recurrenceEnd: Date = Date()
}

struct ParsedTransaction: Equatable, Sendable {
    var type: TransactionType
    var amount: Decimal
    var title: String
    var notes: String
    var categoryID: UUID?
    var walletID: UUID
    var destinationWalletID: UUID?
    var date: Date
    var tags: [String]
    var paymentMethod: PaymentMethod?
    var merchant: String
    var makeRecurring: Bool
    var frequency: RecurrenceFrequency
    var recurrenceEnd: Date?
}

struct WalletDraft: Equatable, Sendable {
    var name: String = ""
    var type: WalletType = .cash
    var currencyCode: String = "USD"
    var openingBalanceText: String = "0"
    var iconName: String = "banknote"
    var colorHex: String = "1A6B4A"
}

struct BudgetDraft: Equatable, Sendable {
    var name: String = ""
    var amountText: String = ""
    var isOverall: Bool = true
    var categoryID: UUID?
    var startDate: Date = Date()
    var endDate: Date = Date()
    var warningThreshold: Double = 0.8
    var notifyAtWarning: Bool = false
    var notifyAtExceeded: Bool = false
}

enum ValidationService {
    static func parseTransaction(
        _ draft: TransactionDraft,
        wallets: [FinanceWallet]
    ) -> (parsed: ParsedTransaction?, messages: [String]) {
        var messages: [String] = []
        let currency = wallets.first { $0.id == draft.walletID }?.currencyCode ?? "USD"
        let amount = AmountParser.parse(draft.amountText, currencyCode: currency)
        if amount == nil {
            messages.append("Enter an amount greater than zero.")
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            messages.append("Enter a title.")
        } else if title.count > 80 {
            messages.append("Title must be 80 characters or fewer.")
        }
        if draft.notes.count > 2000 {
            messages.append("Notes must be 2,000 characters or fewer.")
        }
        if draft.merchant.count > 80 {
            messages.append("Merchant must be 80 characters or fewer.")
        }
        guard let walletID = draft.walletID, let wallet = wallets.first(where: { $0.id == walletID }) else {
            messages.append("Choose a wallet.")
            return (nil, messages)
        }
        if wallet.isArchived {
            messages.append("Choose an active wallet.")
        }

        var destination: UUID?
        if draft.type == .transfer {
            guard let destinationID = draft.destinationWalletID,
                  let destinationWallet = wallets.first(where: { $0.id == destinationID }) else {
                messages.append("Choose a destination wallet.")
                return (nil, messages)
            }
            if destinationID == wallet.id {
                messages.append("Choose two different wallets.")
            }
            if destinationWallet.currencyCode != wallet.currencyCode {
                messages.append("Transfers require wallets that use the same currency. Exchange rates are not available offline.")
            }
            if destinationWallet.isArchived {
                messages.append("The destination wallet is archived.")
            }
            destination = destinationID
        } else if draft.categoryID == nil {
            messages.append("Choose a category.")
        }

        let tags = parseTags(draft.tagsText)
        if tags.count > 12 {
            messages.append("Use 12 tags or fewer.")
        }
        if tags.contains(where: { $0.count > 24 }) {
            messages.append("Each tag must be 24 characters or fewer.")
        }
        if draft.makeRecurring, draft.recurrenceEnds, draft.recurrenceEnd < draft.date {
            messages.append("The repeat end date must be on or after the transaction date.")
        }

        guard messages.isEmpty, let amount else { return (nil, messages) }
        return (
            ParsedTransaction(
                type: draft.type,
                amount: amount,
                title: title,
                notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                categoryID: draft.type == .transfer ? nil : draft.categoryID,
                walletID: wallet.id,
                destinationWalletID: destination,
                date: draft.date,
                tags: tags,
                paymentMethod: draft.paymentMethod,
                merchant: draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
                makeRecurring: draft.makeRecurring && draft.type != .transfer ? draft.makeRecurring : draft.makeRecurring,
                frequency: draft.frequency,
                recurrenceEnd: draft.makeRecurring && draft.recurrenceEnds ? draft.recurrenceEnd : nil
            ),
            messages
        )
    }

    static func transferFundsMessage(
        source: FinanceWallet,
        sourceBalance: Decimal,
        amount: Decimal
    ) -> String? {
        guard !source.isLiability, sourceBalance < amount else { return nil }
        return "This \(source.type.title.lowercased()) does not have enough funds for this transfer."
    }

    static func parseOpeningBalance(_ text: String, currencyCode: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "0" || trimmed == "0.0" || trimmed == "0,0" {
            return .zero
        }
        return AmountParser.parse(trimmed, currencyCode: currencyCode)
    }

    static func walletMessages(_ draft: WalletDraft, existingNames: [String], ignoringName: String? = nil) -> [String] {
        var messages: [String] = []
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            messages.append("Enter a wallet name.")
        } else if name.count > 40 {
            messages.append("Wallet name must be 40 characters or fewer.")
        } else if existingNames.contains(where: { $0.compare(name, options: .caseInsensitive) == .orderedSame && $0 != ignoringName }) {
            messages.append("A wallet with this name already exists.")
        }
        if draft.currencyCode.count != 3 {
            messages.append("Choose a currency.")
        }
        if parseOpeningBalance(draft.openingBalanceText, currencyCode: draft.currencyCode) == nil {
            messages.append(draft.type.isLiability
                ? "Enter the amount owed as a positive number, or zero."
                : "Enter an opening balance of zero or more.")
        }
        return messages
    }

    static func budgetMessages(_ draft: BudgetDraft, currencyCode: String) -> [String] {
        var messages: [String] = []
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            messages.append("Enter a budget name.")
        }
        if AmountParser.parse(draft.amountText, currencyCode: currencyCode) == nil {
            messages.append("Enter a budget amount greater than zero.")
        }
        if !draft.isOverall && draft.categoryID == nil {
            messages.append("Choose a category.")
        }
        let calendar = Calendar(identifier: .gregorian)
        if calendar.startOfDay(for: draft.endDate) < calendar.startOfDay(for: draft.startDate) {
            messages.append("The end date must be on or after the start date.")
        }
        if draft.warningThreshold < 0.5 || draft.warningThreshold > 1 {
            messages.append("The warning threshold must be between 50% and 100%.")
        }
        return messages
    }

    static func parseTags(_ text: String) -> [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let tag = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = tag.lowercased()
            guard !tag.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            tags.append(tag)
        }
        return tags
    }
}
