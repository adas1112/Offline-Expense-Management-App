import Foundation

/// Decimal money helpers. Amounts are rounded with banker's rounding to the currency's minor units.
enum Money {
    static let maximumAmount = Decimal(string: "9999999999.99") ?? 9_999_999_999.99

    static func minorUnits(for currencyCode: String) -> Int {
        switch currencyCode.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF":
            return 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            return 3
        default:
            return 2
        }
    }

    static func rounded(_ value: Decimal, currencyCode: String) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, minorUnits(for: currencyCode), .bankers)
        return output
    }

    static func exportString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 18
        formatter.decimalSeparator = "."
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    static func isUsableAmount(_ value: Decimal) -> Bool {
        !value.isNaN && value > 0 && value <= maximumAmount
    }
}

enum AmountParser {
    static func parse(_ raw: String, currencyCode: String) -> Decimal? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: " ", with: "")
        text = text.replacingOccurrences(of: "'", with: "")

        let lastComma = text.lastIndex(of: ",")
        let lastDot = text.lastIndex(of: ".")
        if let lastComma, let lastDot {
            if lastComma > lastDot {
                text = text.replacingOccurrences(of: ".", with: "")
                text = text.replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
        } else if text.contains(",") {
            text = text.replacingOccurrences(of: ",", with: ".")
        }

        let cleaned = text.filter { $0.isNumber || $0 == "." }
        guard cleaned == text || cleaned == text.filter({ !$0.isWhitespace }) else { return nil }
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        guard !value.isNaN, value > 0, value <= Money.maximumAmount else { return nil }
        let rounded = Money.rounded(value, currencyCode: currencyCode)
        guard rounded > 0 else { return nil }
        return rounded
    }
}
