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

    private var categories: [SpendCategory] {
        SpendCategory.all.filter { $0.id != SpendCategory.incomeID && $0.id != SpendCategory.maaserID && !SpendCategory.notSpending.contains($0.id) }
    }

    private func limit(_ category: SpendCategory) -> Decimal {
        lines.first { $0.categoryID == category.id }?.limit ?? 0
    }

    var body: some View {
        let spent = Ledger.spentByCategory(entries, now: month)
        let total = Ledger.totalBudget(lines)
        let used = categories.reduce(Decimal(0)) { $0 + (spent[$1.id] ?? 0) } + (spent[SpendCategory.unknown.id] ?? 0)

        VStack(alignment: .leading, spacing: 8) {
            Text("נוצל בחודש זה")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(Money.text(used))
                .font(.system(size: 40, weight: .heavy))
                .monospacedDigit()
            ProgressView(value: share(used, of: total))
                .tint(used > total ? Color.red : Theme.accent)
            Text("מתוך תקציב של \(Money.text(total))")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()

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

        Text("לחיצה על קטגוריה מאפשרת לקבוע לה תקציב.")
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

/// Maaser for the month and the family's savings goals.
struct SavingsList: View {
    let month: MonthSummary
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<SavingsGoal> { !$0.removed }, sort: \SavingsGoal.createdAt)
    private var goals: [SavingsGoal]
    @State private var isAdding = false
    @State private var depositing: SavingsGoal?
    @State private var amountText = ""

    var body: some View {
        MaaserCard(month: month)

        HStack {
            Text("יעדי חיסכון")
                .font(.system(size: 22, weight: .heavy))
            Spacer()
            Button("יעד חדש", systemImage: "plus") { isAdding = true }
                .font(.system(size: 15, weight: .bold))
        }
        .padding(.horizontal, 4)

        if goals.isEmpty {
            ContentUnavailableView("עוד אין יעדים", systemImage: "target",
                                   description: Text("הוסיפו יעד ראשון ועקבו אחרי ההתקדמות."))
        } else {
            VStack(spacing: 0) {
                ForEach(goals) { goal in
                    Button {
                        amountText = ""
                        depositing = goal
                    } label: {
                        row(goal).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("מחיקת היעד", systemImage: "trash", role: .destructive) {
                            goal.removed = true
                            goal.updatedAt = .now
                            try? context.save()
                            SharedSync.shared.changed(in: context)
                        }
                    }
                    if goal.id != goals.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
            .alert("הפקדה ליעד", isPresented: isDepositing) {
                TextField("סכום בשקלים", text: $amountText)
                    .keyboardType(.numberPad)
                Button("הוספה") { deposit() }
                Button("ביטול", role: .cancel) {}
            } message: {
                Text(depositing?.title ?? "")
            }
        }

        Color.clear
            .frame(height: 0)
            .sheet(isPresented: $isAdding) {
                GoalEditor(nextPalette: goals.count)
            }
    }

    private var isDepositing: Binding<Bool> {
        Binding(get: { depositing != nil }, set: { if !$0 { depositing = nil } })
    }

    private func deposit() {
        guard let goal = depositing, let value = Ledger.amount(from: amountText) else { return }
        goal.saved += value
        goal.updatedAt = .now
        try? context.save()
        SharedSync.shared.changed(in: context)
        depositing = nil
    }

    private func row(_ goal: SavingsGoal) -> some View {
        HStack(spacing: 12) {
            ArtworkIcon(artwork: goal.artwork, symbol: goal.symbol)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(goal.title).font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text(goal.share, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                }
                ProgressView(value: goal.share).tint(goal.artwork.start)
                Text("\(Money.text(goal.saved)) מתוך \(Money.text(goal.target))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// A sheet for adding a new savings goal.
struct GoalEditor: View {
    let nextPalette: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var targetText = ""
    @State private var symbol = "star.fill"

    private let symbols = ["star.fill", "house.fill", "car.fill", "airplane", "gift.fill",
                           "graduationcap.fill", "heart.fill", "sun.max.fill"]

    private var target: Decimal? {
        guard let value = Ledger.amount(from: targetText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("על מה חוסכים") {
                    TextField("שם היעד", text: $title)
                    TextField("סכום היעד בשקלים", text: $targetText)
                        .keyboardType(.numberPad)
                }
                Section("סמל") {
                    HStack {
                        ForEach(symbols, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .foregroundStyle(symbol == item ? Color.white : Color.primary)
                                    .background(symbol == item ? Theme.accent : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(symbol == item ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle("יעד חדש")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        guard let target else { return }
                        context.insert(SavingsGoal(
                            title: title.trimmingCharacters(in: .whitespaces),
                            target: target, symbol: symbol, palette: nextPalette))
                        try? context.save()
                        SharedSync.shared.changed(in: context)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || target == nil)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium])
    }
}
