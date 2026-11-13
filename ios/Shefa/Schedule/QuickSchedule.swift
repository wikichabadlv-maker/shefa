import SwiftData
import SwiftUI

/// Understands a short line such as "שחרית 7:00 שעה" or "עבודה 9-17".
enum ScheduleParser {
    struct Result {
        var title: String
        var start: Int?
        var duration: Int?
    }

    static func parse(_ text: String) -> Result {
        var words = text.split(separator: " ").map(String.init)
        var start: Int?
        var end: Int?
        var duration: Int?

        func clock(_ word: String) -> Int? {
            let clean = word.trimmingCharacters(in: CharacterSet(charactersIn: "ב-־,."))
            let parts = clean.split(whereSeparator: { $0 == ":" || $0 == "." }).compactMap { Int($0) }
            if parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) { return parts[0] * 60 + parts[1] }
            if parts.count == 1, clean.allSatisfy(\.isNumber), (0..<24).contains(parts[0]) { return parts[0] * 60 }
            return nil
        }

        var kept: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let next = index + 1 < words.count ? words[index + 1] : ""
            // "9-17", "9:00-17:30"
            let range = word.split(whereSeparator: { $0 == "-" || $0 == "–" || $0 == "־" }).map(String.init)
            if range.count == 2, let from = clock(range[0]), let to = clock(range[1]), start == nil {
                start = from
                end = to
            } else if let number = Int(word), ["דק", "דק׳", "דקות", "דקה"].contains(next) {
                duration = number
                index += 1
            } else if let number = Int(word), ["שעות", "שעה"].contains(next) {
                duration = number * 60
                index += 1
            } else if word == "חצי", next == "שעה" {
                duration = 30
                index += 1
            } else if word == "רבע", next == "שעה" {
                duration = 15
                index += 1
            } else if word == "שעה", next == "וחצי" {
                duration = 90
                index += 1
            } else if word == "שעה", start != nil || index > 0 {
                duration = 60
            } else if word == "שעתיים" {
                duration = 120
            } else if ["עד", "ב", "בשעה", "מ"].contains(word), clock(next) != nil {
                if word == "עד" { end = clock(next) } else { start = clock(next) }
                index += 1
            } else if let time = clock(word), word.contains(":") || word.hasPrefix("ב") || start == nil && Int(word) != nil {
                if start == nil { start = time } else if end == nil { end = time }
            } else {
                kept.append(word)
            }
            index += 1
        }
        words = kept
        if let start, let end, end > start { duration = end - start }
        // An afternoon hour written as a small number: "מנחה 4" hardly means four at night.
        if let value = start, value > 0, value < 6 * 60, !text.contains(":") { start = value + 12 * 60 }
        return Result(title: words.joined(separator: " "), start: start, duration: duration)
    }

    /// A fitting symbol and color for a title.
    static func look(for title: String) -> (symbol: String, palette: Int) {
        let table: [([String], String, Int)] = [
            (["שחרית", "תפילה"], "sunrise.fill", 4),
            (["מנחה"], "sun.max.fill", 6),
            (["ערבית", "מעריב", "שמע"], "moon.stars.fill", 7),
            (["מקווה", "מקוה"], "drop.fill", 5),
            (["חת״ת", "חתת", "רמב", "תניא", "שיעור", "לימוד", "דף", "כולל", "סדר"], "book.fill", 0),
            (["חברותא", "פגישה", "ישיבה"], "person.2.fill", 3),
            (["עבודה", "משרד", "ויקי"], "briefcase.fill", 7),
            (["ארוחת", "ארוחה", "אוכל", "בוקר", "צהריים", "ערב"], "fork.knife", 6),
            (["ספורט", "הליכה", "ריצה", "אימון"], "figure.walk", 3),
            (["שינה", "מנוחה", "לישון"], "bed.double.fill", 1),
            (["זוגי", "משפחה", "ילדים", "אשתי", "בית"], "heart.fill", 2),
            (["קניות", "סופר"], "cart.fill", 3),
            (["נסיעה", "רכב"], "car.fill", 5),
        ]
        for (keys, symbol, palette) in table where keys.contains(where: { title.contains($0) }) {
            return (symbol, palette)
        }
        return ("clock.fill", title.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 8)
    }
}

/// Builds the day one line at a time: type what and when, press return, type the next.
struct QuickScheduleBar: View {
    let day: Date
    let todays: [ScheduleItem]
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var repeatKind = 0
    @State private var justAdded: String?
    @FocusState private var isTyping: Bool

    private var parsed: ScheduleParser.Result { ScheduleParser.parse(text) }

    /// Without a time, the new part follows the last one of the day.
    private var start: Int {
        if let start = parsed.start { return start }
        if let last = todays.map(\.endMinute).max(), last < 23 * 60 { return last }
        return 8 * 60
    }

    private var duration: Int { parsed.duration ?? 60 }

    private struct Idea: Identifiable {
        let title: String
        let start: Int
        let duration: Int
        var id: String { title }
    }

    private static let ideas = [
        Idea(title: "מקווה", start: 6 * 60 + 30, duration: 20), Idea(title: "שחרית", start: 7 * 60, duration: 60),
        Idea(title: "חת״ת ורמב״ם", start: 8 * 60, duration: 45), Idea(title: "ארוחת בוקר", start: 8 * 60 + 45, duration: 15),
        Idea(title: "עבודה", start: 9 * 60, duration: 480), Idea(title: "מנחה", start: 13 * 60 + 30, duration: 20),
        Idea(title: "זמן משפחה", start: 18 * 60, duration: 90), Idea(title: "ערבית", start: 20 * 60, duration: 20),
        Idea(title: "חברותא", start: 20 * 60 + 30, duration: 60), Idea(title: "קריאה", start: 22 * 60, duration: 30),
    ]

    private var openIdeas: [Idea] {
        Self.ideas.filter { idea in !todays.contains { $0.title == idea.title } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
                TextField("מה ומתי? למשל: שחרית 7:00 שעה", text: $text)
                    .font(.system(size: 17))
                    .focused($isTyping)
                    .submitLabel(.done)
                    .onSubmit { add() }
            }

            if !parsed.title.isEmpty {
                HStack(spacing: 8) {
                    let look = ScheduleParser.look(for: parsed.title)
                    Label("\(ScheduleItem.clock(start))–\(ScheduleItem.clock(start + duration))", systemImage: look.symbol)
                        .font(.system(size: 14, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(SavingsGoal.palettes[look.palette % SavingsGoal.palettes.count].gradient, in: Capsule())
                        .contentTransition(.numericText())
                    ForEach(Array(["קבוע", "רק היום"].enumerated()), id: \.offset) { index, name in
                        Button {
                            repeatKind = index
                        } label: {
                            Text(name)
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .foregroundStyle(repeatKind == index ? Theme.ground : Color.primary)
                                .background(repeatKind == index ? Color.primary : Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                    Spacer(minLength: 0)
                    Button {
                        add()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 34)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("הוספה ללו״ז")
                }
                .transition(.sectionSwap)
            } else if let justAdded {
                Label("נוסף: \(justAdded). אפשר לכתוב את הבא.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .transition(.sectionSwap)
            } else {
                Text("כותבים שם ושעה ולוחצים על סיום. בלי שעה, החלק החדש ממשיך מסוף הקודם.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !openIdeas.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(openIdeas) { idea in
                            Button {
                                insert(title: idea.title, start: idea.start, duration: idea.duration, once: false)
                            } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Label(idea.title, systemImage: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                    Text(ScheduleItem.clock(idea.start))
                                        .font(.system(size: 11, weight: .medium))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.pressable)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -14)
            }
        }
        .padding(14)
        .cardSurface()
        .animation(.section, value: parsed.title.isEmpty)
        .animation(.section, value: todays.count)
    }

    private func add() {
        let title = parsed.title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        insert(title: title, start: start, duration: duration, once: repeatKind == 1)
        text = ""
        isTyping = true
    }

    private func insert(title: String, start: Int, duration: Int, once: Bool) {
        let look = ScheduleParser.look(for: title)
        let item = ScheduleItem(title: title, startMinute: min(start, 23 * 60 + 55), durationMinutes: max(duration, 5),
                                symbol: look.symbol, palette: look.palette)
        if once { item.onlyDay = DayKey.of(day) }
        withAnimation(.section) {
            context.insert(item)
            justAdded = "\(title) ב־\(ScheduleItem.clock(start))"
        }
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        Feedback.added()
        Task { _ = await Notifier.shared.askPermission() }
    }
}
