import Foundation

enum CSVExporter {
    static let headers = [
        "Date", "Type", "Title", "Category", "Wallet", "Amount", "Currency",
        "Payment method", "Notes", "Tags"
    ]

    static func make(
        transactions: [FinanceTransaction],
        categories: [FinanceCategory],
        wallets: [FinanceWallet],
        calendar: Calendar
    ) -> String {
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let walletNames = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0.name) })
        var lines = [headers.map(escape).joined(separator: ",")]
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        for transaction in transactions {
            let walletName: String
            if transaction.type == .transfer {
                let source = transaction.walletID.flatMap { walletNames[$0] } ?? ""
                let destination = transaction.destinationWalletID.flatMap { walletNames[$0] } ?? ""
                walletName = "\(source) → \(destination)"
            } else {
                walletName = transaction.walletID.flatMap { walletNames[$0] } ?? ""
            }
            let fields = [
                formatter.string(from: transaction.date),
                transaction.type.title,
                transaction.title,
                transaction.categoryID.flatMap { categoryNames[$0] } ?? "",
                walletName,
                Money.exportString(transaction.amount),
                transaction.currencyCode,
                transaction.paymentMethod?.title ?? "",
                transaction.notes,
                transaction.tags.joined(separator: "; ")
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func data(
        transactions: [FinanceTransaction],
        categories: [FinanceCategory],
        wallets: [FinanceWallet],
        calendar: Calendar
    ) -> Data {
        Data(make(transactions: transactions, categories: categories, wallets: wallets, calendar: calendar).utf8)
    }

    /// RFC 4180 escaping for commas, quotes, and line breaks.
    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
