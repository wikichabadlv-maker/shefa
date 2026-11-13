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
    let maaserDue: Decimal
    let daysLeft: Int

    var incomeIsEstimate: Bool { income > incomeSoFar }

    /// What the month leaves for everyday life after fixed costs, maaser and savings.
    var livingBudget: Decimal {
        income - fixed - max(maaserDue, maaserGiven) - saved
    }

    /// What is still free to spend this month.
    var remaining: Decimal { livingBudget - variableSpent - onceSpent }

    var perWeek: Decimal {
        let weeks = max(1, Int((Double(daysLeft) / 7).rounded(.up)))
        return max(remaining, 0) / Decimal(weeks)
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
        }

        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysLeft = isCurrentMonth ? daysInMonth - calendar.component(.day, from: .now) + 1 : 0
        return MonthSummary(
            income: income, incomeSoFar: current.income, fixed: fixed, fixedPaid: current.fixed,
            variableSpent: current.variable, onceSpent: current.once, saved: current.saved,
            maaserGiven: current.maaser, maaserDue: income / 10, daysLeft: daysLeft)
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

    /// Fills the journal with example lines the first time the app opens,
    /// until real data arrives from the bank sync.
    static func seedIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<LedgerEntry>())) ?? 0
        guard count == 0 else { return }
        for entry in SampleData.entries() {
            context.insert(entry)
        }
        try? context.save()
    }
}
