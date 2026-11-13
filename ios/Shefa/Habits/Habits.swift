import SwiftData
import SwiftUI

/// Days the family set aside: a trip, an illness, a simcha. Nothing is
/// expected of the daily practices on such a day, and nothing is counted.
enum OffDays {
    private static let key = "coach.offDays"

    static var all: Set<String> { DayKey.split(UserDefaults.standard.string(forKey: key) ?? "") }

    static func isOff(_ date: Date = .now) -> Bool { all.contains(DayKey.of(date)) }

    static func set(_ isOff: Bool, on date: Date = .now) {
        var days: Set<String> = all
        let day: String = DayKey.of(date)
        if isOff { days.insert(day) } else { days.remove(day) }
        UserDefaults.standard.set(DayKey.join(days, keep: 200), forKey: key)
    }
}

/// A daily practice to keep, such as morning prayers or a fixed study time.
/// Personal to this phone: it is not shared with the other phone.
@Model
final class Habit {
    @Attribute(.unique) var id: String
    var title: String
    var symbol: String
    var palette: Int
    var order: Int
    /// The days it was kept, as `DayKey`s joined by commas.
    var doneDays: String = ""
    var createdAt: Date
    var removed: Bool = false
    /// What it comes after, in the family's own words: "אחרי שחרית". A
    /// practice holds when it leans on something that already happens.
    var anchor: String = ""
    /// The small form that still counts on a hard day: "משנה אחת".
    var small: String = ""
    /// Marked, but never measured or reminded of. The prayers are like this.
    var isQuiet: Bool = false

    init(id: String = UUID().uuidString, title: String, symbol: String, palette: Int, order: Int) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.palette = palette
        self.order = order
        self.createdAt = .now
    }

    var artwork: Artwork {
        SavingsGoal.palettes[abs(palette) % SavingsGoal.palettes.count]
    }

    var days: Set<String> { DayKey.split(doneDays) }

    func isDone(on date: Date = .now) -> Bool { days.contains(DayKey.of(date)) }

    func toggle(on date: Date = .now) {
        var all = days
        let key = DayKey.of(date)
        if all.contains(key) { all.remove(key) } else { all.insert(key) }
        doneDays = DayKey.join(all, keep: 400)
    }

    // MARK: Consistency

    /// How a practice stood on one day.
    enum DayMark {
        case kept
        /// Missed, and covered by the week's one free miss.
        case forgiven
        case missed
        /// Shabbat, a festival, a fast or a day set aside: not counted.
        case free
        /// Before the practice began, today while it is still open, or a day ahead.
        case blank
    }

    /// How steadily a practice is kept over four weeks. One miss a week is
    /// not counted, and neither are days of rest, so a single bad day never
    /// throws the number away.
    struct Strength {
        /// From 0 to 1: the days it was kept, out of the days that count.
        let share: Double
        let kept: Int
        let missed: Int
        /// Misses that the week allowed, and so are not counted.
        let forgiven: Int
        /// Four weeks from Sunday to Shabbat, the current week last.
        let marks: [DayMark]
        /// Where today is among the marks.
        let todayIndex: Int
        /// This week's free miss has not been used.
        let hasReserve: Bool
        /// Kept today after a day that was missed: the moment that matters most.
        let isBack: Bool

        /// The days that count: kept or missed.
        var counted: Int { kept + missed }

        /// Too few days were counted for the number to say anything.
        var isNew: Bool { counted < 3 }

        var percent: String { share.formatted(.percent.precision(.fractionLength(0))) }
    }

    func strength(now: Date = .now) -> Strength {
        let calendar = Calendar.current
        let kept: Set<String> = days
        let off: Set<String> = OffDays.all
        let begins: Date = calendar.startOfDay(for: createdAt)
        let today: Date = calendar.startOfDay(for: now)
        let todayIndex: Int = 21 + calendar.component(.weekday, from: today) - 1
        var marks: [DayMark] = []
        var keptCount = 0
        var missed = 0
        var forgiven = 0
        var weekUsed: [Bool] = [false, false, false, false]
        var lastCounted: DayMark?
        for index in 0..<28 {
            guard index <= todayIndex,
                  let day = calendar.date(byAdding: .day, value: index - todayIndex, to: today) else {
                marks.append(.blank)
                continue
            }
            let key: String = DayKey.of(day)
            var mark: DayMark = .missed
            if kept.contains(key) {
                mark = .kept
            } else if day < begins || index == todayIndex {
                mark = .blank
            } else if off.contains(key) || JewishDay.of(day).isNeutral {
                mark = .free
            } else if !weekUsed[index / 7] {
                // The first miss of a week is the one the week allows.
                weekUsed[index / 7] = true
                mark = .forgiven
            }
            switch mark {
            case .kept: keptCount += 1
            case .forgiven: forgiven += 1
            case .missed: missed += 1
            case .free, .blank: break
            }
            let isCounted: Bool = mark == .kept || mark == .forgiven || mark == .missed
            if index < todayIndex && isCounted { lastCounted = mark }
            marks.append(mark)
        }
        let counted: Int = keptCount + missed
        let share: Double = counted > 0 ? Double(keptCount) / Double(counted) : 0
        let wasMissed: Bool = lastCounted == .missed || lastCounted == .forgiven
        let cameBack: Bool = kept.contains(DayKey.of(today)) && wasMissed
        return Strength(share: share, kept: keptCount, missed: missed, forgiven: forgiven,
                        marks: marks, todayIndex: todayIndex, hasReserve: !weekUsed[3], isBack: cameBack)
    }

    /// The day a mark stands for.
    static func day(at index: Int, in strength: Strength, now: Date = .now) -> Date {
        let calendar = Calendar.current
        let today: Date = calendar.startOfDay(for: now)
        let day: Date = calendar.date(byAdding: .day, value: index - strength.todayIndex, to: today) ?? today
        // Noon, so the day stays the same whatever the hour.
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    /// One number for several practices; nil while there is too little to say.
    static func average(_ all: [Strength]) -> Double? {
        let known: [Strength] = all.filter { !$0.isNew }
        guard !known.isEmpty else { return nil }
        var sum: Double = 0
        for one in known { sum += one.share }
        return sum / Double(known.count)
    }

    /// The consistency of the practices that are measured, taken together.
    static func strength(of habits: [Habit], now: Date = .now) -> Double? {
        average(habits.filter { !$0.removed && !$0.isQuiet }.map { $0.strength(now: now) })
    }

    /// The name of a day that the calendar itself sets apart.
    static func restNote(on day: Date = .now) -> String? {
        let kind: JewishDay = JewishDay.of(day)
        if let yomTov = kind.yomTov { return yomTov }
        if kind.isShabbat { return "שבת קודש" }
        return kind.fast
    }

    /// Why today is not counted, when it is not.
    static func freeNote(on day: Date = .now) -> String? {
        if let rest = restNote(on: day) { return rest }
        return OffDays.isOff(day) ? "יום חריג" : nil
    }

    private static let prayers = ["habit-shacharit", "habit-mincha", "habit-arvit"]
    private static let quietKey = "quietPrayers"

    /// The prayers are marked but not measured, unless the family says
    /// otherwise. Done once for a phone that had them before this was so.
    private static func quietPrayersIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: quietKey) else { return }
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        for habit in habits where prayers.contains(habit.id) { habit.isQuiet = true }
        try? context.save()
        UserDefaults.standard.set(true, forKey: quietKey)
    }

    /// Added later at the family's request: mikveh first in the morning, and
    /// the Chitas pillar named without "and Tehillim".
    private static func addMikvehIfNeeded(in context: ModelContext) {
        let key = "addedMikveh"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        for habit in habits where habit.title == "חת״ת ותהילים" { habit.title = "חת״ת" }
        if !habits.contains(where: { $0.id == "habit-mikveh" }) {
            context.insert(Habit(id: "habit-mikveh", title: "מקווה", symbol: "drop.fill", palette: 5, order: -1))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// The six daily pillars the family asked for, added once and fully editable.
    static func addDefaultsIfNeeded(in context: ModelContext) {
        let key = "addedDefaultHabits"
        addMikvehIfNeeded(in: context)
        guard !UserDefaults.standard.bool(forKey: key) else {
            quietPrayersIfNeeded(in: context)
            return
        }
        let defaults: [(String, String, String, Int)] = [
            ("shacharit", "שחרית", "sunrise.fill", 4),
            ("torah", "קביעות לתורה", "book.fill", 0),
            ("chitas", "חת״ת", "text.book.closed.fill", 1),
            ("mincha", "מנחה", "sun.max.fill", 6),
            ("tzedakah", "צדקה יומית", "heart.fill", 2),
            ("arvit", "ערבית וק״ש", "moon.stars.fill", 7),
        ]
        for (index, item) in defaults.enumerated() {
            let habit = Habit(id: "habit-" + item.0, title: item.1, symbol: item.2, palette: item.3, order: index)
            habit.isQuiet = prayers.contains(habit.id)
            context.insert(habit)
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: quietKey)
    }
}

extension Habit {
    /// Call after a practice was just kept. When it was the last one for
    /// today, the full day's celebration plays; returns true when it did.
    @MainActor @discardableResult
    static func celebrateIfDayFull(in context: ModelContext) -> Bool {
        let all: [Habit] = ((try? context.fetch(FetchDescriptor<Habit>())) ?? []).filter { !$0.removed }
        guard all.count > 1, all.allSatisfy({ $0.isDone() }) else { return false }
        var text: String = "כל קביעויות היום נשמרו."
        if let share = strength(of: all), share >= 0.7 {
            text += " העקביות שלכם בארבעת השבועות האחרונים: \(share.formatted(.percent.precision(.fractionLength(0))))."
        }
        return Moments.shared.play("habits", symbol: "sparkles", title: "יום מלא", text: text, artwork: Theme.emerald)
    }
}
