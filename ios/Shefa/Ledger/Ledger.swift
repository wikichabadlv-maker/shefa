import Foundation
import SwiftData

struct MonthSummary {
    let budget: Decimal
    let remaining: Decimal
    let daysLeft: Int
    let income: Decimal
    let saved: Decimal
    let maaserGiven: Decimal
    let maaserDue: Decimal

    var spentShare: Double {
        guard budget > 0 else { return 0 }
        let share = NSDecimalNumber(decimal: (budget - remaining) / budget).doubleValue
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

    static func summary(_ entries: [LedgerEntry], budget: Decimal = 14_500, now: Date = .now) -> MonthSummary {
        let calendar = Calendar.current
        let month = entries.filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
        let income = month
            .filter { $0.amount > 0 && $0.categoryID != SpendCategory.transferID }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let maaser = month.filter { $0.categoryID == SpendCategory.maaserID }.reduce(Decimal(0)) { $0 - $1.amount }
        let saved = month.filter { $0.categoryID == "savings" }.reduce(Decimal(0)) { $0 - $1.amount }
        let spent = month
            .filter { $0.amount < 0 && !SpendCategory.notSpending.contains($0.categoryID ?? "") }
            .reduce(Decimal(0)) { $0 - $1.amount }
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let isCurrentMonth = calendar.isDate(now, equalTo: .now, toGranularity: .month)
        let daysLeft = isCurrentMonth ? daysInMonth - calendar.component(.day, from: .now) : 0
        return MonthSummary(
            budget: budget, remaining: budget - spent, daysLeft: daysLeft,
            income: income, saved: saved, maaserGiven: maaser, maaserDue: income / 10
        )
    }

    /// Records the user's answer, remembers it for this merchant, and applies
    /// it to other unanswered purchases at the same merchant.
    static func answer(_ entry: LedgerEntry, with category: SpendCategory, in context: ModelContext) {
        let key = merchantKey(entry.title)
        entry.categoryID = category.id
        var answered = [entry.id]

        let rules = (try? context.fetch(FetchDescriptor<MerchantRule>())) ?? []
        if let rule = rules.first(where: { $0.merchant == key }) {
            rule.categoryID = category.id
        } else {
            context.insert(MerchantRule(merchant: key, categoryID: category.id))
        }

        let others = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        for other in others where other.categoryID == nil && other.amount < 0 && merchantKey(other.title) == key {
            other.categoryID = category.id
            answered.append(other.id)
        }
        try? context.save()

        let categoryID = category.id
        let ids = answered
        Task { @MainActor in
            for id in ids {
                await Backend.shared.saveAnswer(entryID: id, categoryID: categoryID)
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
