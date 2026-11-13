import Foundation

/// The three things that would make this week a good one. They are tasks
/// like any other; what is kept here is only which of them were named for
/// the week, so that every morning can ask about them first and the week
/// can be seen getting done. Kept on this phone, and backed up with the
/// rest of what the app has learned.
enum WeekFocus {
    /// Three, and no more: a fourth comes in only in place of another.
    static let limit = 3
    private static let key = "coach.week"
    private static let skipKey = "coach.weekSkipped"

    private static var store: UserDefaults { .standard }

    /// The Sunday on which the week of a moment begins. Once Shabbat is
    /// out, the evening already belongs to the week that is coming.
    static func start(for now: Date = .now) -> Date {
        let calendar = Calendar.current
        let today: Date = calendar.startOfDay(for: now)
        let weekday: Int = calendar.component(.weekday, from: today)
        if weekday == 7, !Notifier.isHolyTime(now) {
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
        return calendar.date(byAdding: .day, value: 1 - weekday, to: today) ?? today
    }

    /// The evening after Shabbat looks at a week that has not begun yet.
    static func isComing(now: Date = .now) -> Bool {
        start(for: now) > now
    }

    private static func weekKey(_ now: Date) -> String { DayKey.of(start(for: now)) }

    private static var weeks: [String: [String]] {
        store.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }

    /// The tasks named for the week of a moment, in the order they were named.
    static func ids(now: Date = .now) -> [String] {
        weeks[weekKey(now)] ?? []
    }

    /// The same, as the tasks stand now. One that was deleted since is left out.
    static func tasks(in items: [ListItem], now: Date = .now) -> [ListItem] {
        ids(now: now).compactMap { id in items.first { $0.id == id && !$0.removed } }
    }

    static func set(_ ids: [String], now: Date = .now) {
        var all: [String: [String]] = weeks
        all[weekKey(now)] = Array(ids.prefix(limit))
        // A couple of months back is enough to keep.
        for old in all.keys.sorted().dropLast(9) { all[old] = nil }
        store.set(all, forKey: key)
        AppRouter.shared.weekTurn += 1
    }

    /// The family said this week goes without: the offer is not made again.
    static func skip(now: Date = .now) {
        store.set(weekKey(now), forKey: skipKey)
        AppRouter.shared.weekTurn += 1
    }

    /// Whether to offer the choosing: a week that has none yet, in its first
    /// days, and never from candle lighting until the day is out.
    static func offers(now: Date = .now) -> Bool {
        guard ids(now: now).isEmpty, store.string(forKey: skipKey) != weekKey(now),
              !Notifier.isHolyTime(now) else { return false }
        let weekday: Int = Calendar.current.component(.weekday, from: now)
        return weekday <= 3 || weekday == 7
    }

    // MARK: In words

    /// "דבר אחד", "שני דברים", "שלושה דברים".
    static func count(_ number: Int) -> String {
        switch number {
        case 1: return "דבר אחד"
        case 2: return "שני דברים"
        case 3: return "שלושה דברים"
        default: return "\(number) דברים"
        }
    }

    /// How far the week's things got, in one short line.
    static func line(done: Int, of total: Int) -> String {
        if total > 0, done >= total { return "השבוע הזה כבר טוב." }
        if done == 0 { return count(total) + ", והשבוע טוב." }
        return done == 1 ? "אחד מתוך \(total) נעשה." : "\(done) מתוך \(total) נעשו."
    }
}
