import Foundation

/// Something that is expected to move money in or out of the bank account soon.
struct Upcoming: Identifiable, Hashable {
    enum Kind: String {
        case income, fixed, card, planned
    }

    /// The same for every month of a returning item, so the family can say
    /// once that it will not return.
    let key: String
    let date: Date
    let title: String
    /// Negative for money out.
    let amount: Decimal
    let kind: Kind
    /// False for an estimate from earlier months.
    let isKnown: Bool
    /// A word about where the figure comes from.
    var note: String? = nil
    /// The family's own planned item behind this line, if there is one.
    var plannedID: String? = nil

    var id: String { key + "@" + DayKey.of(date) }

    var symbol: String {
        if amount > 0 { return "banknote.fill" }
        switch kind {
        case .card: return "creditcard.fill"
        case .planned: return "calendar"
        default: return "arrow.triangle.2.circlepath"
        }
    }

    var artwork: Artwork {
        if amount > 0 { return Theme.green }
        return kind == .card ? Theme.blue : Theme.violet
    }
}

/// The bank balance as it is expected to move, day by day.
struct Horizon {
    struct Point: Identifiable {
        let id: Int
        let date: Date
        let balance: Double
    }

    /// When the balance it starts from was read.
    let asOf: Date
    let isManual: Bool
    /// One point a day, from today to the end of next month.
    let points: [Point]
    /// What is expected from today on.
    let events: [Upcoming]
    /// What was expected between the day the balance was read and today, and
    /// is taken to have happened.
    let assumed: [Upcoming]

    var today: Double { points.first?.balance ?? 0 }

    /// The lowest day, the earliest one when several are as low.
    var lowest: Point? { points.min { $0.balance < $1.balance } }

    var firstBelowZero: Point? { points.first { $0.balance < 0 } }

    /// What happens on the lowest day, the largest payment first.
    var lowestCause: Upcoming? {
        guard let lowest else { return nil }
        return events
            .filter { $0.amount < 0 && Calendar.current.isDate($0.date, inSameDayAs: lowest.date) }
            .min { $0.amount < $1.amount }
    }
}

/// Looks ahead: what the bank account is about to be charged and to receive,
/// worked out from the card lines that already arrived, from payments that
/// return every month, and from what the family entered itself.
enum Forecast {
    static let cardSources: Set<String> = ["כאל", "מקס", "ישראכרט", "אמריקן אקספרס", "דיינרס"]

    /// A second card at the same company is named "מקס 2".
    static func isCard(_ source: String) -> Bool {
        cardSources.contains { source.hasPrefix($0) }
    }

    static func isCardLine(_ entry: LedgerEntry) -> Bool { isCard(entry.source) }

    /// A line the bank itself reported, on its real day: not a card purchase,
    /// not typed by hand and not a monthly summary.
    static func isBankLine(_ entry: LedgerEntry) -> Bool {
        !entry.isManual && !entry.isSample && entry.source != ExcelImport.source && !isCard(entry.source)
    }

    // MARK: Days

    /// A day of the month, in the month of `date` or some months away from
    /// it. A day the month does not have becomes its last day.
    static func day(_ day: Int, inMonthOf date: Date, shift: Int = 0) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let first = calendar.date(from: parts),
              let month = calendar.date(byAdding: .month, value: shift, to: first) else { return date }
        let count: Int = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        return calendar.date(byAdding: .day, value: min(max(day, 1), count) - 1, to: month) ?? month
    }

    /// For example "2026-11".
    static func monthKey(_ date: Date) -> String {
        String(DayKey.of(date).prefix(7))
    }

    /// The last day the forecast looks at: the end of next month.
    static func windowEnd(_ now: Date = .now) -> Date {
        let first: Date = day(1, inMonthOf: now, shift: 2)
        return Calendar.current.date(byAdding: .day, value: -1, to: first) ?? now
    }

    private static func median(_ values: [Decimal]) -> Decimal? {
        guard !values.isEmpty else { return nil }
        let sorted: [Decimal] = values.sorted()
        let middle: Int = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    // MARK: Cards

    /// The day of the month on which each card company charges the bank,
    /// judging by the lines it already charged.
    static func billingDays(_ lines: [LedgerEntry]) -> [String: Int] {
        let calendar = Calendar.current
        var counts: [String: [Int: Int]] = [:]
        for entry in lines where isCardLine(entry) && !entry.pending {
            guard let charge = entry.chargeDate, !calendar.isDate(charge, inSameDayAs: entry.date) else { continue }
            counts[entry.source, default: [:]][calendar.component(.day, from: charge), default: 0] += 1
        }
        var result: [String: Int] = [:]
        for (source, days) in counts {
            let best = days.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first
            result[source] = best?.key ?? 10
        }
        return result
    }

    /// The day a card line reaches the bank. A line that is not final yet
    /// carries no such day, so it goes to the card's next billing day.
    static func chargeDay(of entry: LedgerEntry, billingDay: Int) -> Date {
        let calendar = Calendar.current
        if !entry.pending, let charge = entry.chargeDate, !calendar.isDate(charge, inSameDayAs: entry.date) {
            return calendar.startOfDay(for: charge)
        }
        let sameMonth: Date = day(billingDay, inMonthOf: entry.date)
        return sameMonth > calendar.startOfDay(for: entry.date) ? sameMonth : day(billingDay, inMonthOf: entry.date, shift: 1)
    }

    /// The newest payment of every purchase that is paid in monthly
    /// payments. Purchases at the same place with the same number of
    /// payments are told apart by the bill they were last charged on.
    private static func livePayments(_ cards: [LedgerEntry],
                                     billing: [String: Int]) -> [(entry: LedgerEntry, charge: Date)] {
        var families: [String: [(entry: LedgerEntry, charge: Date)]] = [:]
        for entry in cards where entry.isInPayments && entry.amount < 0 {
            let key: String = [entry.source, entry.account ?? "", Ledger.merchantKey(entry.title),
                               String(entry.installments)].joined(separator: "|")
            let charge: Date = chargeDay(of: entry, billingDay: billing[entry.source] ?? 10)
            families[key, default: []].append((entry, charge))
        }
        var result: [(entry: LedgerEntry, charge: Date)] = []
        for family in families.values {
            guard let newest = family.map({ $0.charge }).max() else { continue }
            let month: String = monthKey(newest)
            for item in family where monthKey(item.charge) == month {
                result.append(item)
            }
        }
        return result
    }

    /// A purchase that is still being paid off, month by month.
    struct Commitment: Identifiable {
        let id: String
        let title: String
        let source: String
        /// One payment, as a positive figure.
        let payment: Decimal
        /// How many payments are still to come.
        let left: Int
        let total: Int
        /// The day of the last payment.
        let ends: Date

        var remaining: Decimal { payment * Decimal(left) }
    }

    /// Everything the family still owes on purchases split into payments.
    static func commitments(_ entries: [LedgerEntry], now: Date = .now) -> [Commitment] {
        let calendar = Calendar.current
        let today: Date = calendar.startOfDay(for: now)
        let cards: [LedgerEntry] = entries.filter { !$0.removed && isCardLine($0) }
        let billing: [String: Int] = billingDays(cards)
        var result: [Commitment] = []
        for item in livePayments(cards, billing: billing) {
            let after: Int = item.entry.installments - item.entry.installment
            let number: Int = calendar.component(.day, from: item.charge)
            let ends: Date = day(number, inMonthOf: item.charge, shift: after)
            guard ends > today else { continue }
            // Payments whose day has already passed are behind us.
            var left: Int = 0
            for step in 0...after where day(number, inMonthOf: item.charge, shift: step) > today {
                left += 1
            }
            guard left > 0 else { continue }
            result.append(Commitment(id: item.entry.id, title: item.entry.title, source: item.entry.source,
                                     payment: -item.entry.amount, left: left, total: item.entry.installments,
                                     ends: ends))
        }
        return result.sorted { $0.remaining != $1.remaining ? $0.remaining > $1.remaining : $0.id < $1.id }
    }

    /// One bill of one card.
    private struct Cycle {
        /// The lines that already arrived.
        var sum = Decimal(0)
        /// Payments of earlier purchases that will fall on this bill.
        var extra = Decimal(0)
        var days: [Date: Int] = [:]
    }

    /// The coming bills of the cards whose purchases arrive line by line.
    private static func cardBills(_ lines: [LedgerEntry], patterns: [Pattern], after start: Date,
                                  until end: Date, now: Date) -> [Upcoming] {
        let calendar = Calendar.current
        let today: Date = calendar.startOfDay(for: now)
        let cards: [LedgerEntry] = lines.filter { isCardLine($0) }
        guard !cards.isEmpty else { return [] }
        let billing: [String: Int] = billingDays(cards)

        var cycles: [String: [String: Cycle]] = [:]
        for entry in cards {
            let charge: Date = chargeDay(of: entry, billingDay: billing[entry.source] ?? 10)
            let month: String = monthKey(charge)
            var cycle: Cycle = cycles[entry.source]?[month] ?? Cycle()
            cycle.sum += entry.amount
            cycle.days[charge, default: 0] += 1
            cycles[entry.source, default: [:]][month] = cycle
        }
        for item in livePayments(cards, billing: billing) {
            let after: Int = item.entry.installments - item.entry.installment
            guard after > 0 else { continue }
            let number: Int = calendar.component(.day, from: item.charge)
            for step in 1...after {
                let date: Date = day(number, inMonthOf: item.charge, shift: step)
                if date > end { break }
                let month: String = monthKey(date)
                var cycle: Cycle = cycles[item.entry.source]?[month] ?? Cycle()
                cycle.extra += item.entry.amount
                cycles[item.entry.source, default: [:]][month] = cycle
            }
        }

        var result: [Upcoming] = []
        for (source, months) in cycles {
            // What a usual bill of this card comes to. The bank's own lines
            // are whole bills; the card's lines may start in the middle of one.
            var typical: Decimal? = patterns.first { $0.key == "card|" + source }.map { -$0.typical }
            if typical == nil {
                var closed: [Decimal] = []
                for cycle in months.values {
                    guard let date = cycle.days.keys.max(), date <= today, cycle.sum < 0 else { continue }
                    closed.append(-cycle.sum)
                }
                typical = closed.max()
            }
            for (month, cycle) in months {
                let usual = cycle.days.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key > $1.key }.first
                let date: Date = usual?.key
                    ?? day(billing[source] ?? 10, inMonthOf: DayKey.date(month + "-01") ?? now)
                guard date > start, date <= end else { continue }
                let known: Decimal = -(cycle.sum + cycle.extra)
                // A bill whose day is still ahead can grow with new purchases.
                let isOpen: Bool = date > today
                var amount: Decimal = known
                var isKnown = true
                var note: String? = isOpen ? "לפי מה שנרשם עד עכשיו" : nil
                if isOpen, let typical, typical > known {
                    amount = typical
                    isKnown = false
                    note = known > 0 ? "הערכה לפי חיוב רגיל. עד עכשיו נרשמו \(Money.text(known))" : "הערכה לפי חיוב רגיל"
                }
                guard amount != 0 else { continue }
                result.append(Upcoming(key: "card|" + source, date: date, title: "חיוב \(source)",
                                       amount: -amount, kind: .card, isKnown: isKnown, note: note))
            }
        }
        return result
    }

    // MARK: Returning payments

    /// A payment or an income that returns in the bank account every month.
    private struct Pattern {
        let key: String
        let title: String
        let kind: Upcoming.Kind
        /// Signed like the lines themselves: negative for money out.
        let typical: Decimal
        /// The last time it was seen.
        let last: Date
        /// Its usual day of the month.
        let day: Int
    }

    private static func patterns(_ lines: [LedgerEntry], linked: Set<String>, now: Date) -> [Pattern] {
        let calendar = Calendar.current
        guard let since = calendar.date(byAdding: .day, value: -100, to: now) else { return [] }
        let until: Date = now.addingTimeInterval(86_400)

        var groups: [String: [LedgerEntry]] = [:]
        for entry in lines where isBankLine(entry) && entry.amount != 0 && entry.date >= since && entry.date <= until {
            let key: String
            if entry.amount < 0, Classifier.isCardBill(entry.title) {
                // A bill that names no company belongs to the one connected card.
                let company: String = Classifier.cardCompany(in: entry.title)
                    ?? (linked.count == 1 ? (linked.first ?? "כרטיס אשראי") : "כרטיס אשראי")
                key = "card|" + company
            } else {
                key = "bank|" + Ledger.merchantKey(entry.title) + (entry.amount > 0 ? "|in" : "|out")
            }
            groups[key, default: []].append(entry)
        }

        var result: [Pattern] = []
        for (key, group) in groups {
            let isCardBill: Bool = key.hasPrefix("card|")
            // One occurrence a month: lines of the same month are added up.
            var sums: [String: Decimal] = [:]
            var days: [String: Set<Int>] = [:]
            for entry in group {
                let month: String = monthKey(entry.date)
                sums[month, default: 0] += entry.amount
                days[month, default: []].insert(calendar.component(.day, from: entry.date))
            }
            guard let newest = group.max(by: { $0.date < $1.date }) else { continue }
            let isOnce: Bool = days.values.allSatisfy { $0.count == 1 }
            let isFixed: Bool = group.allSatisfy { $0.nature == .fixed }
            let allDays: [Int] = days.values.flatMap { Array($0) }
            let spread: Int = (allDays.max() ?? 0) - (allDays.min() ?? 0)
            // The end of one month and the start of the next are close too.
            let isNear: Bool = spread <= 6 || spread >= 24
            let sizes: [Decimal] = sums.values.map { $0 < 0 ? -$0 : $0 }
            let smallest: Decimal = sizes.min() ?? 0
            let largest: Decimal = sizes.max() ?? 0
            // Income is guessed with more care than a payment: expecting
            // money that does not come is the worse mistake.
            let ratio: Decimal = (newest.amount > 0 ? Decimal(string: "0.7") : Decimal(string: "0.5")) ?? 1
            let isAlike: Bool = largest > 0 && smallest >= largest * ratio
            let isMonthly: Bool = isOnce && sums.count >= 2 && isNear && isAlike
            guard isCardBill || isMonthly || (isOnce && isFixed) else { continue }

            let recent: [Decimal] = sums.sorted { $0.key > $1.key }.prefix(3).map { $0.value }
            guard let typical = median(recent), typical != 0 else { continue }
            let title: String = isCardBill ? "חיוב " + String(key.dropFirst(5)) : (newest.subTitle ?? newest.title)
            let kind: Upcoming.Kind = isCardBill ? .card : (typical > 0 ? .income : .fixed)
            result.append(Pattern(key: key, title: title, kind: kind, typical: typical, last: newest.date,
                                  day: calendar.component(.day, from: newest.date)))
        }
        return result
    }

    /// The coming days of a returning payment. One that should have come in
    /// the last week and was not seen is taken to be on its way; later than
    /// that, this month's turn is given up.
    private static func occurrences(of pattern: Pattern, after start: Date, until end: Date) -> [Date] {
        let calendar = Calendar.current
        guard let lateLimit = calendar.date(byAdding: .day, value: -7, to: start) else { return [] }
        var result: [Date] = []
        for shift in 1...4 {
            var date: Date = day(pattern.day, inMonthOf: pattern.last, shift: shift)
            if date <= start {
                guard date >= lateLimit else { continue }
                date = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            }
            if date > end { break }
            result.append(date)
        }
        return result
    }

    // MARK: The whole picture

    /// A guess and the family's own planned item are about the same payment.
    private static func isSame(_ mine: Upcoming, _ guess: Upcoming) -> Bool {
        guard (mine.amount > 0) == (guess.amount > 0) else { return false }
        let gap: Int = abs(Calendar.current.dateComponents([.day], from: mine.date, to: guess.date).day ?? 99)
        guard gap <= 6 else { return false }
        if guess.kind == .card, mine.title.contains(String(guess.key.dropFirst(5))) { return true }
        let first: Decimal = mine.amount < 0 ? -mine.amount : mine.amount
        let second: Decimal = guess.amount < 0 ? -guess.amount : guess.amount
        let larger: Decimal = max(first, second)
        let apart: Decimal = first > second ? first - second : second - first
        return larger > 0 && apart <= larger * (Decimal(string: "0.15") ?? 0)
    }

    /// Everything expected after the day of `start` and up to `end`, the
    /// nearest first.
    static func upcoming(_ entries: [LedgerEntry], after start: Date, until end: Date,
                         now: Date = .now, plan: FinancePlan = .shared) -> [Upcoming] {
        let calendar = Calendar.current
        let from: Date = calendar.startOfDay(for: start)
        let lines: [LedgerEntry] = entries.filter { !$0.removed }
        let linked: Set<String> = Set(lines.filter { isCardLine($0) }.map(\.source))
        let found: [Pattern] = patterns(lines, linked: linked, now: now)

        var detected: [Upcoming] = cardBills(lines, patterns: found, after: from, until: end, now: now)
        let billed: Set<String> = Set(detected.map { $0.key + "@" + monthKey($0.date) })
        for pattern in found {
            for date in occurrences(of: pattern, after: from, until: end) {
                if pattern.kind == .card, billed.contains(pattern.key + "@" + monthKey(date)) { continue }
                detected.append(Upcoming(key: pattern.key, date: date, title: pattern.title,
                                         amount: pattern.typical, kind: pattern.kind, isKnown: false,
                                         note: "הערכה לפי החודשים הקודמים"))
            }
        }
        let hidden: Set<String> = plan.hidden
        detected.removeAll { hidden.contains($0.key) }

        var planned: [Upcoming] = []
        for item in plan.planned {
            var dates: [Date] = []
            if item.isMonthly {
                for shift in 0...3 {
                    dates.append(day(item.day, inMonthOf: from, shift: shift))
                }
            } else if let date = item.date {
                dates.append(calendar.startOfDay(for: date))
            }
            for date in dates where date > from && date <= end {
                planned.append(Upcoming(key: "planned|" + item.id, date: date, title: item.title,
                                        amount: item.value, kind: item.amount > 0 ? .income : .planned,
                                        isKnown: true, plannedID: item.id))
            }
        }
        // The family's own word wins over a guess about the same payment.
        detected.removeAll { guess in planned.contains { isSame($0, guess) } }

        return (detected + planned).sorted {
            $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id
        }
    }

    /// The bank balance from today to the end of next month. Nil when no
    /// balance is known, from the bank or typed in.
    static func horizon(_ entries: [LedgerEntry], now: Date = .now, bank: BankState = .shared,
                        plan: FinancePlan = .shared) -> Horizon? {
        guard let current = bank.current else { return nil }
        let calendar = Calendar.current
        let today: Date = calendar.startOfDay(for: now)
        let start: Date = min(calendar.startOfDay(for: current.asOf), today)
        let end: Date = windowEnd(now)
        let events: [Upcoming] = upcoming(entries, after: start, until: end, now: now, plan: plan)

        var changes: [Date: Double] = [:]
        for event in events {
            changes[calendar.startOfDay(for: event.date), default: 0] += event.amount.double
        }
        var points: [Horizon.Point] = []
        var balance: Double = current.amount
        var date: Date = start
        var steps = 0
        while date <= end, steps < 500 {
            if date > start { balance += changes[date] ?? 0 }
            if date >= today {
                points.append(Horizon.Point(id: points.count, date: date, balance: balance))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
            steps += 1
        }
        return Horizon(asOf: current.asOf, isManual: current.isManual, points: points,
                       events: events.filter { $0.date >= today },
                       assumed: events.filter { $0.date < today })
    }
}
