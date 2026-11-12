import Foundation

/// Formats shekel amounts so that they always read left to right inside
/// Hebrew text, with the sign first and the shekel sign before the digits.
enum Money {
    private static func formatter(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter
    }

    /// The digits alone, for example "9,080".
    static func digits(_ amount: Decimal, fractionDigits: Int = 0) -> String {
        let magnitude = amount < 0 ? -amount : amount
        return formatter(fractionDigits: fractionDigits)
            .string(from: magnitude as NSDecimalNumber) ?? "\(magnitude)"
    }

    /// A full amount, for example "₪9,080" or "−₪284.60".
    static func text(_ amount: Decimal, fractionDigits: Int = 0, showPlus: Bool = false) -> String {
        let sign = amount < 0 ? "−" : (showPlus && amount > 0 ? "+" : "")
        return "\u{2066}\(sign)₪\(digits(amount, fractionDigits: fractionDigits))\u{2069}"
    }
}
