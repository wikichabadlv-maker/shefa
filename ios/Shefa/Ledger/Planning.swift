import Foundation
import SwiftData

/// The monthly spending limit the family set for one category.
@Model
final class BudgetLine {
    @Attribute(.unique) var categoryID: String
    var limit: Decimal

    init(categoryID: String, limit: Decimal) {
        self.categoryID = categoryID
        self.limit = limit
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

    static func seedPlanningIfNeeded(in context: ModelContext) {
        if ((try? context.fetchCount(FetchDescriptor<BudgetLine>())) ?? 0) == 0 {
            let limits: [(String, Decimal)] = [
                ("food", 4_500), ("home", 2_800), ("transport", 1_400), ("kids", 2_000),
                ("health", 500), ("clothing", 600), ("shabbat", 900), ("gift", 500),
                ("maaser", 0), ("other", 1_300),
            ]
            for (id, limit) in limits where limit > 0 {
                context.insert(BudgetLine(categoryID: id, limit: limit))
            }
        }
        if ((try? context.fetchCount(FetchDescriptor<SavingsGoal>())) ?? 0) == 0 {
            let now = Date.now
            context.insert(SavingsGoal(title: "דירה משלנו", saved: 48_000, target: 200_000,
                                       symbol: "house.fill", palette: 0, createdAt: now.addingTimeInterval(-3)))
            context.insert(SavingsGoal(title: "בר מצווה", saved: 12_300, target: 30_000,
                                       symbol: "star.fill", palette: 1, createdAt: now.addingTimeInterval(-2)))
            context.insert(SavingsGoal(title: "חופשת קיץ", saved: 3_100, target: 8_000,
                                       symbol: "sun.max.fill", palette: 2, createdAt: now.addingTimeInterval(-1)))
        }
        try? context.save()
    }
}
