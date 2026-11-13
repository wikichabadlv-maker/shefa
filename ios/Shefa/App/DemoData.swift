import Foundation
import SwiftData

/// A few made-up lines for the simulator only, so that screenshots show every
/// screen with content. Never runs on a real phone, and nothing in it is taken
/// from the family's own records.
enum DemoData {
    static func fill(_ context: ModelContext) {
        // Kept in memory only, so every demo launch sets them again.
        FinancePlan.shared.fillDemo()
        BankState.shared.fillDemo()
        fillRoutines()
        let existing = (try? context.fetchCount(FetchDescriptor<ListItem>())) ?? 0
        guard existing == 0 else { return }

        let today = Calendar.current.startOfDay(for: .now)
        let yesterday: Date = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        // Title, days from today (nil for no day), minutes.
        let tasks: [(String, Int?, Int)] = [
            ("להזמין תור לרופא שיניים", 0, 10), ("לשלם ועד בית", 0, 5),
            ("לסדר את הניירת לרואה החשבון", 0, 60), ("להחזיר ספר לספרייה", -1, 20),
            ("לקנות מתנה לבר מצווה", 3, 45), ("לחדש ביטוח רכב", nil, 30), ("להתקשר לסבתא", nil, 0),
        ]
        for (index, line) in tasks.enumerated() {
            let item = ListItem(kind: ListItem.task, title: line.0)
            if let days = line.1 { item.due = Calendar.current.date(byAdding: .day, value: days, to: today) }
            item.minutes = line.2
            if index == 0 { item.priority = 1 }
            if index == 3 { item.repeatRule = "weekly" }
            if index == 5 {
                // Chosen for yesterday, not done, and put off before that too.
                item.todayDay = ListItem.leftMark + DayKey.of(yesterday)
                item.pushed = 3
                item.pushedDay = DayKey.of(today)
            }
            item.createdAt = Date.now.addingTimeInterval(Double(-index))
            context.insert(item)
        }
        let finished = ListItem(kind: ListItem.task, title: "לשלוח טופס למעון")
        finished.isDone = true
        finished.doneAt = .now
        finished.minutes = 15
        context.insert(finished)
        if Stats.doneToday == 0 { Stats.addDone(1) }
        fillJournal()
        fillHabits((try? context.fetch(FetchDescriptor<Habit>())) ?? [])
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

        // Work and the evening study keep to Sunday through Thursday.
        let midweek = 0b0011111
        let schedule: [(String, Int, Int, String, Int, Int)] = [
            ("שחרית", 7 * 60, 60, "sunrise.fill", 4, ScheduleItem.everyDay),
            ("חת״ת ורמב״ם", 8 * 60 + 15, 30, "book.fill", 0, ScheduleItem.everyDay),
            ("עבודה", 9 * 60, 420, "briefcase.fill", 7, midweek),
            ("חברותא", 20 * 60, 60, "person.2.fill", 3, midweek),
        ]
        for line in schedule {
            context.insert(ScheduleItem(title: line.0, startMinute: line.1, durationMinutes: line.2,
                                        weekdays: line.5, symbol: line.3, palette: line.4))
        }
        // One part that follows the sun and not the clock.
        let mincha = ScheduleItem(title: "מנחה", startMinute: 16 * 60 + 15, durationMinutes: 15,
                                  weekdays: ScheduleItem.weekdaysMask, symbol: "sun.max.fill", palette: 6)
        mincha.anchor = "shkia"
        mincha.anchorOffset = -20
        mincha.startMinute = mincha.start(on: .now)
        context.insert(mincha)

        let fund = SavingsGoal(id: SavingsGoal.emergencyID, title: "קרן חירום", saved: 6500, target: 24000,
                               symbol: "umbrella.fill", palette: 3)
        for (back, amount) in [(3, 500), (2, 400), (1, 600), (0, 300)] {
            fund.record(Decimal(amount), on: Calendar.current.date(byAdding: .month, value: -back, to: .now) ?? .now)
        }
        context.insert(fund)
        let trip = SavingsGoal(title: "חופשה בצפון", saved: 1200, target: 4000, symbol: "airplane", palette: 2)
        trip.deadline = Calendar.current.date(byAdding: .month, value: 7, to: .now)
        for (back, amount) in [(2, 350), (1, 450), (0, 400)] {
            trip.record(Decimal(amount), on: Calendar.current.date(byAdding: .month, value: -back, to: .now) ?? .now)
        }
        context.insert(trip)
        if let pesach = Occasion.find("pesach") {
            let holiday = SavingsGoal(title: pesach.fund, saved: 900, target: 2400, symbol: pesach.symbol,
                                      palette: pesach.palette)
            holiday.occasion = pesach.id
            holiday.deadline = pesach.deadline()
            holiday.record(450, on: Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now)
            holiday.record(450)
            context.insert(holiday)
        }

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
        fillBank(context)
        try? context.save()
    }

    /// The ready-made routines, and on a day that ends in candle lighting, a
    /// board whose first two things are already behind.
    private static func fillRoutines() {
        let store = Routines.shared
        if store.all.isEmpty {
            // One test run shows the eve before the family has a board of its own.
            let skipsBoard: Bool = Launch.screen == "erev-new"
            for template in Routines.templates where !(skipsBoard && template.isForCandles) {
                _ = store.add(template: template)
            }
        }
        guard JewishDay.of(.now).isEve, ErevBoard.done().isEmpty, let erev = store.forCandles else { return }
        for step in erev.steps.prefix(2) { ErevBoard.setDone(step.id, true) }
    }

    /// A few weeks of the daily practices: mostly kept, a miss here and there,
    /// one that is back today after a miss, and one that is still being built.
    private static func fillHabits(_ habits: [Habit]) {
        let calendar = Calendar.current
        let began: Date = calendar.date(byAdding: .day, value: -45, to: .now) ?? .now
        // The days back on which each practice was missed.
        let missed: [String: Set<Int>] = [
            "habit-mikveh": [6, 20, 21],
            "habit-torah": [1, 8, 9, 16],
            "habit-chitas": [5, 12],
            "habit-mincha": [8],
            "habit-tzedakah": [2, 4, 6, 7, 9, 11, 14, 15, 18, 20, 22, 23],
            "habit-arvit": [6, 19],
        ]
        let keptToday: Set<String> = ["habit-mikveh", "habit-shacharit", "habit-torah"]
        for habit in habits {
            habit.createdAt = began
            let skip: Set<Int> = missed[habit.id] ?? []
            var days: Set<String> = []
            for back in 1...40 where !skip.contains(back) {
                guard let day = calendar.date(byAdding: .day, value: -back, to: .now),
                      !JewishDay.of(day).isRest else { continue }
                days.insert(DayKey.of(day))
            }
            if keptToday.contains(habit.id) { days.insert(DayKey.of()) }
            habit.doneDays = DayKey.join(days, keep: 400)
        }
        if let torah = habits.first(where: { $0.id == "habit-torah" }) {
            torah.anchor = "אחרי שחרית"
            torah.small = "משנה אחת"
        }
        if let chitas = habits.first(where: { $0.id == "habit-chitas" }) {
            chitas.anchor = "אחרי שחרית"
        }
    }

    /// What the app would have learned from a few weeks of the family's days:
    /// how much gets done in a day, how estimates turn out, how days felt.
    private static func fillJournal() {
        let calendar = Calendar.current
        let done: [Int] = [90, 60, 120, 75, 105, 90, 45, 110, 80, 95, 70, 100]
        for (index, minutes) in done.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -(index + 1), to: .now) else { continue }
            DayJournal.note(planned: minutes + [0, 30, 15, 45][index % 4], done: minutes, on: day)
            DayJournal.setMood([3, 2, 3, 1, 2, 3][index % 6], on: day)
        }
        for pair in [(10, 14), (20, 28), (30, 41), (15, 20), (45, 62), (10, 13)] {
            DayJournal.addSample(estimate: pair.0, actual: pair.1)
        }
    }

    /// Made-up bank and card lines on real days, for this month and the two
    /// before it, so that the forecast has payments that return, a card bill
    /// on its way, a purchase in payments and a few lines to sort.
    private static func fillBank(_ context: ModelContext) {
        let calendar = Calendar.current
        let today: Date = calendar.startOfDay(for: .now)
        let noon: TimeInterval = 12 * 3600
        let monthly: [(Int, String, Int, String, String?)] = [
            (1, "משכורת שנייה", 6400, "income", "income.spouse"),
            (2, "שכר דירה", -4200, "home", "home.rent"),
            (5, "ארנונה", -420, "home", "home.arnona"),
            (9, "משכורת", 9800, "income", "income.salary"),
            (10, "כאל", -4650, "transfer", nil),
            (15, "קופת חולים", -210, "health", "health.kupah"),
            (20, "חוגים", -450, "kids", "kids.classes"),
        ]
        for back in 0...2 {
            for (index, line) in monthly.enumerated() {
                let date: Date = Forecast.day(line.0, inMonthOf: today, shift: -back)
                guard date <= today else { continue }
                let entry = LedgerEntry(
                    id: "demo-bank-\(back)-\(index)", date: date.addingTimeInterval(noon), title: line.1,
                    amount: Decimal(line.2), source: "דיסקונט", categoryID: line.3, sub: SubCategory.find(line.4))
                entry.account = "4821"
                context.insert(entry)
            }
        }

        // The card charges the bank on the 10th for what was bought up to the 8th.
        func charge(for purchase: Date) -> Date {
            let isEarly: Bool = calendar.component(.day, from: purchase) <= 8
            return Forecast.day(10, inMonthOf: purchase, shift: isEarly ? 0 : 1).addingTimeInterval(noon)
        }
        let purchases: [(Int, String, String, String?, String?)] = [
            (1, "רמי לוי", "-412.30", "food", "food.groceries"),
            (1, "חנות הפינה", "-74", nil, nil),
            (2, "פז", "-260", "transport", "transport.fuel"),
            (3, "סופר פארם", "-128.90", "food", "food.pharm"),
            (3, "א.ב. שירותים", "-230", nil, nil),
            (5, "קסטרו", "-240", "clothing", "clothing.clothes"),
            (6, "וולט", "-96", "gift", "gift.restaurants"),
            (6, "PAYBOX", "-60", nil, nil),
        ]
        for (index, line) in purchases.enumerated() {
            let date: Date = (calendar.date(byAdding: .day, value: -line.0, to: today) ?? today).addingTimeInterval(noon)
            let entry = LedgerEntry(
                id: "demo-card-\(index)", date: date, title: line.1, amount: Decimal(string: line.2) ?? 0,
                source: "כאל", categoryID: line.3, sub: SubCategory.find(line.4))
            entry.chargeDate = charge(for: date)
            entry.account = "7302"
            context.insert(entry)
        }
        let fridgeDay: Date = (calendar.date(byAdding: .day, value: -4, to: today) ?? today).addingTimeInterval(noon)
        let fridge = LedgerEntry(id: "demo-card-payments", date: fridgeDay, title: "מחסני חשמל", amount: -350,
                                 source: "כאל", categoryID: "home", sub: SubCategory.find("home.furniture"))
        fridge.installment = 3
        fridge.installments = 10
        fridge.chargeDate = charge(for: fridgeDay)
        fridge.account = "7302"
        context.insert(fridge)
        let waiting = LedgerEntry(id: "demo-card-pending", date: today.addingTimeInterval(noon), title: "יוחננוף",
                                  amount: Decimal(string: "-187.40") ?? 0, source: "כאל", categoryID: "food",
                                  sub: SubCategory.find("food.groceries"))
        waiting.pending = true
        waiting.chargeDate = today.addingTimeInterval(noon)
        waiting.account = "7302"
        context.insert(waiting)
    }

    /// Made-up monthly summaries for the half year before this month, in the
    /// shape of a family spreadsheet, so that trends and comparisons have
    /// something to show.
    private static func fillHistory(_ context: ModelContext) {
        let lines: [(String, String, Int, Bool)] = [
            ("income.salary", "משכורת", 9800, true), ("income.spouse", "משכורת שנייה", 6400, true),
            ("income.rentaid", "סיוע בשכר דירה", 900, true), ("income.business", "הכנסה מעסק", 2400, false),
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
                var share: Double = line.3 ? 1 : wobble[(back + index) % wobble.count]
                // Income from a business moves much more than the bills do.
                if line.0 == "income.business" { share = [0.4, 1.3, 0.8, 1.6, 0.5, 1.0][back % 6] }
                let amount: Int = Int((Double(line.2) * share).rounded())
                let group: String = String(line.0.prefix { $0 != "." })
                context.insert(LedgerEntry(
                    id: "demo-history-\(back)-\(index)", date: date, title: line.1,
                    amount: Decimal(amount), source: ExcelImport.source, categoryID: group,
                    sub: SubCategory.find(line.0)))
            }
        }
        // One heavy month, the kind a festival fund is for.
        if let heavy = calendar.date(byAdding: .month, value: -3, to: middle) {
            context.insert(LedgerEntry(
                id: "demo-history-heavy", date: heavy, title: "ריהוט ומוצרי חשמל", amount: -11800,
                source: ExcelImport.source, categoryID: "home", sub: SubCategory.find("home.furniture")))
        }
    }
}
