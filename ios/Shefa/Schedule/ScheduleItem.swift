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

    var timeText: String {
        "\(ScheduleItem.clock(startMinute))–\(ScheduleItem.clock(endMinute))"
    }

    var daysText: String {
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

/// What is happening now, for the floating bar and the Home screen.
struct NowStatus {
    let title: String
    let detail: String
    let symbol: String
    let artwork: Artwork

    static func make(items: [ScheduleItem], now: Date = .now) -> NowStatus {
        let weekday = Calendar.current.component(.weekday, from: now)
        let minute = ScheduleItem.minute(of: now)
        let today = items.filter { !$0.removed && $0.isOn(weekday: weekday) }.sorted { $0.startMinute < $1.startMinute }

        if let current = today.first(where: { $0.startMinute <= minute && minute < $0.endMinute }) {
            return NowStatus(
                title: current.title,
                detail: "עכשיו בלו״ז · נשארו \(duration(current.endMinute - minute))",
                symbol: current.symbol, artwork: current.artwork)
        }
        let zmanim = Zmanim(day: now)
        let nextZman = zmanim.next(after: now, mainOnly: true)
        if let next = today.first(where: { $0.startMinute > minute }) {
            let wait = next.startMinute - minute
            if let nextZman, nextZman.date.timeIntervalSince(now) / 60 < Double(wait) {
                return zmanStatus(nextZman, zmanim: zmanim, now: now)
            }
            return NowStatus(
                title: next.title,
                detail: "מתחיל בעוד \(duration(wait)) · \(ScheduleItem.clock(next.startMinute))",
                symbol: next.symbol, artwork: next.artwork)
        }
        if let nextZman {
            return zmanStatus(nextZman, zmanim: zmanim, now: now)
        }
        return NowStatus(title: "לילה טוב", detail: "אין עוד דברים בלו״ז להיום",
                         symbol: "moon.stars.fill", artwork: Theme.violet)
    }

    private static func zmanStatus(_ zman: Zman, zmanim: Zmanim, now: Date) -> NowStatus {
        let minutes = max(Int(zman.date.timeIntervalSince(now) / 60), 0)
        return NowStatus(
            title: zman.title,
            detail: "בעוד \(duration(minutes)) · \(zmanim.clock(zman.date)) · \(zmanim.city.name)",
            symbol: zman.symbol, artwork: Theme.amber)
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) דק׳" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return hours == 1 ? "שעה" : "\(hours) שעות" }
        return "\(hours):\(String(format: "%02d", rest)) שעות"
    }
}
