import SwiftData
import SwiftUI

/// The monthly budget, category by category.
struct BudgetList: View {
    let entries: [LedgerEntry]
    let month: Date
    @Environment(\.modelContext) private var context
    @Query private var lines: [BudgetLine]
    @State private var editing: SpendCategory?
    @State private var amountText = ""

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

        BudgetHero(used: used, total: total, month: month)

        VStack(spacing: 0) {
            ForEach(categories) { category in
                Button {
                    let current = limit(category)
                    amountText = current > 0 ? Money.digits(current) : ""
                    editing = category
                } label: {
                    row(category, spent: spent[category.id] ?? 0, limit: limit(category))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if category.id != categories.last?.id {
                    Divider().padding(.leading, 54)
                }
            }
        }
        .padding(.horizontal, 14)
        .cardSurface()
        .alert("תקציב חודשי", isPresented: isEditing) {
            TextField("סכום בשקלים", text: $amountText)
                .keyboardType(.numberPad)
            Button("שמירה") { save() }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text(editing?.title ?? "")
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

        Text("ההצעה היא הממוצע של החודשים האחרונים, בלי הוצאות חד פעמיות. לחיצה על קטגוריה מאפשרת לשנות.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }

    private var isEditing: Binding<Bool> {
        Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
    }

    private func share(_ part: Decimal, of whole: Decimal) -> Double {
        guard whole > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: part / whole).doubleValue, 0), 1)
    }

    private func save() {
        guard let category = editing else { return }
        let value = Ledger.amount(from: amountText) ?? 0
        if let line = lines.first(where: { $0.categoryID == category.id }) {
            line.limit = value
            line.updatedAt = .now
        } else {
            context.insert(BudgetLine(categoryID: category.id, limit: value))
        }
        try? context.save()
        SharedSync.shared.changed(in: context)
        editing = nil
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
                    ProgressView(value: share(spent, of: limit))
                        .tint(isOver ? Color.red : category.artwork.start)
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
                Text(Money.text(used))
                    .font(.system(size: 42, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if total > 0 {
                    Text("מתוך \(Money.text(total))")
                        .font(.system(size: 14, weight: .bold))
                        .opacity(0.9)
                }
                Text(line)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.9)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            ProgressRing(share: share, lineWidth: 10)
                .frame(width: 92, height: 92)
                .overlay {
                    Text(share, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 19, weight: .heavy))
                        .monospacedDigit()
                }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background((isOver ? Artwork(0xDC2626, 0x991B1B) : Theme.violet).gradient,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: (isOver ? Color(hex: 0x991B1B) : Color(hex: 0x4C1D95)).opacity(0.4), radius: 20, y: 12)
        .accessibilityElement(children: .combine)
    }
}

/// A white progress ring for colorful cards.
struct ProgressRing: View {
    let share: Double
    var lineWidth: CGFloat = 8
    var track: Color = .white.opacity(0.25)
    var fill: Color = .white

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(share, 0), 1))
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Maaser for the month and the family's savings goals.
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
        MaaserCard(month: month)

        HStack {
            Text("יעדי חיסכון")
                .font(.system(size: 22, weight: .heavy))
            Spacer()
            Button("יעד חדש", systemImage: "plus") { draft = GoalDraft(palette: goals.count) }
                .font(.system(size: 15, weight: .bold))
        }
        .padding(.horizontal, 4)

        if goals.count > 1 {
            totalCard
        }

        ForEach(goals) { goal in
            Button {
                editing = goal
            } label: {
                GoalCard(goal: goal)
            }
            .buttonStyle(.plain)
        }

        if !hasEmergency && emergencyTarget > 0 {
            emergencyCard
        }

        if goals.isEmpty {
            ideas
        }

        Color.clear
            .frame(height: 0)
            .sheet(item: $editing) { goal in
                GoalSheet(goal: goal, draft: GoalDraft(goal))
            }
            .sheet(item: $draft) { value in
                GoalSheet(goal: nil, draft: value)
            }
    }

    private var totalCard: some View {
        let share = totalTarget > 0 ? (totalSaved / totalTarget).double : 0
        return HStack(spacing: 14) {
            ProgressRing(share: share, lineWidth: 7, track: Theme.chip, fill: Theme.accent)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 1) {
                Text("חסכנו עד היום")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(Money.text(totalSaved))
                    .font(.system(size: 26, weight: .heavy))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text("מתוך")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(Money.text(totalTarget))
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
            }
        }
        .padding(16)
        .cardSurface()
        .accessibilityElement(children: .combine)
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
            .buttonStyle(.plain)
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
                        .buttonStyle(.plain)
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
                Text(Money.text(goal.saved))
                    .font(.system(size: 32, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("מתוך \(Money.text(goal.target)) · \(line)")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.9)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            ProgressRing(share: goal.share, lineWidth: 8)
                .frame(width: 72, height: 72)
                .overlay {
                    Text(goal.share, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 16, weight: .heavy))
                        .monospacedDigit()
                }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(goal.artwork.gradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: goal.artwork.end.opacity(0.35), radius: 16, y: 10)
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
                        TextField("סכום בשקלים", text: $moveText)
                            .keyboardType(.numberPad)
                        HStack(spacing: 10) {
                            moveButton("הפקדה", symbol: "plus", sign: 1, goal: goal)
                            moveButton("משיכה", symbol: "minus", sign: -1, goal: goal)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } header: {
                        Text("שמנו בצד? משכנו?")
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
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func moveButton(_ title: String, symbol: String, sign: Int, goal: SavingsGoal) -> some View {
        Button {
            guard let value = Ledger.amount(from: moveText), value > 0 else { return }
            let next = max(goal.saved + (sign > 0 ? value : -value), 0)
            withAnimation(.snappy) {
                goal.saved = next
                goal.updatedAt = .now
            }
            draft.savedText = Money.digits(next).replacingOccurrences(of: ",", with: "")
            moveText = ""
            try? context.save()
            SharedSync.shared.changed(in: context)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(sign > 0 ? Color.white : Color.primary)
                .background(sign > 0 ? Theme.accent : Theme.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(Ledger.amount(from: moveText) == nil)
    }

    private func save() {
        guard let target else { return }
        let title = draft.title.trimmingCharacters(in: .whitespaces)
        let saved = Ledger.amount(from: draft.savedText) ?? 0
        if let goal {
            goal.title = title
            goal.target = target
            goal.saved = saved
            goal.symbol = draft.symbol
            goal.palette = draft.palette
            goal.deadline = draft.hasDeadline ? draft.deadline : nil
            goal.updatedAt = .now
        } else {
            let created = SavingsGoal(id: draft.id, title: title, saved: saved, target: target,
                                      symbol: draft.symbol, palette: draft.palette)
            created.deadline = draft.hasDeadline ? draft.deadline : nil
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
