import SwiftData
import SwiftUI

/// The monthly budget, category by category.
struct BudgetList: View {
    let entries: [LedgerEntry]
    let month: Date
    /// The month's totals, to say what the plan leaves without a purpose.
    var summary: MonthSummary? = nil
    @Environment(\.modelContext) private var context
    @Query private var lines: [BudgetLine]
    @State private var editing: SpendCategory?

    private var categories: [SpendCategory] { SpendCategory.spending }

    private func applySuggestion() {
        let suggestion = Ledger.suggestedBudget(entries)
        for category in categories {
            let value = suggestion[category.id] ?? 0
            if let line = lines.first(where: { $0.categoryID == category.id }) {
                line.limit = value
                line.updatedAt = .now
            } else if value > 0 {
                context.insert(BudgetLine(categoryID: category.id, limit: value))
            }
        }
        try? context.save()
        SharedSync.shared.changed(in: context)
    }

    private func limit(_ category: SpendCategory) -> Decimal {
        lines.first { $0.categoryID == category.id }?.limit ?? 0
    }

    var body: some View {
        let spent = Ledger.spentByCategory(entries, now: month)
        let total = Ledger.totalBudget(lines)
        let used = categories.reduce(Decimal(0)) { $0 + (spent[$1.id] ?? 0) } + (spent[SpendCategory.unknown.id] ?? 0)

        BudgetHero(used: used, total: total, month: month, free: free(total))

        let ordered = categories.sorted { first, second in
            func rank(_ category: SpendCategory) -> Int {
                let cap = limit(category)
                let used = spent[category.id] ?? 0
                if cap > 0 && used > cap { return 0 }
                if isFast(used, cap) { return 1 }
                if cap > 0 || used > 0 { return 2 }
                return 3
            }
            return rank(first) < rank(second)
        }
        let unplanned = categories.filter { limit($0) == 0 && (spent[$0.id] ?? 0) > 0 }
        if total > 0, !unplanned.isEmpty {
            Label("\(unplanned.count) קטגוריות עם הוצאות ובלי תקציב: \(unplanned.prefix(3).map(\.title).joined(separator: ", "))",
                  systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.amberInk)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.amberGround, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        VStack(spacing: 0) {
            ForEach(ordered) { category in
                Button {
                    Feedback.tap()
                    editing = category
                } label: {
                    row(category, spent: spent[category.id] ?? 0, limit: limit(category))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                if category.id != ordered.last?.id {
                    Divider().padding(.leading, 54)
                }
            }
        }
        .padding(.horizontal, 14)
        .cardSurface()
        .sheet(item: $editing) { category in
            BudgetSheet(category: category, entries: entries, month: month)
        }
        .task {
            guard Launch.screen == "finance-budget-edit" else { return }
            try? await Task.sleep(for: .seconds(1))
            editing = SpendCategory.find("food")
        }

        Button {
            withAnimation(.snappy) { applySuggestion() }
        } label: {
            Label("הצעת תקציב לפי ההוצאות שלנו", systemImage: "wand.and.stars")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)

        Text("ההצעה היא הממוצע של החודשים האחרונים, בלי הוצאות חד פעמיות. לחיצה על קבוצה פותחת אותה לשינוי, עם חצי השנה האחרונה מול העיניים. הקו הקטן שעל כל פס מראה איפה היום בחודש.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }

    private func share(_ part: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: part / whole).doubleValue, 0), 1)
    }

    /// What the month's income leaves after maaser, savings and the whole
    /// budget; negative when the budget asks for more than there is.
    private func free(_ total: Decimal) -> Decimal? {
        guard let summary, total > 0, summary.income > 0, summary.daysLeft > 0 else { return nil }
        return summary.income - summary.maaserInPlan - summary.saved - total
    }

    /// How much of the month has passed, 0...1; 1 for earlier months.
    private var monthPassed: Double {
        let calendar = Calendar.current
        guard calendar.isDate(month, equalTo: .now, toGranularity: .month) else { return 1 }
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return Double(calendar.component(.day, from: .now)) / Double(count)
    }

    private var daysLeft: Int {
        let calendar = Calendar.current
        guard calendar.isDate(month, equalTo: .now, toGranularity: .month) else { return 0 }
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return count - calendar.component(.day, from: .now) + 1
    }

    /// Spending clearly ahead of the calendar, though still inside the budget.
    private func isFast(_ spent: Decimal, _ limit: Decimal) -> Bool {
        guard limit > 0, spent <= limit, monthPassed < 1 else { return false }
        return share(spent, of: limit) > monthPassed + 0.15
    }

    private func note(spent: Decimal, limit: Decimal) -> String {
        if spent > limit { return "חריגה של \(Money.text(spent - limit))" }
        let left = limit - spent
        if daysLeft > 0 {
            let perDay = Money.text(left / Decimal(daysLeft))
            return isFast(spent, limit) ? "קצב מהיר · נשארו \(Money.text(left)), כ־\(perDay) ליום"
                : "נשארו \(Money.text(left)), כ־\(perDay) ליום"
        }
        return "נשארו \(Money.text(left))"
    }

    private func row(_ category: SpendCategory, spent: Decimal, limit: Decimal) -> some View {
        let isOver = limit > 0 && spent > limit
        return HStack(spacing: 12) {
            ArtworkIcon(artwork: category.artwork, symbol: category.symbol)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(category.title).font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text(limit > 0 ? "\(Money.text(spent)) מתוך \(Money.text(limit))" : Money.text(spent))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isOver ? Color.red : Color.secondary)
                }
                if limit > 0 {
                    GrowBar(share: share(spent, of: limit), height: 6,
                            fill: isOver ? Color.red : (isFast(spent, limit) ? Color.orange : category.artwork.start))
                        .overlay(alignment: .leading) {
                            // Where today stands in the month: a bar that
                            // has passed the mark runs ahead of the days.
                            if monthPassed < 1 {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(Color.primary.opacity(0.55))
                                        .frame(width: 2, height: 12)
                                        .padding(.leading, max(proxy.size.width * CGFloat(monthPassed) - 1, 0))
                                        .offset(y: -3)
                                }
                                .accessibilityHidden(true)
                            }
                        }
                    Text(note(spent: spent, limit: limit))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOver ? Color.red : (isFast(spent, limit) ? Color.orange : Color.secondary))
                } else {
                    Text("ללא תקציב")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// The colorful summary on top of the budget.
struct BudgetHero: View {
    let used: Decimal
    let total: Decimal
    let month: Date
    /// What the month's income leaves outside the budget; nil when unknown.
    var free: Decimal? = nil

    private var share: Double {
        guard total > 0 else { return 0 }
        return min(max((used / total).double, 0), 1)
    }

    private var daysLeft: Int {
        let calendar = Calendar.current
        guard calendar.isDate(month, equalTo: .now, toGranularity: .month) else { return 0 }
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return count - calendar.component(.day, from: .now) + 1
    }

    private var line: String {
        if total <= 0 { return "עוד לא נקבע תקציב. אפשר להתחיל מההצעה שלמטה." }
        if used > total { return "חריגה של \(Money.text(used - total)) מהתקציב" }
        let left = total - used
        if daysLeft > 0 {
            return "נשארו \(Money.text(left)), שהם כ־\(Money.text(left / Decimal(daysLeft))) ליום"
        }
        return "נשארו \(Money.text(left)) מהתקציב"
    }

    var body: some View {
        let isOver = total > 0 && used > total
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("נוצל ב\(Ledger.monthName(month))")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(0.9)
                BigMoney(value: used.double, size: 46)
                if total > 0 {
                    Text("מתוך \(Money.text(total))")
                        .font(.system(size: 14, weight: .bold))
                        .opacity(0.9)
                }
                Text(line)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.9)
                    .padding(.top, 2)
                if let free, free != 0 {
                    Text(free > 0
                         ? "\(Money.text(free)) מההכנסה עוד בלי ייעוד."
                         : "התקציב גדול ב־\(Money.text(-free)) ממה שהחודש יכול לשאת.")
                        .font(.system(size: 13, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if total > 0 {
                ProgressRing(share: share, lineWidth: 10)
                    .frame(width: 92, height: 92)
                    .overlay {
                        CountUp(value: share) { $0.formatted(.percent.precision(.fractionLength(0))) }
                            .font(.system(size: 19, weight: .heavy))
                            .monospacedDigit()
                    }
            } else {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 34, weight: .bold))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .livingCard(isOver ? Artwork(0xDC2626, 0x991B1B) : Theme.violet, seed: 0.3)
        .accessibilityElement(children: .combine)
    }
}

/// A white progress ring for colorful cards. It draws itself when its
/// screen opens.
struct ProgressRing: View {
    let share: Double
    var lineWidth: CGFloat = 8
    var track: Color = .white.opacity(0.25)
    var fill: Color = .white
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let target: Double = min(max(share, 0), 1)
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: arrived || reduceMotion ? target : 0)
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 1.0).delay(0.15), value: arrived)
                .animation(.smooth(duration: 0.5), value: target)
        }
        .padding(lineWidth / 2)
        // A turn is mirrored in a right-to-left layout, which would start the
        // ring at the bottom.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// The family's savings goals. Maaser has its own section.
struct SavingsList: View {
    let month: MonthSummary
    let entries: [LedgerEntry]
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<SavingsGoal> { !$0.removed }, sort: \SavingsGoal.createdAt)
    private var goals: [SavingsGoal]
    @State private var editing: SavingsGoal?
    @State private var draft: GoalDraft?

    private var totalSaved: Decimal { goals.reduce(Decimal(0)) { $0 + $1.saved } }
    private var totalTarget: Decimal { goals.reduce(Decimal(0)) { $0 + $1.target } }

    private var emergencyTarget: Decimal {
        let cost = Ledger.monthlyLivingCost(entries)
        return Decimal(((cost * 3).double / 500).rounded(.up) * 500)
    }

    private var hasEmergency: Bool { goals.contains { $0.id == SavingsGoal.emergencyID } }

    var body: some View {
        savingsHero

        HStack {
            Text("יעדי חיסכון")
                .font(.system(size: 22, weight: .heavy))
            Spacer()
            Button("יעד חדש", systemImage: "plus") { draft = GoalDraft(palette: goals.count) }
                .font(.system(size: 15, weight: .bold))
        }
        .padding(.horizontal, 4)

        ForEach(goals) { goal in
            Button {
                editing = goal
            } label: {
                GoalCard(goal: goal)
            }
            .buttonStyle(.pressable)
        }

        if !hasEmergency && emergencyTarget > 0 {
            emergencyCard
        }

        if goals.isEmpty {
            ideas
        }

        OccasionFunds(goals: goals, entries: entries) { goal in
            editing = goal
        } start: { value in
            draft = value
        }
        .id("occasions")

        Color.clear
            .frame(height: 0)
            .sheet(item: $editing) { goal in
                GoalSheet(goal: goal, draft: GoalDraft(goal))
            }
            .sheet(item: $draft) { value in
                GoalSheet(goal: nil, draft: value)
            }
            .task {
                guard Launch.screen == "finance-goal" || Launch.screen == "finance-fund" else { return }
                try? await Task.sleep(for: .seconds(1))
                editing = Launch.screen == "finance-fund" ? goals.first { !$0.occasion.isEmpty } : goals.first
            }
    }

    /// Everything put aside so far, what went in this month, and what the
    /// goals ask for each month.
    private var savingsHero: some View {
        let share = totalTarget > 0 ? min((totalSaved / totalTarget).double, 1) : 0
        let monthly = goals.reduce(Decimal(0)) { $0 + ($1.left > 0 ? ($1.monthlyNeeded ?? 0) : 0) }
        let rate = month.income > 0 ? (month.saved / month.income).double : 0
        let line: String
        if goals.isEmpty {
            line = "יעד אחד ברור עם סכום ותאריך שווה יותר מכוונה טובה."
        } else if monthly > 0 {
            line = "כדי לעמוד בכל היעדים בזמן צריך לשים בצד \(Money.text(monthly)) בחודש."
        } else {
            line = "קבעו תאריך ליעד, והאפליקציה תחשב כמה לשים בצד בכל חודש."
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("חסכנו עד היום")
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(0.9)
                    BigMoney(value: totalSaved.double, size: 46)
                    if totalTarget > 0 {
                        Text("מתוך \(Money.text(totalTarget)) בכל היעדים")
                            .font(.system(size: 14, weight: .bold))
                            .opacity(0.9)
                    }
                }
                Spacer(minLength: 0)
                ProgressRing(share: share, lineWidth: 10)
                    .frame(width: 88, height: 88)
                    .overlay {
                        CountUp(value: share) { $0.formatted(.percent.precision(.fractionLength(0))) }
                            .font(.system(size: 19, weight: .heavy))
                            .monospacedDigit()
                    }
            }
            HStack(spacing: 0) {
                stat("נכנס החודש", Money.text(month.saved))
                Divider().frame(height: 28).overlay(.white.opacity(0.3))
                stat("מההכנסה", rate.formatted(.percent.precision(.fractionLength(0))))
                Divider().frame(height: 28).overlay(.white.opacity(0.3))
                stat("נדרש בחודש", monthly > 0 ? Money.text(monthly) : "לא נקבע")
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(line)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.92)
        }
        .foregroundStyle(.white)
        .padding(20)
        .livingCard(Theme.emerald, seed: 0.6)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var emergencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("קרן חירום", systemImage: "umbrella.fill")
                .font(.system(size: 17, weight: .heavy))
            Text("אנשי פיננסים ממליצים להחזיק בצד שלושה חודשי מחיה לפני כל חיסכון אחר. לפי ההוצאות שלכם אלה \(Money.text(emergencyTarget)).")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Button {
                draft = GoalDraft(id: SavingsGoal.emergencyID, title: "קרן חירום",
                                  targetText: Money.digits(emergencyTarget), symbol: "umbrella.fill", palette: 3)
            } label: {
                Text("הוספה כיעד")
                    .font(.system(size: 15, weight: .bold))
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.pressable)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var ideas: some View {
        let list: [GoalDraft] = [
            GoalDraft(title: "דירה משלנו", symbol: "house.fill", palette: 0),
            GoalDraft(title: "רכב", symbol: "car.fill", palette: 5),
            GoalDraft(title: "חופשה", symbol: "airplane", palette: 2),
            GoalDraft(title: "שמחה משפחתית", symbol: "gift.fill", palette: 1),
            GoalDraft(title: "חגים", symbol: "flame.fill", palette: 6),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("על מה חוסכים?")
                .font(.system(size: 18, weight: .heavy))
            Text("בחרו רעיון או צרו יעד משלכם. לכל יעד אפשר לקבוע סכום ותאריך, והאפליקציה תחשב כמה לשים בצד בכל חודש.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(list) { idea in
                        Button {
                            draft = idea
                        } label: {
                            Label(idea.title, systemImage: idea.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .background(Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// One savings goal as a wide colorful card.
struct GoalCard: View {
    let goal: SavingsGoal

    private var line: String {
        if goal.left <= 0 { return "הגעתם ליעד!" }
        if let monthly = goal.monthlyNeeded, let deadline = goal.deadline {
            let when = deadline.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide).year())
            return "\(Money.text(monthly)) לחודש עד \(when)"
        }
        if let arrival = goal.arrival {
            let when = arrival.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide).year())
            return "בקצב הזה: \(when)"
        }
        return "נשארו \(Money.text(goal.left))"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: goal.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.2), in: Circle())
                    Text(goal.title)
                        .font(.system(size: 18, weight: .heavy))
                        .lineLimit(1)
                }
                BigMoney(value: goal.saved.double, size: 36)
                Text("מתוך \(Money.text(goal.target)) · \(line)")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.9)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            LiquidOrb(share: goal.share)
                .frame(width: 78, height: 78)
                .overlay {
                    CountUp(value: goal.share) { $0.formatted(.percent.precision(.fractionLength(0))) }
                        .font(.system(size: 17, weight: .heavy))
                        .monospacedDigit()
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                }
        }
        .foregroundStyle(.white)
        .padding(18)
        .livingCard(goal.artwork, radius: 26, seed: Double(abs(goal.palette) % 8) * 0.37 + 0.2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// What the goal sheet works on before saving.
struct GoalDraft: Identifiable {
    var id = UUID().uuidString
    var title = ""
    var targetText = ""
    var savedText = ""
    var symbol = "star.fill"
    var palette = 0
    var hasDeadline = false
    var deadline = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    /// The yearly occasion a new fund is opened for.
    var occasion = ""

    init(id: String = UUID().uuidString, title: String = "", targetText: String = "",
         symbol: String = "star.fill", palette: Int = 0) {
        self.id = id
        self.title = title
        self.targetText = targetText
        self.symbol = symbol
        self.palette = palette
    }

    init(_ goal: SavingsGoal) {
        id = goal.id
        title = goal.title
        targetText = Money.digits(goal.target).replacingOccurrences(of: ",", with: "")
        savedText = Money.digits(goal.saved).replacingOccurrences(of: ",", with: "")
        symbol = goal.symbol
        palette = goal.palette
        hasDeadline = goal.deadline != nil
        if let date = goal.deadline { deadline = date }
        occasion = goal.occasion
    }
}

/// Create a goal, or change everything about an existing one.
struct GoalSheet: View {
    let goal: SavingsGoal?
    @State var draft: GoalDraft
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var moveText = ""
    @State private var confirmsDelete = false

    static let symbols = ["star.fill", "house.fill", "car.fill", "airplane", "gift.fill", "graduationcap.fill",
                          "heart.fill", "sun.max.fill", "umbrella.fill", "flame.fill", "figure.and.child.holdinghands",
                          "banknote.fill"]

    private var target: Decimal? {
        guard let value = Ledger.amount(from: draft.targetText), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty && target != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let goal {
                    Section {
                        GoalCard(goal: goal)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(quickAmounts(goal), id: \.self) { value in
                                    Button {
                                        move(value, sign: 1, goal: goal)
                                    } label: {
                                        Text(Money.text(value, showPlus: true))
                                            .font(.system(size: 16, weight: .heavy))
                                            .monospacedDigit()
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 16)
                                            .frame(height: 44)
                                            .background(goal.artwork.gradient, in: Capsule())
                                    }
                                    .buttonStyle(.pressable)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        TextField("סכום אחר", text: $moveText)
                            .keyboardType(.numberPad)
                        HStack(spacing: 10) {
                            moveButton("הפקדה", symbol: "plus", sign: 1, goal: goal)
                            moveButton("משיכה", symbol: "minus", sign: -1, goal: goal)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } header: {
                        Text("שמנו בצד? הקשה אחת")
                    } footer: {
                        Text(paceLine(goal))
                    }

                    let recent: [(month: String, amount: Decimal)] = Array(goal.deposits.suffix(6).reversed())
                    if !recent.isEmpty {
                        Section("מה נכנס, חודש אחרי חודש") {
                            ForEach(recent, id: \.month) { item in
                                HStack {
                                    Text(GoalSheet.monthTitle(item.month))
                                    Spacer()
                                    Text(Money.text(item.amount, showPlus: true))
                                        .font(.system(size: 16, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(item.amount > 0 ? Theme.accent : Color.primary)
                                }
                            }
                        }
                    }
                }

                Section("היעד") {
                    TextField("שם היעד", text: $draft.title)
                    LabeledContent("סכום היעד") {
                        TextField("בשקלים", text: $draft.targetText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("כבר נחסך") {
                        TextField("0", text: $draft.savedText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("תאריך יעד", isOn: $draft.hasDeadline)
                    if draft.hasDeadline {
                        DatePicker("להגיע עד", selection: $draft.deadline, in: Date.now..., displayedComponents: .date)
                    }
                }
                Section("מראה") {
                    SymbolGrid(symbols: GoalSheet.symbols, selection: $draft.symbol)
                    PaletteRow(selection: $draft.palette)
                }
                if goal != nil {
                    Section {
                        Button("מחיקת היעד", role: .destructive) { confirmsDelete = true }
                    }
                }
            }
            .navigationTitle(goal == nil ? "יעד חדש" : "עריכת יעד")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("למחוק את היעד?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("מחיקה", role: .destructive) {
                    if let goal {
                        goal.removed = true
                        goal.updatedAt = .now
                    }
                    finish()
                }
                Button("ביטול", role: .cancel) {}
            }
        }
        .arrives()
        .momentHost()
        .environment(\.layoutDirection, .rightToLeft)
    }

    /// "2026-11" as "נובמבר 2026".
    static func monthTitle(_ key: String) -> String {
        guard let date = DayKey.date(key + "-01") else { return key }
        return date.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide).year())
    }

    /// Round amounts for a deposit with one touch, and what the goal asks
    /// for this month when it has a date.
    private func quickAmounts(_ goal: SavingsGoal) -> [Decimal] {
        var result: [Decimal] = [50, 100, 200, 500]
        if let needed = goal.monthlyNeeded {
            let rounded: Decimal = Decimal((needed.double / 10).rounded(.up) * 10)
            if rounded > 0, !result.contains(rounded) { result.insert(rounded, at: 0) }
        }
        return result
    }

    /// What the last months say about when the goal will be reached.
    private func paceLine(_ goal: SavingsGoal) -> String {
        guard goal.left > 0 else { return "היעד מלא." }
        guard let pace = goal.monthlyPace, let arrival = goal.arrival else {
            return "כל הפקדה נרשמת כאן, וכך אפשר לראות לאן הקצב שלכם מוביל."
        }
        let when: String = arrival.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide).year())
        var text: String = "בחודשים האחרונים שמתם בצד כ־\(Money.text(pace)) בחודש. בקצב הזה תגיעו ליעד ב\(when)."
        if let deadline = goal.deadline, arrival > deadline, let needed = goal.monthlyNeeded {
            text += " כדי להגיע בתאריך שקבעתם צריך \(Money.text(needed)) בחודש."
        }
        return text
    }

    /// Puts money into the goal, or takes it out, and writes it in the log.
    private func move(_ value: Decimal, sign: Int, goal: SavingsGoal) {
        let next: Decimal = max(goal.saved + (sign > 0 ? value : -value), 0)
        let change: Decimal = next - goal.saved
        guard change != 0 else { return }
        let reaches: Bool = goal.target > 0 && goal.saved < goal.target && next >= goal.target
        withAnimation(.smooth(duration: 0.7)) {
            goal.saved = next
            goal.record(change)
            goal.updatedAt = .now
        }
        draft.savedText = Money.digits(next).replacingOccurrences(of: ",", with: "")
        moveText = ""
        try? context.save()
        SharedSync.shared.changed(in: context)
        if reaches {
            Moments.goalReached(goal)
        } else if sign > 0 {
            Feedback.done()
        } else {
            Feedback.tap()
        }
    }

    private func moveButton(_ title: String, symbol: String, sign: Int, goal: SavingsGoal) -> some View {
        Button {
            guard let value = Ledger.amount(from: moveText), value > 0 else { return }
            move(value, sign: sign, goal: goal)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(sign > 0 ? Color.white : Color.primary)
                .background(sign > 0 ? Theme.accent : Theme.chip, in: Capsule())
        }
        .buttonStyle(.pressable)
        .disabled(Ledger.amount(from: moveText) == nil)
    }

    private func save() {
        guard let target else { return }
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        let saved = Ledger.amount(from: draft.savedText) ?? 0
        if let goal {
            let reaches = goal.saved < goal.target && saved >= target
            goal.title = title
            goal.target = target
            // A figure corrected by hand is a deposit or a withdrawal too.
            if saved != goal.saved { goal.record(saved - goal.saved) }
            goal.saved = saved
            goal.symbol = draft.symbol
            goal.palette = draft.palette
            goal.deadline = draft.hasDeadline ? draft.deadline : nil
            goal.updatedAt = .now
            if reaches {
                // After the sheet has closed, on the screen behind it.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.6))
                    Moments.goalReached(goal)
                }
            }
        } else {
            let created = SavingsGoal(id: draft.id, title: title, saved: saved, target: target,
                                      symbol: draft.symbol, palette: draft.palette)
            created.deadline = draft.hasDeadline ? draft.deadline : nil
            created.occasion = draft.occasion
            context.insert(created)
        }
        finish()
    }

    private func finish() {
        try? context.save()
        SharedSync.shared.changed(in: context)
        dismiss()
    }
}
