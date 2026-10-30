import Foundation
import SwiftUI

enum MoneyDirection: Sendable {
    case plain
    case income
    case expense
    case transfer
}

enum DisplayFormat {
    static func dateString(_ date: Date, preference: DateFormatPreference, calendar: Calendar) -> String {
        switch preference {
        case .iso:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        case .short, .medium, .long:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = .current
            formatter.timeZone = calendar.timeZone
            switch preference {
            case .short: formatter.dateStyle = .short
            case .medium: formatter.dateStyle = .medium
            case .long: formatter.dateStyle = .long
            case .iso: break
            }
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    static func money(
        _ amount: Decimal,
        currencyCode: String,
        direction: MoneyDirection = .plain,
        locale: Locale = .current
    ) -> String {
        let rounded = Money.rounded(abs(amount), currencyCode: currencyCode)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        let units = Money.minorUnits(for: currencyCode)
        formatter.minimumFractionDigits = units
        formatter.maximumFractionDigits = units
        let body = formatter.string(from: rounded as NSDecimalNumber) ?? "\(currencyCode) \(Money.exportString(rounded))"
        switch direction {
        case .plain, .transfer:
            return body
        case .income:
            return "+\(body)"
        case .expense:
            return "−\(body)"
        }
    }

    static func percent(_ ratio: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let number = NSDecimalNumber(decimal: ratio)
        return formatter.string(from: number) ?? "\(number)%"
    }

    static var currencyCodes: [String] {
        Locale.commonISOCurrencyCodes.sorted()
    }

    static func currencyName(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}

extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        if cleaned.count == 6 {
            let red = Double((value >> 16) & 0xFF) / 255
            let green = Double((value >> 8) & 0xFF) / 255
            let blue = Double(value & 0xFF) / 255
            self.init(red: red, green: green, blue: blue)
        } else {
            self = .accentColor
        }
    }
}

enum Theme {
    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 12
    static let income = Color("IncomeColor")
    static let expense = Color("ExpenseColor")
    static let swatches = ["1A6B4A", "1D4E89", "6B4C9A", "8C4A32", "8E3140", "2F6F73", "3E5C4A", "9A6B2F"]
    static let icons = [
        "banknote", "building.columns", "creditcard", "wallet.pass", "tray.full",
        "house", "cart", "fork.knife", "car", "bus", "bolt", "cross.case",
        "film", "bag", "book", "airplane", "gift", "star", "pawprint", "briefcase"
    ]
}

enum AppLog {
    static func persistence(_ message: String) {
        // Financial amounts, notes, and merchant names are intentionally omitted.
        print("persistence: \(message)")
    }
}
