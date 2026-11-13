import Foundation
import SwiftData

/// A fixed part of the family's day, for example morning prayers or a study
/// session, repeating on chosen days of the week.
@Model
final class ScheduleItem {
    @Attribute(.unique) var id: String
    var title: String
    /// Minutes from midnight.
    var startMinute: Int
    var durationMinutes: Int
    /// One bit per day: bit 0 is Sunday, bit 6 is Shabbat.
    var weekdays: Int
    var symbol: String
    var palette: Int
    var createdAt: Date
    var updatedAt: Date = Date.now
    var removed: Bool = false
    /// When set, the item happens on this one day only (a `DayKey`).
    var onlyDay: String = ""
    /// The days on which it was marked as done, as `DayKey`s joined by commas.
    var doneDays: String = ""
    /// When set, the start follows one of the day's times (a `Zman` id) and
    /// not the clock, so "Mincha before sunset" moves with the seasons.
    var anchor: String = ""
    /// Minutes after the anchor; negative for before it.
    var anchorOffset: Int = 0

    init(id: String = UUID().uuidString, title: String, startMinute: Int, durationMinutes: Int,
         weekdays: Int = ScheduleItem.weekdaysMask, symbol: String = "clock.fill", palette: Int = 0) {
        self.id = id
        self.title = title
        self.startMinute = startMinute
        self.durationMinutes = durationMinutes
        self.weekdays = weekdays
        self.symbol = symbol
        self.palette = palette
        self.createdAt = .now
    }

    /// Sunday to Friday.
    static let weekdaysMask = 0b0111111
    static let everyDay = 0b1111111
    static let dayLetters = ["א", "ב", "ג", "ד", "ה", "ו", "ש"]

    var endMinute: Int { startMinute + durationMinutes }

    var artwork: Artwork {
        SavingsGoal.palettes[abs(palette) % SavingsGoal.palettes.count]
    }

    /// `weekday` is 1 for Sunday, as in `Calendar`.
    func isOn(weekday: Int) -> Bool {
        weekdays & (1 << (weekday - 1)) != 0
    }

    func isOn(_ date: Date) -> Bool {
        if !onlyDay.isEmpty { return onlyDay == DayKey.of(date) }
        // A festival is kept like Shabbat: only what was set for Shabbat is on.
        if JewishDay.of(date).yomTov != nil { return isOn(weekday: 7) }
        return isOn(weekday: Calendar.current.component(.weekday, from: date))
    }

    /// The minute it starts on a given day: by its anchor when it has one
    /// and the day has that time, otherwise by the clock.
    func start(on day: Date) -> Int {
        guard !anchor.isEmpty,
              let zman = Zmanim(day: day).list.first(where: { $0.id == anchor }) else { return startMinute }
        return min(max(ScheduleItem.minute(of: zman.date) + anchorOffset, 0), 23 * 60 + 55)
    }

    func end(on day: Date) -> Int { start(on: day) + durationMinutes }

    /// The times of the day a part can follow, in the order of the day.
    static let anchors: [(id: String, title: String)] = [
        ("netz", "הנץ החמה"), ("shma", "סוף זמן קריאת שמע"), ("chatzot", "חצות היום"),
        ("mincha", "מנחה גדולה"), ("plag", "פלג המנחה"), ("candles", "הדלקת נרות"),
        ("shkia", "שקיעת החמה"), ("tzeit", "צאת הכוכבים"),
    ]

    /// For example "20 דק׳ לפני שקיעת החמה".
    var anchorText: String? {
        guard let name = ScheduleItem.anchors.first(where: { $0.id == anchor })?.title else { return nil }
        if anchorOffset == 0 { return "ב" + name }
        let side: String = anchorOffset < 0 ? "לפני" : "אחרי"
        return "\(NowStatus.duration(abs(anchorOffset))) \(side) \(name)"
    }

    func isDone(on date: Date = .now) -> Bool {
        DayKey.split(doneDays).contains(DayKey.of(date))
    }

    func setDone(_ done: Bool, on date: Date = .now) {
        var days = DayKey.split(doneDays)
        if done { days.insert(DayKey.of(date)) } else { days.remove(DayKey.of(date)) }
        doneDays = DayKey.join(days, keep: 60)
        updatedAt = .now
    }

    var timeText: String {
        "\(ScheduleItem.clock(startMinute))–\(ScheduleItem.clock(endMinute))"
    }

    var daysText: String {
        if !onlyDay.isEmpty { return "חד פעמי" }
        if weekdays == ScheduleItem.everyDay { return "כל יום" }
        if weekdays == ScheduleItem.weekdaysMask { return "ימים א׳ עד ו׳" }
        if weekdays == 0b0011111 { return "ימים א׳ עד ה׳" }
        let letters = (0..<7).filter { weekdays & (1 << $0) != 0 }.map { ScheduleItem.dayLetters[$0] + "׳" }
        return letters.isEmpty ? "ללא ימים" : "ימי " + letters.joined(separator: ", ")
    }

    static func clock(_ minute: Int) -> String {
        let wrapped = ((minute % 1440) + 1440) % 1440
        return String(format: "%d:%02d", wrapped / 60, wrapped % 60)
    }

    static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

extension ScheduleItem {
    /// Brings the clock time of every anchored part to today's times. It is
    /// this phone's own reading of the same rule, so it is not stamped as an
    /// edit and the other phone is not told.
    @MainActor
    static func followAnchors(in context: ModelContext, now: Date = .now) {
        let all: [ScheduleItem] = (try? context.fetch(FetchDescriptor<ScheduleItem>())) ?? []
        var changed = false
        for item in all where !item.removed && !item.anchor.isEmpty {
            let start: Int = item.start(on: now)
            if item.startMinute != start {
                item.startMinute = start
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    /// Call after a part of today was just marked as done. When it was the
    /// last one, the day's celebration plays; returns true when it did.
    @MainActor @discardableResult
    static func celebrateIfDayDone(in context: ModelContext) -> Bool {
        let all: [ScheduleItem] = (try? context.fetch(FetchDescriptor<ScheduleItem>())) ?? []
        let today: [ScheduleItem] = NowStatus.today(all)
        guard today.count > 1, today.allSatisfy({ $0.isDone() }) else { return false }
        return Moments.shared.play(
            "schedule", symbol: "checkmark.seal.fill", title: "סדר היום הושלם",
            text: "כל \(today.count) חלקי היום סומנו. מחר ממשיכים.", artwork: Sky.now().artwork)
    }
}

/// What is happening now in the family's own schedule, for the floating bar.
struct NowStatus {
    let title: String
    let detail: String
    let symbol: String
    let artwork: Artwork
    /// The schedule item behind it, when there is one.
    var item: ScheduleItem?
    /// From 0 to 1 while an item is in progress.
    var progress: Double?

    static func today(_ items: [ScheduleItem], on date: Date = .now) -> [ScheduleItem] {
        items.filter { !$0.removed && $0.isOn(date) }.sorted { $0.startMinute < $1.startMinute }
    }

    static func make(items: [ScheduleItem], topTask: String? = nil, now: Date = .now) -> NowStatus {
        let minute = ScheduleItem.minute(of: now)
        let list = today(items, on: now)

        if let current = list.first(where: { $0.startMinute <= minute && minute < $0.endMinute }) {
            let share = Double(minute - current.startMinute) / Double(max(current.durationMinutes, 1))
            return NowStatus(
                title: current.title,
                detail: "עכשיו · נשארו \(duration(current.endMinute - minute))",
                symbol: current.symbol, artwork: current.artwork, item: current, progress: share)
        }
        if let next = list.first(where: { $0.startMinute > minute }) {
            return NowStatus(
                title: next.title,
                detail: "הבא בתור · בעוד \(duration(next.startMinute - minute)) · \(ScheduleItem.clock(next.startMinute))",
                symbol: next.symbol, artwork: next.artwork, item: next)
        }
        if let topTask {
            return NowStatus(title: topTask, detail: "המטלה הבאה שלך", symbol: "checklist", artwork: Theme.emerald)
        }
        if list.isEmpty {
            return NowStatus(title: "היום פנוי", detail: "הקישו כדי לבנות את היום",
                             symbol: "sparkles", artwork: Theme.emerald)
        }
        return NowStatus(title: "סיימנו להיום", detail: "אין עוד דברים בלו״ז",
                         symbol: "moon.stars.fill", artwork: Theme.violet)
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) דק׳" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return hours == 1 ? "שעה" : (hours == 2 ? "שעתיים" : "\(hours) שעות") }
        return "\(hours):\(String(format: "%02d", rest)) שעות"
    }
}
