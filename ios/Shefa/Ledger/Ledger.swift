import Foundation
import SwiftData

/// The month in one picture: what came in, what is committed, and what is
/// left to live on.
struct MonthSummary {
    /// Income for the month. Early in the month this is the larger of what
    /// already arrived and the recent monthly average.
    let income: Decimal
    let incomeSoFar: Decimal
    /// Fixed costs, estimated the same way as income.
    let fixed: Decimal
    let fixedPaid: Decimal
    let variableSpent: Decimal
    let onceSpent: Decimal
    let saved: Decimal
    let maaserGiven: Decimal
    /// The maaser of the income that has actually arrived.
    let maaserDue: Decimal
    /// The maaser the month's plan keeps aside: that of the whole income the
    /// month is planned on.
    let maaserReserve: Decimal
    let daysLeft: Int
    /// The house salary, when the family set one and this is the current month.
    let salary: Decimal
    /// How much of the month has passed, from 0 to 1.
    let passed: Double

    var incomeIsEstimate: Bool { income > incomeSoFar }

    /// What arrived above the house salary. It stays in the bank as a
    /// cushion for leaner months and is not part of the month's plan.
    var surplus: Decimal { salary > 0 ? max(incomeSoFar - salary, 0) : 0 }

    /// Maaser as the month's plan carries it. Giving out of income above the
    /// house salary is not charged to the plan.
    var maaserInPlan: Decimal { max(maaserReserve, maaserGiven - surplus) }

    /// What the month leaves for everyday life after fixed costs, maaser and savings.
    var livingBudget: Decimal {
        income - fixed - maaserInPlan - saved
    }

    /// What is still free to spend this month.
    var remaining: Decimal { livingBudget - variableSpent - onceSpent }

    var perWeek: Decimal {
        let weeks = max(1, Int((Double(daysLeft) / 7).rounded(.up)))
        return max(remaining, 0) / Decimal(weeks)
    }

    var perDay: Decimal { max(remaining, 0) / Decimal(max(daysLeft, 1)) }

    /// How the month stands, in one of three plain states.
    enum Mood { case calm, watch, over }

    var mood: Mood {
        if remaining < 0 { return .over }
        guard daysLeft > 0, livingBudget > 0, passed > 0.1 else { return .calm }
        return spentShare > passed + 0.15 ? .watch : .calm
    }

    var totalSpent: Decimal { fixedPaid + variableSpent + onceSpent + maaserGiven }

    var spentShare: Double {
        guard livingBudget > 0 else { return remaining < 0 ? 1 : 0 }
        let share = NSDecimalNumber(decimal: (variableSpent + onceSpent) / livingBudget).doubleValue
        return min(max(share, 0), 1)
    }
}

struct LedgerDay: Identifiable {
    let id: Date
    let entries: [LedgerEntry]

    var total: Decimal { entries.reduce(Decimal(0)) { $0 + $1.amount } }

    /// For example "היום · חמישי" or "8 בנובמבר · ראשון".
    var title: String {
        let calendar = Calendar.current
        if entries.allSatisfy({ $0.source == ExcelImport.source }) {
            return "סיכום החודש מקובץ התקציב"
        }
        let weekday = id.formatted(Date.FormatStyle(locale: Ledger.hebrew).weekday(.wide))
            .replacingOccurrences(of: "יום ", with: "")
        if calendar.isDateInToday(id) { return "היום · \(weekday)" }
        if calendar.isDateInYesterday(id) { return "אתמול · \(weekday)" }
        let day = id.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide))
        return "\(day) · \(weekday)"
    }
}

/// The rules of the money journal: grouping, monthly totals, and learning
/// from the user's answers about unclear purchases.
enum Ledger {
    static let hebrew = Locale(identifier: "he_IL")

    /// A number of days in words: "יום אחד", "יומיים" or "17 ימים".
    static func daysText(_ count: Int) -> String {
        switch count {
        case 1: return "יום אחד"
        case 2: return "יומיים"
        default: return "\(count) ימים"
        }
    }

    /// A day of the year in words, for example "10 בדצמבר".
    static func dayText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: hebrew).day().month(.wide))
    }

    /// The merchant name without branch numbers, used to match similar purchases.
    static func merchantKey(_ title: String) -> String {
        let kept = title.unicodeScalars.filter { !CharacterSet.decimalDigits.contains($0) }
        return String(String.UnicodeScalarView(kept))
            .split(separator: " ")
            .joined(separator: " ")
            .lowercased()
    }

    static func inMonth(_ entries: [LedgerEntry], _ month: Date) -> [LedgerEntry] {
        entries.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    static func days(_ entries: [LedgerEntry]) -> [LedgerDay] {
        let groups = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        return groups
            .map { LedgerDay(id: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.id > $1.id }
    }

    private struct MonthTotals {
        var income = Decimal(0)
        var fixed = Decimal(0)
        var variable = Decimal(0)
        var once = Decimal(0)
        var maaser = Decimal(0)
        var saved = Decimal(0)
    }

    private static func totals(_ entries: [LedgerEntry]) -> MonthTotals {
        var result = MonthTotals()
        for entry in entries {
            let category = entry.categoryID ?? ""
            if category == SpendCategory.transferID { continue }
            if entry.amount > 0 {
                result.income += entry.amount
            } else if category == SpendCategory.maaserID {
                result.maaser -= entry.amount
            } else if category == SpendCategory.savingsID {
                result.saved -= entry.amount
            } else {
                switch entry.nature {
                case .fixed: result.fixed -= entry.amount
                case .variable: result.variable -= entry.amount
                case .once: result.once -= entry.amount
                }
            }
        }
        return result
    }

    static func summary(_ entries: [LedgerEntry], now: Date = .now) -> MonthSummary {
        let calendar = Calendar.current
        let current = totals(inMonth(entries, now))
        let isCurrentMonth = calendar.isDate(now, equalTo: .now, toGranularity: .month)

        var income = current.income
        var fixed = current.fixed
        var salary = Decimal(0)
        if isCurrentMonth {
            // Compare with up to three earlier months that have any activity.
            var earlier: [MonthTotals] = []
            for back in 1...3 {
                guard let month = calendar.date(byAdding: .month, value: -back, to: now) else { continue }
                let lines = inMonth(entries, month)
                if !lines.isEmpty { earlier.append(totals(lines)) }
            }
            if !earlier.isEmpty {
                let count = Decimal(earlier.count)
                income = max(income, earlier.reduce(Decimal(0)) { $0 + $1.income } / count)
                fixed = max(fixed, earlier.reduce(Decimal(0)) { $0 + $1.fixed } / count)
            }
            // A house salary keeps the month's plan steady whatever arrives.
            salary = FinancePlan.shared.salary
            if salary > 0 { income = salary }
        }

        let book = MaaserBook()
        let lines = inMonth(entries, now)
        let due: Decimal = book.due(lines)
        var reserve: Decimal = due
        if isCurrentMonth, !book.recordOnly {
            // The plan keeps aside the maaser of the whole planned income,
            // in the proportion that this family's income counts for maaser.
            let share: Decimal = current.income > 0 ? book.base(lines) / current.income : 1
            reserve = income * share * book.rate
        }

        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let today = calendar.component(.day, from: .now)
        let daysLeft = isCurrentMonth ? daysInMonth - today + 1 : 0
        return MonthSummary(
            income: income, incomeSoFar: current.income, fixed: fixed, fixedPaid: current.fixed,
            variableSpent: current.variable, onceSpent: current.once, saved: current.saved,
            maaserGiven: current.maaser, maaserDue: due, maaserReserve: reserve, daysLeft: daysLeft,
            salary: salary, passed: isCurrentMonth ? Double(today) / Double(daysInMonth) : 1)
    }

    /// What came in during each of the months before this one, the nearest
    /// first, skipping months with no income on record.
    static func incomeHistory(_ entries: [LedgerEntry], before month: Date = .now,
                              count: Int = 12) -> [(month: Date, income: Decimal)] {
        var result: [(month: Date, income: Decimal)] = []
        for back in 1...max(count, 1) {
            guard let date = Calendar.current.date(byAdding: .month, value: -back, to: month) else { continue }
            let income: Decimal = flow(entries, date).income
            if income > 0 { result.append((date, income)) }
        }
        return result
    }

    /// A cautious steady monthly figure for a family whose income moves: in
    /// about three months out of four, at least this much came in.
    static func suggestedSalary(_ entries: [LedgerEntry], now: Date = .now) -> Decimal? {
        let incomes: [Decimal] = incomeHistory(entries, before: now).map { $0.income }.sorted()
        guard incomes.count >= 3 else { return nil }
        let index: Int = Int((Double(incomes.count - 1) * 0.25).rounded(.down))
        return Decimal((incomes[index].double / 100).rounded(.down) * 100)
    }

    /// Records the user's answer, remembers it for this merchant, and applies
    /// it to other unanswered purchases at the same merchant.
    static func answer(_ entry: LedgerEntry, with category: SpendCategory, sub: SubCategory? = nil,
                       in context: ModelContext) {
        let key = merchantKey(entry.title)
        entry.categoryID = category.id
        entry.subID = sub?.id
        entry.subTitle = sub?.title
        var answered = [entry.id]

        let rules = (try? context.fetch(FetchDescriptor<MerchantRule>())) ?? []
        if let rule = rules.first(where: { $0.merchant == key }) {
            rule.categoryID = category.id
            rule.subID = sub?.id
            rule.subTitle = sub?.title
        } else {
            context.insert(MerchantRule(merchant: key, categoryID: category.id,
                                        subID: sub?.id, subTitle: sub?.title))
        }

        let others = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        for other in others where other.categoryID == nil && other.amount < 0 && merchantKey(other.title) == key {
            other.categoryID = category.id
            other.subID = sub?.id
            other.subTitle = sub?.title
            answered.append(other.id)
        }
        try? context.save()

        let categoryID = category.id
        let subID = sub?.id
        let ids = answered
        Task { @MainActor in
            for id in ids {
                await Backend.shared.saveAnswer(entryID: id, categoryID: categoryID, subID: subID)
            }
        }
    }
}
