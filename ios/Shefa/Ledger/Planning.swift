import Foundation
import SwiftData

/// The monthly spending limit the family set for one category.
@Model
final class BudgetLine {
    @Attribute(.unique) var categoryID: String
    var limit: Decimal
    var updatedAt: Date = Date.now

    init(categoryID: String, limit: Decimal, updatedAt: Date = .now) {
        self.categoryID = categoryID
        self.limit = limit
        self.updatedAt = updatedAt
    }
}

/// Something the family saves toward.
@Model
final class SavingsGoal {
    @Attribute(.unique) var id: String
    var title: String
    var saved: Decimal
    var target: Decimal
    var symbol: String
    var palette: Int
    var createdAt: Date
    var updatedAt: Date = Date.now
    var removed: Bool = false

    init(id: String = UUID().uuidString, title: String, saved: Decimal = 0, target: Decimal,
         symbol: String = "star.fill", palette: Int = 0, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.saved = saved
        self.target = target
        self.symbol = symbol
        self.palette = palette
        self.createdAt = createdAt
    }

    static let palettes: [Artwork] = [Theme.blue, Theme.violet, Theme.pink, Theme.emerald, Theme.amber]

    var artwork: Artwork {
        SavingsGoal.palettes[abs(palette) % SavingsGoal.palettes.count]
    }

    var share: Double {
        guard target > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: saved / target).doubleValue, 0), 1)
    }
}

extension Ledger {
    static func totalBudget(_ lines: [BudgetLine]) -> Decimal {
        lines.reduce(Decimal(0)) { $0 + $1.limit }
    }

    /// How much was spent this month in each category.
    static func spentByCategory(_ entries: [LedgerEntry], now: Date = .now) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        for entry in entries
        where entry.amount < 0 && !SpendCategory.notSpending.contains(entry.categoryID ?? "")
            && Calendar.current.isDate(entry.date, equalTo: now, toGranularity: .month) {
            result[entry.categoryID ?? SpendCategory.unknown.id, default: 0] -= entry.amount
        }
        return result
    }

    /// Parses what the user typed as an amount, for example "1,200" or "350.5".
    static func amount(from text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "₪", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US")), value >= 0 else {
            return nil
        }
        return value
    }

    /// A starting budget from the family's own recent spending: the average
    /// of up to three earlier months, without one-time expenses, rounded up.
    static func suggestedBudget(_ entries: [LedgerEntry], now: Date = .now) -> [String: Decimal] {
        let calendar = Calendar.current
        var months: [[LedgerEntry]] = []
        for back in 1...3 {
            guard let month = calendar.date(byAdding: .month, value: -back, to: now) else { continue }
            let lines = inMonth(entries, month)
            if !lines.isEmpty { months.append(lines) }
        }
        if months.isEmpty { months = [inMonth(entries, now)] }

        var sums: [String: Decimal] = [:]
        for lines in months {
            for entry in lines where entry.amount < 0 && entry.nature != .once {
                guard let category = entry.categoryID,
                      SpendCategory.spending.contains(where: { $0.id == category }) else { continue }
                sums[category, default: 0] -= entry.amount
            }
        }
        var result: [String: Decimal] = [:]
        for (category, sum) in sums {
            let average = NSDecimalNumber(decimal: sum / Decimal(months.count)).doubleValue
            result[category] = Decimal((average / 50).rounded(.up) * 50)
        }
        return result
    }

    static func seedPlanningIfNeeded(in context: ModelContext) {
        if ((try? context.fetchCount(FetchDescriptor<SavingsGoal>())) ?? 0) == 0 {
            let now = Date.now
            let examples: [(String, Decimal, Decimal, String)] = [
                ("דירה משלנו", 48_000, 200_000, "house.fill"),
                ("בר מצווה", 12_300, 30_000, "star.fill"),
                ("חופשת קיץ", 3_100, 8_000, "sun.max.fill"),
            ]
            for (index, example) in examples.enumerated() {
                let goal = SavingsGoal(
                    id: "example-goal-\(index)", title: example.0, saved: example.1, target: example.2,
                    symbol: example.3, palette: index,
                    createdAt: now.addingTimeInterval(Double(index - examples.count)))
                goal.updatedAt = SharedSync.untouched
                context.insert(goal)
            }
        }
        try? context.save()
    }
}
