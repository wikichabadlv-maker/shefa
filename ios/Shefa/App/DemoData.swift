import Foundation
import SwiftData

/// A few made-up lines for the simulator only, so that screenshots show every
/// screen with content. Never runs on a real phone.
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
        let book = Book(title: "היום יום", author: "הרבי מליובאוויטש", totalPages: 240, palette: 7)
        for (back, page) in [(4, 96), (3, 104), (2, 118), (1, 131), (0, 142)] {
            book.setPage(page, on: Calendar.current.date(byAdding: .day, value: -back, to: .now) ?? .now)
        }
        book.createdAt = Calendar.current.date(byAdding: .day, value: -12, to: .now) ?? .now
        context.insert(book)
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
        try? context.save()
    }
}
