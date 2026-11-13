import Foundation

/// A time of the year that costs more than an ordinary month. Putting a
/// little aside every month turns it from a surprise into a plan.
struct Occasion: Identifiable, Hashable {
    let id: String
    let title: String
    /// How the fund for it is named.
    let fund: String
    let symbol: String
    let palette: Int
    /// The month and the day, in the Hebrew calendar unless `isCivil` is set.
    /// Hebrew months are counted from Tishrei; Adar is 7, Nisan 8, Sivan 10.
    let month: Int
    let day: Int
    var isCivil = false

    static let all: [Occasion] = [
        Occasion(id: "tishrei", title: "חגי תשרי", fund: "קופת חגי תשרי", symbol: "leaf.fill", palette: 4, month: 1, day: 1),
        Occasion(id: "kislev19", title: "י״ט כסלו", fund: "קופת י״ט כסלו", symbol: "book.fill", palette: 7, month: 3, day: 19),
        Occasion(id: "chanukah", title: "חנוכה", fund: "קופת חנוכה", symbol: "flame.fill", palette: 6, month: 3, day: 25),
        Occasion(id: "purim", title: "פורים", fund: "קופת פורים", symbol: "gift.fill", palette: 2, month: 7, day: 14),
        Occasion(id: "pesach", title: "פסח", fund: "קופת פסח", symbol: "sparkles", palette: 0, month: 8, day: 15),
        Occasion(id: "shavuot", title: "שבועות", fund: "קופת שבועות", symbol: "mountain.2.fill", palette: 3, month: 10, day: 6),
        Occasion(id: "summer", title: "הקיץ והקייטנות", fund: "קופת הקיץ", symbol: "sun.max.fill", palette: 5,
                 month: 7, day: 1, isCivil: true),
        Occasion(id: "school", title: "פתיחת שנת הלימודים", fund: "קופת שנת הלימודים", symbol: "graduationcap.fill",
                 palette: 1, month: 9, day: 1, isCivil: true),
    ]

    static func find(_ id: String) -> Occasion? {
        all.first { $0.id == id }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: isCivil ? .gregorian : .hebrew)
        calendar.timeZone = .current
        return calendar
    }

    private func date(year: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    /// The next time it comes, today included.
    func next(after now: Date = .now) -> Date? {
        let today: Date = Calendar.current.startOfDay(for: now)
        let year: Int = calendar.component(.year, from: now)
        for offset in 0...1 {
            if let date = date(year: year + offset), date >= today { return date }
        }
        return nil
    }

    /// The last time it came.
    func previous(before now: Date = .now) -> Date? {
        let today: Date = Calendar.current.startOfDay(for: now)
        let year: Int = calendar.component(.year, from: now)
        for offset in [0, -1] {
            if let date = date(year: year + offset), date < today { return date }
        }
        return nil
    }

    /// The day the money should be ready: two weeks before.
    func deadline(after now: Date = .now) -> Date? {
        guard let date = next(after: now) else { return nil }
        let ready: Date = Calendar.current.date(byAdding: .day, value: -14, to: date) ?? date
        return max(ready, now)
    }

    /// What this time of the year cost above an ordinary month the last
    /// time, by the family's own records. Nil when the records do not reach
    /// that far or show nothing unusual.
    func suggestedTarget(_ entries: [LedgerEntry], now: Date = .now) -> Decimal? {
        let calendar = Calendar.current
        guard let last = previous(before: now),
              // Most of the buying is done in the days before.
              let heavy = calendar.date(byAdding: .day, value: -10, to: last) else { return nil }
        let spent: Decimal = Ledger.flow(entries, heavy).spent
        guard spent > 0 else { return nil }
        var others: [Decimal] = []
        for shift in -5...5 where shift != 0 {
            guard let month = calendar.date(byAdding: .month, value: shift, to: heavy), month < now else { continue }
            let value: Decimal = Ledger.flow(entries, month).spent
            if value > 0 { others.append(value) }
        }
        guard others.count >= 3 else { return nil }
        let sorted: [Decimal] = others.sorted()
        let usual: Decimal = sorted[sorted.count / 2]
        let extra: Decimal = spent - usual
        guard extra >= 200 else { return nil }
        return Decimal((extra.double / 100).rounded() * 100)
    }
}
