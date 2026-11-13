import Foundation

extension Decimal {
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension Ledger {
    /// A real expense: money out that is not a transfer or a savings deposit.
    static func isSpending(_ entry: LedgerEntry) -> Bool {
        entry.amount < 0 && !SpendCategory.notSpending.contains(entry.categoryID ?? "")
    }

    /// Spending in one month, by group.
    static func groupTotals(_ entries: [LedgerEntry], _ month: Date) -> [String: Decimal] {
        var sums: [String: Decimal] = [:]
        for entry in inMonth(entries, month) where isSpending(entry) {
            sums[entry.categoryID ?? SpendCategory.unknown.id, default: 0] -= entry.amount
        }
        return sums
    }

    /// Money in and money out for one month.
    static func flow(_ entries: [LedgerEntry], _ month: Date) -> (income: Decimal, spent: Decimal) {
        var income = Decimal(0)
        var spent = Decimal(0)
        for entry in inMonth(entries, month) {
            if entry.categoryID == SpendCategory.transferID { continue }
            if entry.amount > 0 {
                income += entry.amount
            } else if isSpending(entry) {
                spent -= entry.amount
            }
        }
        return (income, spent)
    }

    /// Up to `count` months before `month` that have any lines.
    static func earlierMonths(_ entries: [LedgerEntry], before month: Date, count: Int = 3) -> [Date] {
        var result: [Date] = []
        for back in 1...max(count, 1) {
            guard let date = Calendar.current.date(byAdding: .month, value: -back, to: month) else { continue }
            if !inMonth(entries, date).isEmpty { result.append(date) }
        }
        return result
    }

    static func monthName(_ date: Date, short: Bool = false) -> String {
        date.formatted(Date.FormatStyle(locale: hebrew).month(short ? .abbreviated : .wide))
    }
}

/// One short observation about the month, in plain words.
struct Insight: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let text: String
    let artwork: Artwork
    var categoryID: String?
}

/// Turns the month's numbers into a handful of things worth knowing, the way
/// a good adviser would point them out.
enum Insights {
    static func build(entries: [LedgerEntry], month: Date, summary: MonthSummary) -> [Insight] {
        var result: [Insight] = []
        let now = flow(entries, month)
        let groups = Ledger.groupTotals(entries, month)
        let total = groups.values.reduce(Decimal(0), +)

        // 1. The month's balance.
        if now.income > 0 || now.spent > 0 {
            let net = now.income - now.spent
            result.append(Insight(
                id: "balance", symbol: net >= 0 ? "arrow.up.right" : "arrow.down.right",
                title: net >= 0 ? "חודש חיובי: \(Money.text(net, showPlus: true))" : "חודש בגירעון: \(Money.text(net))",
                text: "נכנסו \(Money.text(now.income)) ויצאו \(Money.text(now.spent))",
                artwork: net >= 0 ? Theme.green : Theme.pink))
        }

        // 2. Compared with the usual.
        let earlier = Ledger.earlierMonths(entries, before: month)
        if !earlier.isEmpty {
            var averages: [String: Decimal] = [:]
            for date in earlier {
                for (key, value) in Ledger.groupTotals(entries, date) {
                    averages[key, default: 0] += value
                }
            }
            for key in averages.keys {
                averages[key] = (averages[key] ?? 0) / Decimal(earlier.count)
            }
            let rises = groups
                .compactMap { key, value -> (String, Decimal, Decimal)? in
                    let usual = averages[key] ?? 0
                    guard usual > 0, value - usual >= 100, value >= usual * Decimal(1.3) else { return nil }
                    return (key, value, usual)
                }
                .sorted { $0.1 - $0.2 > $1.1 - $1.2 }
            if let rise = rises.first, let category = SpendCategory.find(rise.0) {
                result.append(Insight(
                    id: "rise", symbol: "chart.line.uptrend.xyaxis",
                    title: "\(category.title): מעל הרגיל",
                    text: "\(Money.text(rise.1)) החודש, לעומת ממוצע של \(Money.text(rise.2))",
                    artwork: category.artwork, categoryID: category.id))
            }
            let drops = averages
                .compactMap { key, usual -> (String, Decimal, Decimal)? in
                    let value = groups[key] ?? 0
                    guard usual >= 200, usual - value >= 100, value <= usual * Decimal(0.7) else { return nil }
                    return (key, value, usual)
                }
                .sorted { $0.2 - $0.1 > $1.2 - $1.1 }
            if summary.daysLeft <= 0, let drop = drops.first, let category = SpendCategory.find(drop.0) {
                result.append(Insight(
                    id: "drop", symbol: "chart.line.downtrend.xyaxis",
                    title: "\(category.title): פחות מהרגיל",
                    text: "\(Money.text(drop.1)), לעומת ממוצע של \(Money.text(drop.2))",
                    artwork: Theme.emerald, categoryID: category.id))
            }
        }

        // 3. Where most of it went.
        if let top = groups.max(by: { $0.value < $1.value }), total > 0,
           let category = SpendCategory.find(top.key) {
            let share = Int((top.value / total).double * 100)
            result.append(Insight(
                id: "top", symbol: category.symbol,
                title: "הכי הרבה: \(category.title)",
                text: "\(Money.text(top.value)), שהם \(share)% מההוצאות",
                artwork: category.artwork, categoryID: category.id))
        }

        // 4. Maaser.
        if summary.maaserDue > 0 {
            let left = max(summary.maaserDue - summary.maaserGiven, 0)
            result.append(Insight(
                id: "maaser", symbol: "heart.fill",
                title: left > 0 ? "\(Money.text(left)) ממתינים לנתינה" : "המעשר של החודש ניתן",
                text: "ניתנו \(Money.text(summary.maaserGiven)) מתוך \(Money.text(summary.maaserDue))",
                artwork: Theme.amber, categoryID: SpendCategory.maaserID))
        }

        // 5. Savings rate.
        if now.income > 0 {
            let rate = Int(((now.income - now.spent) / now.income).double * 100)
            if rate > 0 {
                result.append(Insight(
                    id: "rate", symbol: "leaf.fill",
                    title: "נשארו \(rate)% מההכנסות",
                    text: "מתכנני פיננסים ממליצים לשאוף ל־10% עד 20%",
                    artwork: Theme.emerald))
            }
        }

        // 6. One-time expenses.
        if summary.onceSpent > 0 {
            result.append(Insight(
                id: "once", symbol: "sparkles",
                title: "חד פעמיות: \(Money.text(summary.onceSpent))",
                text: "הן לא נכנסות לממוצע החודשי שלכם",
                artwork: Artwork(0xD97706, 0x92400E)))
        }

        // 7. Waiting questions.
        let questions = Ledger.inMonth(entries, month).filter(\.needsAnswer).count
        if questions > 0 {
            result.append(Insight(
                id: "questions", symbol: "questionmark.bubble.fill",
                title: questions == 1 ? "תנועה אחת מחכה לבירור" : "\(questions) תנועות מחכות לבירור",
                text: "כמה שניות, והתמונה מדויקת יותר",
                artwork: Theme.blue))
        }

        // 8. The year so far.
        let calendar = Calendar.current
        if let year = calendar.dateInterval(of: .year, for: month) {
            var income = Decimal(0)
            var spent = Decimal(0)
            for entry in entries where entry.date >= year.start && entry.date < year.end {
                if entry.categoryID == SpendCategory.transferID { continue }
                if entry.amount > 0 { income += entry.amount } else if Ledger.isSpending(entry) { spent -= entry.amount }
            }
            if income > 0 || spent > 0 {
                let net = income - spent
                result.append(Insight(
                    id: "year", symbol: "calendar",
                    title: "מתחילת השנה: \(Money.text(net, showPlus: true))",
                    text: "הכנסות \(Money.text(income)), הוצאות \(Money.text(spent))",
                    artwork: Theme.violet))
            }
        }
        return result
    }

    private static func flow(_ entries: [LedgerEntry], _ month: Date) -> (income: Decimal, spent: Decimal) {
        Ledger.flow(entries, month)
    }
}
