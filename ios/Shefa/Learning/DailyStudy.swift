import SwiftData
import SwiftUI

/// One of the fixed daily lessons.
struct StudyPortion: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let artwork: Artwork
}

/// What is learned today: Chumash, Tehillim, Tanya and three chapters of Rambam.
enum DailyStudy {
    static let chumash = "chumash"
    static let tehillim = "tehillim"
    static let tanya = "tanya"
    static let rambam = "rambam"

    static func portions(on date: Date = .now) -> [StudyPortion] {
        [
            StudyPortion(id: chumash, title: "חומש עם רש״י", detail: chumashText(on: date),
                         symbol: "scroll.fill", artwork: Theme.amber),
            StudyPortion(id: tehillim, title: "תהילים", detail: tehillimText(on: date),
                         symbol: "music.note", artwork: Theme.violet),
            StudyPortion(id: tanya, title: "תניא", detail: "השיעור של \(HebrewDate.text(date)), לפי מורה שיעור",
                         symbol: "flame.fill", artwork: Theme.pink),
            StudyPortion(id: rambam, title: "רמב״ם · שלושה פרקים", detail: rambamText(on: date),
                         symbol: "books.vertical.fill", artwork: Theme.blue),
        ]
    }

    // MARK: Rambam

    /// The first cycle began on 27 Nisan 5744; a cycle is 339 days of three units.
    private static let rambamUnits: [(String, Int)] = {
        var units: [(String, Int)] = (1...12).map { ("הקדמה", $0) }
        for (name, count) in StudyTables.rambam {
            units += (1...count).map { (name, $0) }
        }
        return units
    }()

    private static func dayInCycle(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let start = calendar.date(from: DateComponents(year: 1984, month: 4, day: 29)) else { return 0 }
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        let cycleDays = rambamUnits.count / 3
        return ((days % cycleDays) + cycleDays) % cycleDays
    }

    /// The day's three units, each as a short name such as "עבדים ז׳".
    static func rambamChapters(on date: Date = .now) -> [String] {
        let day = dayInCycle(date)
        return (0..<3).map { index in
            let unit = rambamUnits[day * 3 + index]
            if unit.0 == "הקדמה" { return "חלק \(letters(index + 1))" }
            if unit.0 == "נוסח ההגדה" { return unit.0 }
            return "\(unit.0) \(letters(unit.1))"
        }
    }

    static func rambamText(on date: Date = .now) -> String {
        let units = rambamUnits
        let dayInCycle = dayInCycle(date)
        if dayInCycle < 4 {
            return "הקדמת הרמב״ם ומניין המצוות · יום \(dayInCycle + 1) מתוך 4"
        }
        let today = (0..<3).map { units[dayInCycle * 3 + $0] }
        var parts: [String] = []
        var index = 0
        while index < today.count {
            let name = today[index].0
            var last = index
            while last + 1 < today.count, today[last + 1].0 == name { last += 1 }
            parts.append(sectionText(name, from: today[index].1, to: today[last].1))
            index = last + 1
        }
        return parts.joined(separator: " · ")
    }

    private static func sectionText(_ name: String, from first: Int, to last: Int) -> String {
        if name == "נוסח ההגדה" { return name }
        let chapters = first == last ? "פרק \(letters(first))" : "פרקים \(letters(first))–\(letters(last))"
        if name == "סדר התפילה" { return "\(name), \(chapters)" }
        return "הלכות \(name), \(chapters)"
    }

    /// 1...99 as Hebrew letters, for example 15 is ט״ו.
    static func letters(_ number: Int) -> String {
        let ones = ["", "א", "ב", "ג", "ד", "ה", "ו", "ז", "ח", "ט"]
        let tens = ["", "י", "כ", "ל", "מ", "נ", "ס", "ע", "פ", "צ"]
        guard number > 0, number < 100 else { return "\(number)" }
        var text: String
        switch number {
        case 15: text = "טו"
        case 16: text = "טז"
        default: text = tens[number / 10] + ones[number % 10]
        }
        if text.count == 1 { return text + "׳" }
        text.insert("״", at: text.index(before: text.endIndex))
        return text
    }

    // MARK: Chumash

    private static let aliyot = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שביעי"]

    static func chumashText(on date: Date = .now) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let aliyah = aliyot[(weekday - 1) % 7]
        guard let parsha = parsha(on: date) else { return "פרשת השבוע, \(aliyah)" }
        return "פרשת \(parsha), \(aliyah)"
    }

    /// The portion of the coming Shabbat. Between Haazinu and Simchat Torah
    /// the portion is Vezot Haberacha.
    static func parsha(on date: Date = .now) -> String? {
        let key = DayKey.of(date)
        guard let next = StudyTables.parsha.first(where: { $0.0 >= key }) else { return nil }
        let hebrew = Calendar(identifier: .hebrew).dateComponents([.month, .day], from: date)
        if next.1 == "בראשית", hebrew.month == 1, (hebrew.day ?? 0) <= 22 {
            return "וזאת הברכה"
        }
        return next.1
    }

    // MARK: Tehillim

    private static let tehillimByDay = [
        "א–ט", "י–יז", "יח–כב", "כג–כח", "כט–לד", "לה–לח", "לט–מג", "מד–מח", "מט–נד", "נה–נט",
        "ס–סה", "סו–סח", "סט–עא", "עב–עו", "עז–עח", "עט–פב", "פג–פז", "פח–פט", "צ–צו", "צז–קג",
        "קד–קה", "קו–קז", "קח–קיב", "קיג–קיח", "קיט, א–צו", "קיט, צז–קעו", "קכ–קלד", "קלה–קלט",
        "קמ–קמד", "קמה–קנ",
    ]

    static func tehillimText(on date: Date = .now) -> String {
        let calendar = Calendar(identifier: .hebrew)
        let day = calendar.component(.day, from: date)
        let length = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        if day == 29 && length == 29 { return "פרקים קמ–קנ · יום כ״ט וגם ל׳" }
        let index = min(max(day, 1), 30) - 1
        return "פרקים \(tehillimByDay[index]) · יום \(letters(day)) בחודש"
    }
}
