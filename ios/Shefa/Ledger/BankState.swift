import Foundation
import Observation

/// What the bank sync last reported besides the lines themselves: how much
/// is in each account, and whether each source was reached.
@Observable
final class BankState {
    static let shared = BankState()

    struct Balance: Codable, Identifiable {
        var source: String
        var account: String
        var amount: Double
        var asOf: Date

        var id: String { source + "-" + account }
    }

    struct Run: Codable, Identifiable {
        var source: String
        var ranAt: Date
        var ok: Bool
        var errorType: String?
        var count: Int

        var id: String { source }
    }

    private struct Saved: Codable {
        var balances: [Balance]
        var runs: [Run]
        var lastGood: [String: Date]
        var manual: Balance?
    }

    /// The newest balance of every account.
    private(set) var balances: [Balance] = []
    /// The newest run of every source.
    private(set) var runs: [Run] = []
    /// When each source last answered properly.
    private(set) var lastGood: [String: Date] = [:]
    /// A balance the family typed in, for a phone with no bank feed.
    private(set) var manual: Balance?

    private static let key = "bank.state"

    private init() {
        guard let text = UserDefaults.standard.string(forKey: Self.key),
              let data = text.data(using: .utf8),
              let saved = try? Self.decoder.decode(Saved.self, from: data) else { return }
        balances = saved.balances
        runs = saved.runs
        lastGood = saved.lastGood
        manual = saved.manual
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private func save() {
        let saved = Saved(balances: balances, runs: runs, lastGood: lastGood, manual: manual)
        guard let data = try? Self.encoder.encode(saved), let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: Self.key)
    }

    /// Takes rows as the database returned them, newest first.
    func update(balances rows: [Balance], runs runRows: [Run]) {
        var newest: [String: Balance] = [:]
        for row in rows where newest[row.id] == nil {
            newest[row.id] = row
        }
        if !newest.isEmpty {
            balances = newest.values.sorted { $0.id < $1.id }
        }

        var latest: [String: Run] = [:]
        var good: [String: Date] = lastGood
        for run in runRows {
            if latest[run.source] == nil { latest[run.source] = run }
            if run.ok, run.ranAt > (good[run.source] ?? .distantPast) { good[run.source] = run.ranAt }
        }
        if !latest.isEmpty {
            runs = latest.values.sorted { $0.source < $1.source }
            lastGood = good
        }
        save()
    }

    func setManual(_ amount: Double?) {
        manual = amount.map { Balance(source: "ידני", account: "", amount: $0, asOf: .now) }
        save()
    }

    /// Made-up values for a demo run.
    func fillDemo() {
        let now = Date.now
        balances = [Balance(source: "דיסקונט", account: "4821", amount: 2140, asOf: now.addingTimeInterval(-5400))]
        runs = [
            Run(source: "דיסקונט", ranAt: now.addingTimeInterval(-5400), ok: true, errorType: nil, count: 14),
            Run(source: "כאל", ranAt: now.addingTimeInterval(-5400), ok: true, errorType: nil, count: 9),
        ]
        lastGood = ["דיסקונט": now.addingTimeInterval(-5400), "כאל": now.addingTimeInterval(-5400)]
        manual = nil
    }

    /// The money in the family's bank accounts, and how fresh the figure is.
    /// Card balances are not money in hand, so they are left out.
    var current: (amount: Double, asOf: Date, isManual: Bool)? {
        let accounts = balances.filter { !Forecast.isCard($0.source) }
        let newestBank: Date? = accounts.map(\.asOf).max()
        if let manual, manual.asOf > (newestBank ?? .distantPast) {
            return (manual.amount, manual.asOf, true)
        }
        guard let newestBank else { return nil }
        return (accounts.reduce(0) { $0 + $1.amount }, newestBank, false)
    }

    /// Reads a database time such as "2026-11-13T15:58:40.123456+00:00".
    static func time(_ text: String) -> Date? {
        var cleaned = text
        // Fractions of a second come in any length, and are not needed.
        if let dot = cleaned.firstIndex(of: ".") {
            let rest = cleaned[dot...]
            let end = rest.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) ?? cleaned.endIndex
            cleaned.removeSubrange(dot..<end)
        }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: cleaned)
    }

    /// For example "לפני שעתיים" or "אתמול ב־19:15".
    static func ago(_ date: Date, now: Date = .now) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 2 { return "עכשיו" }
        if minutes < 60 { return "לפני \(minutes) דקות" }
        let hours = minutes / 60
        if hours == 1 { return "לפני שעה" }
        if hours == 2 { return "לפני שעתיים" }
        if hours < 12 { return "לפני \(hours) שעות" }
        let clock = date.formatted(Date.FormatStyle(locale: Ledger.hebrew).hour().minute())
        if Calendar.current.isDateInToday(date) { return "היום ב־\(clock)" }
        if Calendar.current.isDateInYesterday(date) { return "אתמול ב־\(clock)" }
        let day = date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide))
        return "ב־\(day)"
    }
}
