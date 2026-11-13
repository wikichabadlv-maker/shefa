import SwiftData
import SwiftUI

/// Remembers when each product was bought, to learn how often the home needs it.
enum ShoppingMemory {
    private static let key = "shoppingBoughtDays"

    struct Rhythm: Identifiable {
        let title: String
        /// Average days between purchases.
        let interval: Int
        let daysSinceLast: Int
        let times: Int

        var id: String { title }
        var isDue: Bool { Double(daysSinceLast) >= Double(interval) * 0.85 }
    }

    private static var stored: [String: [String]] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: [String]]) ?? [:]
    }

    static func record(_ titles: [String], on date: Date = .now) {
        var all = stored
        for title in titles {
            var days = Set(all[title] ?? [])
            days.insert(DayKey.of(date))
            all[title] = Array(days.sorted().suffix(24))
        }
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Every product with the days it was bought, including what older
    /// versions of the list remember.
    private static func history(_ items: [ListItem]) -> [String: Set<String>] {
        var all = stored.mapValues { Set($0) }
        for item in items where item.removed && item.isDone {
            if let date = item.doneAt { all[item.title, default: []].insert(DayKey.of(date)) }
        }
        return all
    }

    /// Products bought at least twice, with how often.
    static func rhythms(_ items: [ListItem], now: Date = .now) -> [Rhythm] {
        let calendar = Calendar.current
        return history(items).compactMap { title, days in
            let dates = days.sorted().compactMap { DayKey.date($0) }
            guard dates.count >= 2, let first = dates.first, let last = dates.last else { return nil }
            let span = calendar.dateComponents([.day], from: first, to: last).day ?? 0
            let interval = max(Int((Double(span) / Double(dates.count - 1)).rounded()), 1)
            let since = calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                                to: calendar.startOfDay(for: now)).day ?? 0
            return Rhythm(title: title, interval: interval, daysSinceLast: since, times: dates.count)
        }
    }

    /// Products that are probably running out and are not on the list.
    static func due(_ items: [ListItem], now: Date = .now) -> [Rhythm] {
        let onList = Set(items.filter { !$0.removed }.map(\.title))
        return rhythms(items, now: now)
            .filter { $0.isDue && !onList.contains($0.title) }
            .sorted { Double($0.daysSinceLast) / Double($0.interval) > Double($1.daysSinceLast) / Double($1.interval) }
    }

    /// Products bought before, most often first.
    static func favorites(_ items: [ListItem]) -> [String] {
        history(items).sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }.map(\.key)
    }

    static func intervalText(_ days: Int) -> String {
        switch days {
        case 1: return "כל יום"
        case 2: return "כל יומיים"
        case 6...8: return "כל שבוע"
        case 13...15: return "כל שבועיים"
        case 27...33: return "כל חודש"
        default: return "כל \(days) ימים"
        }
    }
}

/// One short question that helps the app fit itself to the family.
struct CoachQuestion: Identifiable {
    let id: String
    let text: String
    let why: String
    let options: [(value: String, label: String)]
}

/// Something the app noticed, with a suggestion.
struct CoachInsight: Identifiable {
    let id: String
    let symbol: String
    let artwork: Artwork
    let title: String
    let text: String
}

/// The part of the app that learns the family's habits: it asks a short
/// question now and then, watches what actually happens, and suggests.
enum Coach {
    static let enabledKey = "notifyCoach"
    private static let askedKey = "coach.lastAsked"

    static let questions: [CoachQuestion] = [
        CoachQuestion(id: "peak", text: "מתי הראש שלכם הכי צלול?",
                      why: "בשעה הזו אזכיר את המטלה הכי חשובה של היום.",
                      options: [("9:00", "בבוקר"), ("13:30", "בצהריים"), ("20:00", "בערב")]),
        CoachQuestion(id: "picks", text: "כמה מטלות ביום זה ריאלי בשבילכם?",
                      why: "עדיף לסיים מעט מאשר לגרור רשימה ארוכה. לפי זה אתריע כשהיום עמוס מדי.",
                      options: [("2", "שתיים"), ("3", "שלוש"), ("5", "חמש")]),
        CoachQuestion(id: "evening", text: "מתי נוח לכם לתכנן את מחר?",
                      why: "תכנון של דקה בערב הוא ההרגל שהכי משפר את היום שאחריו.",
                      options: [("20:30", "20:30"), ("21:30", "21:30"), ("22:30", "22:30"), ("off", "בלי תזכורת")]),
        CoachQuestion(id: "morning", text: "מתי לשלוח את תקציר הבוקר?",
                      why: "מה מחכה היום, והשיעורים היומיים, בהתראה אחת.",
                      options: [("6:30", "6:30"), ("7:30", "7:30"), ("8:30", "8:30"), ("off", "בלי תקציר")]),
        CoachQuestion(id: "shopDay", text: "באיזה יום עושים את הקנייה הגדולה?",
                      why: "ערב קודם אזכיר מה ברשימה ומה כנראה נגמר.",
                      options: [("4", "רביעי"), ("5", "חמישי"), ("6", "שישי"), ("0", "משתנה")]),
    ]

    static func answer(_ id: String) -> String? {
        UserDefaults.standard.string(forKey: "coach." + id)
    }

    static func setAnswer(_ id: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: "coach." + id)
        UserDefaults.standard.set(DayKey.of(), forKey: askedKey)
    }

    static func skipToday() {
        UserDefaults.standard.set(DayKey.of(), forKey: askedKey)
    }

    static func forgetAnswers() {
        for question in questions { UserDefaults.standard.removeObject(forKey: "coach." + question.id) }
        UserDefaults.standard.removeObject(forKey: askedKey)
    }

    /// At most one question a day, so it never feels like a form.
    static var nextQuestion: CoachQuestion? {
        guard UserDefaults.standard.string(forKey: askedKey) != DayKey.of() else { return nil }
        return questions.first { answer($0.id) == nil }
    }

    static var dailyPicks: Int { Int(answer("picks") ?? "") ?? 3 }

    private static func minute(_ text: String?) -> Int? {
        guard let parts = text?.split(separator: ":").compactMap({ Int($0) }), parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static var morningMinute: Int? { answer("morning") == "off" ? nil : (minute(answer("morning")) ?? 7 * 60 + 30) }
    static var eveningMinute: Int? { answer("evening") == "off" ? nil : (minute(answer("evening")) ?? 21 * 60 + 30) }
    static var peakMinute: Int? { minute(answer("peak")) }
    /// 1 is Sunday; nil when the day changes from week to week.
    static var shoppingWeekday: Int? {
        guard let day = Int(answer("shopDay") ?? ""), day > 0 else { return nil }
        return day
    }

    // MARK: What the app noticed

    static func insights(tasks: [ListItem], habits: [Habit], books: [Book], shopping: [ListItem]) -> [CoachInsight] {
        var result: [CoachInsight] = []
        let calendar = Calendar.current
        let open = tasks.filter { !$0.isDone && !$0.removed }
        let today = open.filter(\.isForToday)

        if today.count > dailyPicks + 1 {
            result.append(CoachInsight(
                id: "overload", symbol: "scalemass.fill", artwork: Theme.amber,
                title: "היום עמוס מדי",
                text: "בחרתם \(today.count) מטלות להיום, והיעד שלכם הוא \(dailyPicks). מה אפשר לדחות למחר בלב שלם?"))
        }

        let due = ShoppingMemory.due(shopping)
        if !due.isEmpty {
            let names = due.prefix(3).map { "\($0.title) (\(ShoppingMemory.intervalText($0.interval)))" }
            result.append(CoachInsight(
                id: "shopping", symbol: "cart.fill", artwork: Theme.green,
                title: "כנראה נגמר בבית",
                text: names.joined(separator: ", ") + ". אפשר להוסיף לרשימה בנגיעה מלשונית הקניות."))
        }

        let finished = tasks.filter { item in
            guard item.isDone, let date = item.doneAt else { return false }
            return date > (calendar.date(byAdding: .day, value: -60, to: .now) ?? .now)
        }
        if finished.count >= 5 {
            let hours = Dictionary(grouping: finished) { calendar.component(.hour, from: $0.doneAt ?? .now) }
            if let best = hours.max(by: { $0.value.count < $1.value.count }), best.value.count * 3 >= finished.count {
                result.append(CoachInsight(
                    id: "bestHour", symbol: "bolt.fill", artwork: Theme.blue,
                    title: "השעה החזקה שלכם: \(best.key):00",
                    text: "רוב המטלות שלכם נסגרות סביב השעה הזו. שווה לשמור אותה למטלה הכי חשובה ולא לפגישות."))
            }
        }

        let weekDone = (0..<7).reduce(0) { sum, offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            return sum + (Stats.doneByDay[DayKey.of(day)] ?? 0)
        }
        if weekDone > 0, Double(weekDone) / 6 < Double(dailyPicks) * 0.5, open.count > 3 {
            result.append(CoachInsight(
                id: "pace", symbol: "tortoise.fill", artwork: Theme.violet,
                title: "קצב אמיתי: \(weekDone) מטלות בשבוע",
                text: "זה פחות ממה שתכננתם, וזה בסדר. נסו לבחור מטלה אחת פחות בכל יום ולסיים את כולן."))
        }

        let stale = open.filter { item in
            item.due == nil && item.createdAt < (calendar.date(byAdding: .day, value: -14, to: .now) ?? .now)
        }
        if stale.count >= 2 {
            result.append(CoachInsight(
                id: "stale", symbol: "hourglass", artwork: Artwork(0x64748B, 0x334155),
                title: "\(stale.count) מטלות מחכות יותר משבועיים",
                text: "מטלה שלא זזה היא בדרך כלל גדולה מדי או לא באמת חשובה. לפרק לצעד של שתי דקות, לתזמן, או למחוק."))
        }

        let last14 = (0..<14).compactMap { calendar.date(byAdding: .day, value: -$0, to: .now) }
            .filter { calendar.component(.weekday, from: $0) != 7 }
        let tracked = habits.filter { !$0.removed && !$0.days.isEmpty }
        if let weakest = tracked.min(by: { rate($0, last14) < rate($1, last14) }), tracked.count >= 2,
           rate(weakest, last14) < 0.5 {
            let kept = last14.filter { weakest.isDone(on: $0) }.count
            result.append(CoachInsight(
                id: "weakHabit", symbol: "arrow.up.heart.fill", artwork: Theme.pink,
                title: "״\(weakest.title)״ צריך חיזוק",
                text: "נשמר \(kept) מתוך \(last14.count) ימי החול האחרונים. הרגל נתפס כשמצמידים אותו לשעה קבועה בלו״ז."))
        }
        if let strongest = tracked.max(by: { $0.streak < $1.streak }), strongest.streak >= 5 {
            result.append(CoachInsight(
                id: "strongHabit", symbol: "flame.fill", artwork: Theme.amber,
                title: "\(strongest.streak) ימים ברצף: \(strongest.title)",
                text: "זה כבר חלק מכם. הרצף הזה שווה שמירה גם ביום עמוס."))
        }

        if let book = books.first(where: { !$0.isFinished && !$0.removed }) {
            if let finish = book.finishDate, book.totalPages - book.page <= 40 {
                result.append(CoachInsight(
                    id: "bookEnd", symbol: "flag.checkered", artwork: book.artwork,
                    title: "קרובים לסיום ״\(book.title)״",
                    text: "נשארו \(book.totalPages - book.page) עמודים. בקצב הזה תסיימו ב־\(HebrewDate.text(finish))."))
            } else if !book.readToday {
                result.append(CoachInsight(
                    id: "bookToday", symbol: "book.fill", artwork: book.artwork,
                    title: "עמוד אחד ב״\(book.title)״",
                    text: "עוד לא קראתם היום. חמש דקות לפני השינה שומרות על הרצף."))
            }
        }
        return result
    }

    private static func rate(_ habit: Habit, _ days: [Date]) -> Double {
        guard !days.isEmpty else { return 1 }
        return Double(days.filter { habit.isDone(on: $0) }.count) / Double(days.count)
    }
}

/// The coach on the home screen: a question when there is one to ask,
/// otherwise what it noticed.
struct CoachCard: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" }) private var tasks: [ListItem]
    @Query(filter: #Predicate<ListItem> { $0.kind == "shopping" }) private var shopping: [ListItem]
    @Query(filter: #Predicate<Habit> { !$0.removed }) private var habits: [Habit]
    @Query(filter: #Predicate<Book> { !$0.removed }, sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @State private var question = Coach.nextQuestion
    @State private var thanks = false

    var body: some View {
        let insights = Coach.insights(tasks: tasks, habits: habits, books: books, shopping: shopping)
        if let question {
            questionCard(question)
                .transition(.sectionSwap)
        } else if thanks {
            note("תודה, רשמתי", "ההתראות וההצעות יתאימו את עצמן. מחר אשאל עוד שאלה אחת.", "checkmark.seal.fill")
                .transition(.sectionSwap)
        } else if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("שמתי לב")
                    .font(.system(size: 22, weight: .heavy))
                    .padding(.horizontal, 4)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(insights) { insight in
                            tile(insight)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -16)
            }
        }
    }

    private func questionCard(_ item: CoachQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArtworkIcon(artwork: Theme.violet, symbol: "sparkles", size: 36)
                Text("שאלה קצרה, כדי להכיר אתכם")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("לא עכשיו") {
                    Coach.skipToday()
                    withAnimation(.section) { question = nil }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.pressable)
                .foregroundStyle(.secondary)
            }
            Text(item.text)
                .font(.system(size: 20, weight: .heavy))
            Text(item.why)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(item.options, id: \.value) { option in
                    Button {
                        Coach.setAnswer(item.id, option.value)
                        Feedback.done()
                        withAnimation(.section) {
                            question = nil
                            thanks = true
                        }
                        Notifier.shared.refresh(in: context)
                        Task { _ = await Notifier.shared.askPermission() }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .foregroundStyle(Color.primary)
                            .background(Theme.chip, in: Capsule())
                            .minimumScaleFactor(0.8)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(16)
        .cardSurface()
    }

    private func note(_ title: String, _ text: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            ArtworkIcon(artwork: Theme.green, symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .cardSurface()
    }

    private func tile(_ insight: CoachInsight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: insight.symbol)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.2), in: Circle())
            Spacer(minLength: 0)
            Text(insight.title)
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(insight.text)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.92)
                .lineLimit(4)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 260, height: 178, alignment: .leading)
        .background(insight.artwork.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
