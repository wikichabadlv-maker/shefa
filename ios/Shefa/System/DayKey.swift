import Foundation

/// Days as short text such as "2026-11-13", for remembering what was done when.
enum DayKey {
    static func of(_ date: Date = .now) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// A set of days kept as one text field.
    static func split(_ text: String) -> Set<String> {
        Set(text.split(separator: ",").map(String.init))
    }

    /// Joins the days back, keeping only the most recent ones.
    static func join(_ days: Set<String>, keep: Int = 120) -> String {
        days.sorted().suffix(keep).joined(separator: ",")
    }

    /// How many days in a row, ending today or yesterday, are in the set.
    /// With `skipNeutral`, a Shabbat, a festival, a fast or a day the family
    /// set aside neither adds to the count nor breaks it.
    static func streak(_ days: Set<String>, skipNeutral: Bool = false, now: Date = .now) -> Int {
        let calendar = Calendar.current
        let off: Set<String> = skipNeutral ? OffDays.all : []
        var count = 0
        var passed = 0
        var day = now
        var isFirst = true
        while count < 1000 && passed < 1500 {
            let key: String = of(day)
            passed += 1
            if days.contains(key) {
                count += 1
            } else if skipNeutral && (off.contains(key) || JewishDay.of(day).isNeutral) {
                // Not counted, not broken.
            } else if !isFirst {
                break
            }
            isFirst = false
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

/// Small counters kept on this phone: how many tasks were finished each day.
enum Stats {
    private static let key = "doneTasksByDay"

    static var doneByDay: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    static func addDone(_ change: Int, on date: Date = .now) {
        var all = doneByDay
        let day = DayKey.of(date)
        all[day] = max((all[day] ?? 0) + change, 0)
        UserDefaults.standard.set(all, forKey: key)
    }

    static var doneToday: Int { doneByDay[DayKey.of()] ?? 0 }

    static var streak: Int {
        DayKey.streak(Set(doneByDay.filter { $0.value > 0 }.keys), skipNeutral: true)
    }

    static var total: Int { doneByDay.values.reduce(0, +) }
}
