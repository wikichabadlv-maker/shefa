import Foundation
import SwiftData

/// A few made-up lines for the simulator only, so that screenshots show every
/// screen with content. Never runs on a real phone, and nothing in it is taken
/// from the family's own records.
enum DemoData {
    static func fill(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<ListItem>())) ?? 0
        guard existing == 0 else { return }

        let today = Calendar.current.startOfDay(for: .now)
        for (index, title) in ["להזמין תור לרופא שיניים", "לשלם ועד בית", "לקנות מתנה לבר מצווה",
                               "להחזיר ספר לספרייה", "לחדש ביטוח רכב"].enumerated() {
            let item = ListItem(kind: ListItem.task, title: title)
            if index < 2 { item.due = today }
            if index == 0 { item.priority = 1; item.minutes = 10 }
            if index == 2 { item.due = Calendar.current.date(byAdding: .day, value: 3, to: today) }
            if index == 3 { item.due = Calendar.current.date(byAdding: .day, value: -1, to: today); item.repeatRule = "weekly" }
            context.insert(item)
        }
        let finished = ListItem(kind: ListItem.task, title: "לשלוח טופס למעון")
        finished.isDone = true
        finished.doneAt = .now
        context.insert(finished)
        if Stats.doneToday == 0 { Stats.addDone(1) }
        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        for habit in habits.prefix(2) where !habit.isDone() { habit.toggle() }
        for title in ["חלב", "ביצים", "חלות לשבת", "נרות"] {
            context.insert(ListItem(kind: ListItem.shopping, title: title))
        }
        for title in ["קוד לדלת הבניין: 2580", "מידת נעליים של רבקי: 38"] {
            context.insert(ListItem(kind: ListItem.note, title: title))
        }
        StudyLog.fillDemo()
        let book = Book(title: "היום יום", author: "הרבי מליובאוויטש", totalPages: 240, palette: 7)
        for (back, page) in [(4, 96), (3, 104), (2, 118), (1, 131), (0, 142)] {
            book.setPage(page, on: Calendar.current.date(byAdding: .day, value: -back, to: .now) ?? .now)
        }
        book.createdAt = Calendar.current.date(byAdding: .day, value: -12, to: .now) ?? .now
        context.insert(book)
        for (index, done) in [("לקוטי דיבורים", 420), ("ספר הזכרונות", 310), ("אגרות קודש", 180)].enumerated() {
            let read = Book(title: done.0, author: "", totalPages: done.1, palette: index + 1)
            let day = Calendar.current.date(byAdding: .day, value: -20 * (index + 1), to: .now) ?? .now
            read.setPage(done.1, on: day)
            read.createdAt = day
            context.insert(read)
        }
        for (title, gaps) in [("חלב", [18, 12, 6]), ("לחם", [9, 6, 3]), ("יין", [21, 14, 7])] {
            for gap in gaps {
                ShoppingMemory.record([title], on: Calendar.current.date(byAdding: .day, value: -gap, to: .now) ?? .now)
            }
        }
        context.insert(ListItem(kind: ListItem.learning, title: "לסיים פרק ב׳ בתניא"))

        let schedule: [(String, Int, Int, String, Int)] = [
            ("שחרית", 7 * 60, 60, "sunrise.fill", 4),
            ("חת״ת ורמב״ם", 8 * 60 + 15, 30, "book.fill", 0),
            ("עבודה", 9 * 60, 420, "briefcase.fill", 7),
            ("חברותא", 20 * 60, 60, "person.2.fill", 3),
        ]
        for line in schedule {
            context.insert(ScheduleItem(title: line.0, startMinute: line.1, durationMinutes: line.2,
                                        weekdays: ScheduleItem.everyDay, symbol: line.3, palette: line.4))
        }

        let fund = SavingsGoal(id: SavingsGoal.emergencyID, title: "קרן חירום", saved: 6500, target: 24000,
                               symbol: "umbrella.fill", palette: 3)
        context.insert(fund)
        let trip = SavingsGoal(title: "חופשה בצפון", saved: 1200, target: 4000, symbol: "airplane", palette: 2)
        trip.deadline = Calendar.current.date(byAdding: .month, value: 7, to: .now)
        context.insert(trip)

        let lines: [(String, String, String?, Int)] = [
            ("ירקות בשוק", "-86", "food", 1),
            ("מונית", "-42", "transport", 2),
            ("שיעור פרטי", "350", "income", 3),
            ("קופת צדקה", "-36", "maaser", 4),
            ("שופרסל דיל", "-312.40", nil, 5),
        ]
        for line in lines {
            let date = Calendar.current.date(byAdding: .day, value: -line.3, to: .now) ?? .now
            context.insert(LedgerEntry(
                id: LedgerEntry.manualPrefix + "demo-\(line.3)", date: date, title: line.0,
                amount: Decimal(string: line.1) ?? 0, source: "מזומן", categoryID: line.2))
        }
        fillHistory(context)
        try? context.save()
    }

    /// Made-up monthly summaries for the half year before this month, in the
    /// shape of a family spreadsheet, so that trends and comparisons have
    /// something to show.
    private static func fillHistory(_ context: ModelContext) {
        let lines: [(String, String, Int, Bool)] = [
            ("income.salary", "משכורת", 9800, true), ("income.spouse", "משכורת שנייה", 6400, true),
            ("home.rent", "שכר דירה", -4200, true), ("home.arnona", "ארנונה", -420, true),
            ("home.electric", "חשמל", -380, false), ("home.mobile", "סלולר", -120, true),
            ("food.groceries", "סופר ומכולת", -2600, false), ("transport.fuel", "דלק", -520, false),
            ("transport.public", "תחבורה ציבורית", -160, false), ("shabbat.shabbat", "שבת וחג", -340, false),
            ("health.kupah", "קופת חולים", -210, true), ("kids.classes", "חוגים", -450, true),
            ("clothing.clothes", "ביגוד והנעלה", -300, false), ("gift.restaurants", "מסעדות וקפה", -260, false),
            ("maaser.regular", "מעשר", -1620, true),
        ]
        let wobble: [Double] = [0.94, 1.06, 0.98, 1.1, 0.9, 1.03]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem") ?? .current
        var parts = calendar.dateComponents([.year, .month], from: .now)
        parts.day = 15
        parts.hour = 12
        guard let middle = calendar.date(from: parts) else { return }
        for back in 1...6 {
            guard let date = calendar.date(byAdding: .month, value: -back, to: middle) else { continue }
            for (index, line) in lines.enumerated() {
                let share: Double = line.3 ? 1 : wobble[(back + index) % wobble.count]
                let amount: Int = Int((Double(line.2) * share).rounded())
                let group: String = String(line.0.prefix { $0 != "." })
                context.insert(LedgerEntry(
                    id: "demo-history-\(back)-\(index)", date: date, title: line.1,
                    amount: Decimal(amount), source: ExcelImport.source, categoryID: group,
                    sub: SubCategory.find(line.0)))
            }
        }
    }
}
