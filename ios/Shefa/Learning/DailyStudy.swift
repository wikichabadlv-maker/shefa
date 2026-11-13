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

    static func rambamText(on date: Date = .now) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let start = calendar.date(from: DateComponents(year: 1984, month: 4, day: 29)) else { return "" }
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        let units = rambamUnits
        let cycleDays = units.count / 3
        let dayInCycle = ((days % cycleDays) + cycleDays) % cycleDays
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

/// Which lessons were learned on which day, kept on this phone.
enum StudyLog {
    private static let key = "studyDoneByDay"

    private static var all: [String: [String]] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: [String]]) ?? [:]
    }

    static func done(on date: Date = .now) -> Set<String> {
        Set(all[DayKey.of(date)] ?? [])
    }

    static func toggle(_ id: String, on date: Date = .now) {
        var everything = all
        var today = Set(everything[DayKey.of(date)] ?? [])
        if today.contains(id) { today.remove(id) } else { today.insert(id) }
        everything[DayKey.of(date)] = today.sorted()
        // A year is plenty to remember.
        if everything.count > 400 {
            for old in everything.keys.sorted().prefix(everything.count - 400) { everything[old] = nil }
        }
        UserDefaults.standard.set(everything, forKey: key)
    }

    /// Days in a row in which this lesson was learned.
    static func streak(_ id: String) -> Int {
        DayKey.streak(Set(all.filter { $0.value.contains(id) }.keys))
    }

    /// Days in a row in which all four lessons were learned.
    static var fullStreak: Int {
        DayKey.streak(Set(all.filter { $0.value.count >= 4 }.keys))
    }
}

/// Today's lessons with a tick for each.
struct DailyStudyCard: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { $0.id == "habit-chitas" && !$0.removed }) private var chitasHabit: [Habit]
    @State private var done = StudyLog.done()
    @State private var celebrates = false

    private let portions = DailyStudy.portions()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("השיעורים היומיים")
                    .font(.system(size: 20, weight: .heavy))
                Text("\(done.count)/\(portions.count)")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                if StudyLog.fullStreak > 1 {
                    Label("\(StudyLog.fullStreak) ימים", systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.amberInk)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Theme.amberGround, in: Capsule())
                }
            }

            VStack(spacing: 0) {
                ForEach(portions) { portion in
                    row(portion)
                    if portion.id != portions.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
        .padding(16)
        .cardSurface()
        .overlay {
            if celebrates { ConfettiView().allowsHitTesting(false) }
        }
    }

    private func row(_ portion: StudyPortion) -> some View {
        let isDone = done.contains(portion.id)
        return Button {
            toggle(portion.id)
        } label: {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: portion.artwork, symbol: portion.symbol, size: 40)
                    .saturation(isDone ? 0.3 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(portion.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isDone ? Color.secondary : Color.primary)
                        .strikethrough(isDone)
                    Text(portion.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 25))
                    .foregroundStyle(isDone ? Theme.accent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }

    private func toggle(_ id: String) {
        StudyLog.toggle(id)
        withAnimation(.section) { done = StudyLog.done() }
        let chitas: Set<String> = [DailyStudy.chumash, DailyStudy.tehillim, DailyStudy.tanya]
        if let habit = chitasHabit.first, chitas.isSubset(of: done) != habit.isDone() {
            // The "Chitas" pillar follows the three lessons.
            habit.toggle()
            try? context.save()
        }
        if done.count == portions.count {
            Feedback.celebrate()
            celebrates = true
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                celebrates = false
            }
        } else if done.contains(id) {
            Feedback.done()
        } else {
            Feedback.tap()
        }
    }
}
