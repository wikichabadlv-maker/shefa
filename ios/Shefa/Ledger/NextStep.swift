import Foundation

/// A place inside the finance tab that another screen can open.
enum FinanceRoute: Hashable, Identifiable {
    case horizon, salary, status
    case category(String)

    var id: String {
        switch self {
        case .horizon: return "horizon"
        case .salary: return "salary"
        case .status: return "status"
        case .category(let id): return "category." + id
        }
    }
}

/// The one thing worth doing about the family's money right now. A screen
/// full of numbers leaves the reader to work out what matters; this says it.
struct NextStep: Identifiable {
    enum Target: Equatable {
        case none, review, budget, savings, maaser
        case route(FinanceRoute)
    }

    let id: String
    let symbol: String
    let title: String
    let text: String
    /// What the button says; nil when there is nothing to do.
    var button: String? = nil
    var target: Target = .none
    let artwork: Artwork
}

enum NextSteps {
    /// Picks the step, the most pressing first. Only for the current month.
    static func pick(entries: [LedgerEntry], summary: MonthSummary, budget: [BudgetLine],
                     horizon: Horizon?, now: Date = .now) -> NextStep {
        let calendar = Calendar.current
        let rose = Artwork(0xBE185D, 0x831843)
        let days: String = Ledger.daysText(summary.daysLeft)

        // 1. The bank account is about to go below zero.
        if let horizon, let low = horizon.firstBelowZero,
           (calendar.dateComponents([.day], from: now, to: low.date).day ?? 99) <= 14 {
            let day: String = low.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide))
            return NextStep(
                id: "dip", symbol: "arrow.down.right.circle.fill",
                title: "ב־\(day) החשבון צפוי לרדת מתחת לאפס",
                text: "לפי היתרה ומה שצפוי לרדת עד אז, יחסרו כ־\(Money.text(Decimal(-low.balance.rounded()))). אפשר לדחות תשלום, להקדים הכנסה או להעביר מהחיסכון.",
                button: "לקו האופק", target: .route(.horizon), artwork: rose)
        }

        // 2. The month went over what it can carry.
        if summary.remaining < 0 {
            return NextStep(
                id: "over", symbol: "pause.circle.fill",
                title: "החודש עבר את המסגרת ב־\(Money.text(-summary.remaining))",
                text: summary.daysLeft > 0
                    ? "נשארו עוד \(days). הכי מועיל עכשיו: לדחות את מה שאפשר, ולהחליט מאיפה מכסים את ההפרש."
                    : "שווה לראות איזו קבוצה גדלה, ולקבוע לה תקציב לחודש הבא.",
                button: "לתקציב", target: .budget, artwork: rose)
        }

        // 3. One group went over its budget.
        let spent: [String: Decimal] = Ledger.spentByCategory(entries, now: now)
        var worst: (category: SpendCategory, over: Decimal)? = nil
        for line in budget where line.limit > 0 {
            let used: Decimal = spent[line.categoryID] ?? 0
            guard used > line.limit, let category = SpendCategory.find(line.categoryID) else { continue }
            if worst == nil || used - line.limit > (worst?.over ?? 0) {
                worst = (category, used - line.limit)
            }
        }
        if let worst {
            return NextStep(
                id: "line-over", symbol: worst.category.symbol,
                title: "\(worst.category.title): \(Money.text(worst.over)) מעל התקציב",
                text: "אפשר להעביר מקבוצה שנשאר בה, או להעלות את התקציב אם זה המצב החדש.",
                button: "לקבוצה", target: .route(.category(worst.category.id)), artwork: worst.category.artwork)
        }

        // 4. Lines wait to be sorted.
        let questions: Int = Ledger.inMonth(entries, now).filter(\.needsAnswer).count
        if questions > 0 {
            return NextStep(
                id: "review", symbol: "square.stack.3d.up.fill",
                title: questions == 1 ? "תנועה אחת מחכה לבירור" : "\(questions) תנועות מחכות לבירור",
                text: "חצי דקה של הקשות, והמספרים של החודש מדויקים.",
                button: "בירור מהיר", target: .review, artwork: Theme.blue)
        }

        // 5. One group is spent faster than the days pass.
        if summary.daysLeft > 3 {
            var fastest: (category: SpendCategory, lead: Double, left: Decimal)? = nil
            for line in budget where line.limit > 0 {
                let used: Decimal = spent[line.categoryID] ?? 0
                let share: Double = (used / line.limit).double
                let lead: Double = share - summary.passed
                guard lead > 0.2, used <= line.limit, let category = SpendCategory.find(line.categoryID) else { continue }
                if fastest == nil || lead > (fastest?.lead ?? 0) {
                    fastest = (category, lead, line.limit - used)
                }
            }
            if let fastest {
                let perDay: Decimal = fastest.left / Decimal(max(summary.daysLeft, 1))
                return NextStep(
                    id: "line-fast", symbol: fastest.category.symbol,
                    title: "\(fastest.category.title) בקצב מהיר",
                    text: "נשארו בה \(Money.text(fastest.left)) לעוד \(days), כלומר כ־\(Money.text(perDay)) ליום.",
                    button: "לקבוצה", target: .route(.category(fastest.category.id)), artwork: Theme.amber)
            }
        }

        // 6. No budget yet, and there is a past to learn from.
        if Ledger.totalBudget(budget) <= 0, !Ledger.earlierMonths(entries, before: now).isEmpty {
            return NextStep(
                id: "budget", symbol: "wand.and.stars",
                title: "עוד אין תקציב",
                text: "יש הצעה מוכנה לפי ההוצאות שלכם בחודשים האחרונים. לחיצה אחת, ואחר כך אפשר לשנות כל שורה.",
                button: "לתקציב", target: .budget, artwork: Theme.violet)
        }

        // 7. A good month: more came in than the house salary.
        if summary.surplus > 0 {
            return NextStep(
                id: "surplus", symbol: "leaf.fill",
                title: "נכנסו \(Money.text(summary.surplus)) מעל משכורת הבית",
                text: "העודף נשאר בבנק ככרית לחודש חלש. אפשר גם להעביר חלק ממנו ליעד חיסכון.",
                button: "ליעדים", target: .savings, artwork: Theme.green)
        }

        // 8. Income that moves from month to month can be steadied.
        if summary.salary <= 0, let suggestion = Ledger.suggestedSalary(entries, now: now) {
            let incomes: [Decimal] = Ledger.incomeHistory(entries, before: now).map { $0.income }
            if let low = incomes.min(), let high = incomes.max(), high > 0, (high - low) / high > Decimal(string: "0.15") ?? 1 {
                return NextStep(
                    id: "salary", symbol: "equal.circle.fill",
                    title: "ההכנסה שלכם משתנה מחודש לחודש",
                    text: "משכורת בית קבועה של \(Money.text(suggestion)) הייתה מחזיקה ברוב החודשים. העודף של חודש טוב מכסה חודש חלש.",
                    button: "למשכורת הבית", target: .route(.salary), artwork: Artwork(0x0D9488, 0x115E59))
            }
        }

        // 9. The month is ending and maaser money still waits.
        let waiting: Decimal = summary.maaserDue - summary.maaserGiven
        if summary.daysLeft > 0, summary.daysLeft <= 7, waiting > 0 {
            return NextStep(
                id: "maaser", symbol: "heart.fill",
                title: "\(Money.text(waiting)) ממתינים לנתינה",
                text: "החודש מסתיים בעוד \(days).",
                button: "למעשר", target: .maaser, artwork: Theme.amber)
        }

        // 10. Nothing to do, and saying so is worth a card too.
        return NextStep(
            id: "calm", symbol: "checkmark.seal.fill", title: "הכול בשליטה",
            text: summary.daysLeft > 0
                ? "נשארו \(Money.text(summary.remaining)), שהם כ־\(Money.text(summary.perDay)) ליום עד סוף החודש. אין מה לעשות עכשיו."
                : "אין מה לעשות עכשיו.",
            artwork: Theme.emerald)
    }
}
