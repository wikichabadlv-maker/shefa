import Foundation

/// What a day is in the Jewish year, as it is kept in the Land of Israel:
/// Shabbat and the festivals, their eves, the fasts, Rosh Chodesh, and the
/// days a Chabad home marks. The day meant is the one whose daylight hours
/// fall on the civil date; the night before belongs to it too.
struct JewishDay {
    /// The Hebrew months as `Calendar` numbers them. In a leap year 6 is
    /// the first Adar and 7 the second; in an ordinary year 7 is Adar.
    enum Month {
        static let tishrei = 1, cheshvan = 2, kislev = 3, tevet = 4, shevat = 5, adarFirst = 6, adar = 7
        static let nisan = 8, iyar = 9, sivan = 10, tamuz = 11, av = 12, elul = 13
    }

    let date: Date
    let month: Int
    let day: Int
    let isLeapYear: Bool
    /// 1 is Sunday and 7 is Shabbat.
    let weekday: Int
    /// The festival on which no work is done, when this is one.
    let yomTov: String?
    let isCholHamoed: Bool
    /// A public fast that falls on this day.
    let fast: String?
    let isRoshChodesh: Bool
    /// A day with a name of its own that is neither a festival nor a fast.
    let special: String?
    /// The day of Chanukah, from 1 to 8, when this is one.
    let chanukahDay: Int?

    /// The number of the Chanukah light kindled toward the evening of this
    /// day: the first on the eve of Chanukah, and none on its last day.
    var chanukahCandle: Int? {
        if let chanukahDay { return chanukahDay < 8 ? chanukahDay + 1 : nil }
        return month == Month.kislev && day == 24 ? 1 : nil
    }

    var isShabbat: Bool { weekday == 7 }
    /// Shabbat or a festival: no work, no tasks, no reminders.
    var isRest: Bool { isShabbat || yomTov != nil }

    /// The day after this one.
    var next: JewishDay {
        JewishDay.of(Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date)
    }

    /// A working day that ends in candle lighting.
    var isEve: Bool { !isRest && next.isRest }

    /// Candles are lit toward the evening of this day.
    var hasCandles: Bool { next.isRest }

    /// A day on which the practices of an ordinary day are not expected:
    /// Shabbat, a festival or a fast. It neither adds to a count nor breaks it.
    var isNeutral: Bool { isRest || fast != nil }

    /// The name of the day when it has one, the weightiest first.
    var title: String? {
        if let yomTov { return isShabbat ? "שבת קודש · " + yomTov : yomTov }
        if isShabbat {
            if isCholHamoed { return "שבת חול המועד" }
            if let special { return "שבת קודש · " + special }
            return isRoshChodesh ? "שבת ראש חודש" : "שבת קודש"
        }
        if let fast { return fast }
        // A Friday keeps its own name next to whatever else the day is.
        let friday: String? = weekday == 6 && next.yomTov == nil ? "ערב שבת קודש" : nil
        let name: String? = ownName
        if let friday { return name.map { friday + " · " + $0 } ?? friday }
        return name
    }

    /// What a working day is called apart from its being a Friday.
    private var ownName: String? {
        if isCholHamoed { return special ?? "חול המועד" }
        if let special { return isRoshChodesh ? special + " · ראש חודש" : special }
        if isRoshChodesh { return "ראש חודש" }
        if isEve, let coming = next.yomTov { return "ערב " + coming }
        return nil
    }

    /// The name of the night that leads into this day, when it has one:
    /// "ליל שבת קודש", "ליל י״ט כסלו · חג הגאולה". A fast that begins at
    /// dawn gives the night before it no name.
    var nightTitle: String? {
        if isRest { return title.map { "ליל " + $0 } }
        if let fast { return fast == "תשעה באב" ? "ליל תשעה באב" : nil }
        return ownName.map { "ליל " + $0 }
    }

    /// The Hebrew side of a moment: the date as it is said then, and the
    /// name of the day when it has one. Once the stars are out both belong
    /// to the coming day: "אור לח׳ בכסלו".
    static func moment(_ now: Date = .now) -> (date: String, name: String?) {
        let times: [Zman] = Zmanim(day: now).list
        guard let out = times.first(where: { $0.id == "tzeit" || $0.id == "shabbat-end" }), now >= out.date,
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else {
            return (HebrewDate.text(now), JewishDay.of(now).title)
        }
        return ("אור ל" + HebrewDate.text(tomorrow), JewishDay.of(tomorrow).nightTitle)
    }

    /// A short word for the rest that is coming or is here.
    var restName: String {
        if let yomTov { return yomTov }
        return "שבת"
    }

    /// What is wished as this day of rest comes in: "שבת שלום", "חג שמח".
    var greeting: String {
        guard let yomTov else { return "שבת שלום" }
        if fast != nil { return "גמר חתימה טובה" }
        if yomTov == "ראש השנה" { return "כתיבה וחתימה טובה" }
        return isShabbat ? "שבת שלום וחג שמח" : "חג שמח"
    }

    /// How the evening after this day of rest is called: "מוצאי שבת",
    /// "מוצאי החג", and by their own names for the Days of Awe.
    var outName: String {
        if isShabbat { return "מוצאי שבת" }
        if let yomTov, fast != nil || yomTov == "ראש השנה" { return "מוצאי " + yomTov }
        return "מוצאי החג"
    }

    // MARK: Reading a date

    private static let lock = NSLock()
    private static var cache: [String: JewishDay] = [:]

    /// The same as `JewishDay(date)`, remembered for the days already asked about.
    static func of(_ date: Date = .now) -> JewishDay {
        let key: String = DayKey.of(date)
        lock.lock()
        if let known = cache[key] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let made = JewishDay(date)
        lock.lock()
        if cache.count > 800 { cache.removeAll() }
        cache[key] = made
        lock.unlock()
        return made
    }

    private static var hebrew: Calendar {
        var calendar = Calendar(identifier: .hebrew)
        calendar.timeZone = .current
        return calendar
    }

    init(_ date: Date) {
        let hebrew: Calendar = JewishDay.hebrew
        // Noon, so that the hour of the day never decides which day it is.
        let noon: Date = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let parts = hebrew.dateComponents([.year, .month, .day], from: noon)
        let month: Int = parts.month ?? 1
        let day: Int = parts.day ?? 1
        let weekday: Int = Calendar.current.component(.weekday, from: noon)
        let isLeap: Bool = (hebrew.range(of: .month, in: .year, for: noon)?.count ?? 12) == 13

        self.date = noon
        self.month = month
        self.day = day
        self.weekday = weekday
        self.isLeapYear = isLeap
        self.yomTov = JewishDay.yomTov(month: month, day: day)
        self.isCholHamoed = (month == Month.tishrei && (16...21).contains(day))
            || (month == Month.nisan && (16...20).contains(day))
        self.fast = JewishDay.fast(month: month, day: day, weekday: weekday)
        self.isRoshChodesh = (day == 1 && month != Month.tishrei) || day == 30
        let chanukah: Int? = JewishDay.chanukah(month: month, day: day, date: noon, year: parts.year ?? 0)
        self.chanukahDay = chanukah
        self.special = JewishDay.special(month: month, day: day, isLeap: isLeap, chanukah: chanukah)
    }

    private static func yomTov(month: Int, day: Int) -> String? {
        switch (month, day) {
        case (Month.tishrei, 1), (Month.tishrei, 2): return "ראש השנה"
        case (Month.tishrei, 10): return "יום הכיפורים"
        case (Month.tishrei, 15): return "חג הסוכות"
        case (Month.tishrei, 22): return "שמיני עצרת ושמחת תורה"
        case (Month.nisan, 15): return "חג הפסח"
        case (Month.nisan, 21): return "שביעי של פסח"
        case (Month.sivan, 6): return "חג השבועות"
        default: return nil
        }
    }

    /// A fast that falls on Shabbat is kept on Sunday, and the Fast of
    /// Esther is brought forward to Thursday.
    private static func fast(month: Int, day: Int, weekday: Int) -> String? {
        switch (month, day) {
        case (Month.tishrei, 10): return "יום הכיפורים"
        case (Month.tishrei, 3) where weekday != 7, (Month.tishrei, 4) where weekday == 1: return "צום גדליה"
        case (Month.tevet, 10): return "עשרה בטבת"
        case (Month.adar, 13) where weekday != 7, (Month.adar, 11) where weekday == 5: return "תענית אסתר"
        case (Month.tamuz, 17) where weekday != 7, (Month.tamuz, 18) where weekday == 1: return "שבעה עשר בתמוז"
        case (Month.av, 9) where weekday != 7, (Month.av, 10) where weekday == 1: return "תשעה באב"
        default: return nil
        }
    }

    /// Chanukah runs eight days from the 25th of Kislev, into Tevet.
    private static func chanukah(month: Int, day: Int, date: Date, year: Int) -> Int? {
        guard (month == Month.kislev && day >= 25) || (month == Month.tevet && day <= 3) else { return nil }
        let hebrew: Calendar = JewishDay.hebrew
        guard let first = hebrew.date(from: DateComponents(year: year, month: Month.kislev, day: 25, hour: 12)) else {
            return nil
        }
        let passed: Int = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: first),
            to: Calendar.current.startOfDay(for: date)).day ?? -1
        return (0...7).contains(passed) ? passed + 1 : nil
    }

    private static func special(month: Int, day: Int, isLeap: Bool, chanukah: Int?) -> String? {
        // The days of Chanukah are called by their number, and the last by its own name.
        if let chanukah { return chanukah == 8 ? "זאת חנוכה" : "\(JewishDay.letters[chanukah - 1])׳ דחנוכה" }
        switch (month, day) {
        case (Month.tishrei, 6): return "ו׳ תשרי"
        case (Month.tishrei, 9): return "ערב יום הכיפורים"
        case (Month.tishrei, 13): return "י״ג תשרי"
        case (Month.tishrei, 21): return "הושענא רבה"
        case (Month.cheshvan, 20): return "כ׳ חשוון"
        case (Month.kislev, 9): return "ט׳ כסלו"
        case (Month.kislev, 10): return "י׳ כסלו · חג הגאולה"
        case (Month.kislev, 14): return "י״ד כסלו"
        case (Month.kislev, 19): return "י״ט כסלו · חג הגאולה"
        case (Month.kislev, 20): return "כ׳ כסלו · חג הגאולה"
        case (Month.kislev, 24): return "ערב חנוכה"
        case (Month.tevet, 5): return "ה׳ טבת · דידן נצח"
        case (Month.tevet, 24): return "כ״ד טבת"
        case (Month.shevat, 10): return "יו״ד שבט"
        case (Month.shevat, 15): return "ט״ו בשבט"
        case (Month.shevat, 22): return "כ״ב שבט"
        case (Month.adarFirst, 14) where isLeap: return "פורים קטן"
        case (Month.adar, 14): return "פורים"
        case (Month.adar, 15): return "שושן פורים"
        case (Month.adar, 25): return "כ״ה אדר"
        case (Month.nisan, 2): return "ב׳ ניסן"
        case (Month.nisan, 11): return "י״א ניסן"
        case (Month.nisan, 13): return "י״ג ניסן"
        case (Month.nisan, 14): return "ערב פסח"
        case (Month.iyar, 2): return "ב׳ אייר"
        case (Month.iyar, 14): return "פסח שני"
        case (Month.iyar, 18): return "ל״ג בעומר"
        case (Month.sivan, 5): return "ערב חג השבועות"
        case (Month.tamuz, 3): return "ג׳ תמוז"
        case (Month.tamuz, 12): return "י״ב תמוז · חג הגאולה"
        case (Month.tamuz, 13): return "י״ג תמוז · חג הגאולה"
        case (Month.av, 15): return "ט״ו באב"
        case (Month.av, 20): return "כ׳ מנחם אב"
        case (Month.elul, 18): return "ח״י אלול"
        case (Month.elul, 29): return "ערב ראש השנה"
        default: return nil
        }
    }

    private static let ordinals = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שביעי", "שמיני"]
    private static let letters = ["א", "ב", "ג", "ד", "ה", "ו", "ז", "ח"]

    /// "ראשון" for 1, up to "שמיני" for 8.
    static func ordinal(_ number: Int) -> String {
        ordinals[min(max(number, 1), 8) - 1]
    }
}
