import Foundation
import PDFKit
import UIKit

struct PDFReportRequest: Sendable {
    var title: String
    var periodLabel: String
    var generatedAt: Date
    var report: FinanceReport
    var transactions: [FinanceTransaction]
    var categories: [FinanceCategory]
    var wallets: [FinanceWallet]
    var calendar: Calendar
    var locale: Locale = .current
}

enum PDFExporter {
    static func make(_ request: PDFReportRequest) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 40
        let contentWidth = pageRect.width - margin * 2
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: request.title,
            kCGPDFContextCreator as String: "Offline Personal Expense Tracker",
            kCGPDFContextAuthor as String: "On-device report"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let titleFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
        let headerFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        let smallFont = UIFont.systemFont(ofSize: 8, weight: .regular)
        let ink = UIColor(white: 0.12, alpha: 1)
        let secondary = UIColor(white: 0.38, alpha: 1)

        return renderer.pdfData { context in
            var pageNumber = 0
            var y: CGFloat = margin

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                y = margin
                let header = request.title
                y += draw(header, font: titleFont, color: ink, x: margin, y: y, width: contentWidth)
                y += 2
                let subtitle = "\(request.periodLabel)  ·  \(request.report.currencyCode)"
                y += draw(subtitle, font: bodyFont, color: secondary, x: margin, y: y, width: contentWidth)
                y += 8
                let footer = "Page \(pageNumber)"
                let footerWidth = (footer as NSString).size(withAttributes: [.font: smallFont]).width
                footer.draw(
                    at: CGPoint(x: pageRect.width - margin - footerWidth, y: pageRect.height - 28),
                    withAttributes: [.font: smallFont, .foregroundColor: secondary]
                )
                let generated = "Generated \(iso(request.generatedAt))"
                generated.draw(
                    at: CGPoint(x: margin, y: pageRect.height - 28),
                    withAttributes: [.font: smallFont, .foregroundColor: secondary]
                )
            }

            func ensure(_ height: CGFloat) {
                if y + height > pageRect.height - margin - 20 {
                    beginPage()
                }
            }

            beginPage()
            ensure(120)
            y += draw("Summary", font: headerFont, color: ink, x: margin, y: y, width: contentWidth) + 4
            let summaryRows = [
                ("Opening balance", money(request.report.openingNetWorth, code: request.report.currencyCode, locale: request.locale)),
                ("Income", money(request.report.income, code: request.report.currencyCode, locale: request.locale)),
                ("Expenses", money(request.report.expense, code: request.report.currencyCode, locale: request.locale)),
                ("Net cash flow", money(request.report.net, code: request.report.currencyCode, locale: request.locale)),
                ("Closing balance", money(request.report.closingNetWorth, code: request.report.currencyCode, locale: request.locale))
            ]
            for row in summaryRows {
                ensure(16)
                y += drawPair(row.0, row.1, font: bodyFont, color: ink, y: y, width: contentWidth) 
            }
            if request.report.excludedForeignWalletCount > 0 {
                ensure(28)
                y += 4
                y += draw(
                    "Wallets in other currencies are listed separately and are not included in these totals.",
                    font: smallFont,
                    color: secondary,
                    x: margin,
                    y: y,
                    width: contentWidth
                )
            }

            y += 12
            ensure(40)
            y += draw("Expenses by category", font: headerFont, color: ink, x: margin, y: y, width: contentWidth) + 4
            if request.report.expenseByCategory.isEmpty {
                y += draw("No expenses in this period.", font: bodyFont, color: secondary, x: margin, y: y, width: contentWidth)
            } else {
                for row in request.report.expenseByCategory {
                    ensure(16)
                    y += drawPair(
                        row.name,
                        money(row.amount, code: request.report.currencyCode, locale: request.locale),
                        font: bodyFont,
                        color: ink,
                        y: y,
                        width: contentWidth
                    )
                }
            }

            y += 12
            ensure(40)
            y += draw("Wallets", font: headerFont, color: ink, x: margin, y: y, width: contentWidth) + 4
            if request.report.walletBalances.isEmpty {
                y += draw("No wallets.", font: bodyFont, color: secondary, x: margin, y: y, width: contentWidth)
            } else {
                for wallet in request.report.walletBalances {
                    ensure(16)
                    let label = wallet.type.isLiability ? "\(wallet.name) (owed)" : wallet.name
                    let value = money(wallet.balance, code: wallet.currencyCode, locale: request.locale)
                    y += drawPair(label, value, font: bodyFont, color: ink, y: y, width: contentWidth)
                }
            }

            y += 12
            ensure(40)
            y += draw("Transactions", font: headerFont, color: ink, x: margin, y: y, width: contentWidth) + 4
            let columns: [CGFloat] = [72, 150, 90, 90, contentWidth - 402]
            ensure(16)
            drawColumns(["Date", "Title", "Category", "Wallet", "Amount"], widths: columns, font: headerFont, color: secondary, y: y)
            y += 14
            let categoryNames = Dictionary(uniqueKeysWithValues: request.categories.map { ($0.id, $0.name) })
            let walletNames = Dictionary(uniqueKeysWithValues: request.wallets.map { ($0.id, $0.name) })
            if request.transactions.isEmpty {
                y += draw("No transactions in this period.", font: bodyFont, color: secondary, x: margin, y: y, width: contentWidth)
            }
            for transaction in request.transactions {
                ensure(18)
                let amountText: String
                switch transaction.type {
                case .income:
                    amountText = money(transaction.amount, code: transaction.currencyCode, locale: request.locale)
                case .expense:
                    amountText = "−" + money(transaction.amount, code: transaction.currencyCode, locale: request.locale)
                case .transfer:
                    amountText = money(transaction.amount, code: transaction.currencyCode, locale: request.locale)
                }
                let values = [
                    shortDate(transaction.date, calendar: request.calendar),
                    transaction.title,
                    transaction.categoryID.flatMap { categoryNames[$0] } ?? (transaction.type == .transfer ? "Transfer" : ""),
                    transaction.walletID.flatMap { walletNames[$0] } ?? "",
                    amountText
                ]
                drawColumns(values, widths: columns, font: smallFont, color: ink, y: y)
                y += 14
            }
        }
    }

    static func document(from data: Data) -> PDFDocument? {
        PDFDocument(data: data)
    }

    private static func money(_ amount: Decimal, code: String, locale: Locale) -> String {
        DisplayFormat.money(amount, currencyCode: code, direction: .plain, locale: locale)
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func shortDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    @discardableResult
    private static func draw(_ text: String, font: UIFont, color: UIColor, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: 2000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let height = ceil(bounds.height)
        (text as NSString).draw(in: CGRect(x: x, y: y, width: width, height: height), withAttributes: attributes)
        return height
    }

    @discardableResult
    private static func drawPair(_ leading: String, _ trailing: String, font: UIFont, color: UIColor, y: CGFloat, width: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        leading.draw(at: CGPoint(x: 40, y: y), withAttributes: attributes)
        let size = (trailing as NSString).size(withAttributes: attributes)
        trailing.draw(at: CGPoint(x: 40 + width - size.width, y: y), withAttributes: attributes)
        return 14
    }

    private static func drawColumns(_ values: [String], widths: [CGFloat], font: UIFont, color: UIColor, y: CGFloat) {
        var x: CGFloat = 40
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for (index, value) in values.enumerated() {
            let width = widths[index]
            let clipped = (value as NSString)
            clipped.draw(
                with: CGRect(x: x, y: y, width: width - 4, height: 12),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attributes,
                context: nil
            )
            x += width
        }
    }
}
