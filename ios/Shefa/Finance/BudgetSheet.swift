import Charts
import SwiftData
import SwiftUI

/// Setting the monthly budget of one group, with the family's own past in
/// front of the eyes: what an ordinary month costs there, and in how many
/// months a figure would have held.
struct BudgetSheet: View {
    let category: SpendCategory
    let entries: [LedgerEntry]
    let month: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var lines: [BudgetLine]
    /// The figure on the screen, before it is saved.
    @State private var draft: Decimal = 0
    @State private var isLoaded = false
    @State private var isTyping = false
    @State private var typed = ""

    private struct Bar: Identifiable {
        let id: Int
        let label: String
        let amount: Double
    }

    /// A figure the family can take with one touch.
    private struct Idea: Identifiable {
        let id: String
        let amount: Decimal
    }

    private var saved: Decimal {
        lines.first { $0.categoryID == category.id }?.limit ?? 0
    }

    private func spent(in date: Date) -> Decimal {
        var sum = Decimal(0)
        for entry in Ledger.inMonth(entries, date) where entry.categoryID == category.id && entry.amount < 0 {
            sum -= entry.amount
        }
        return sum
    }

    /// The six months before the one on the screen, the oldest first.
    private var bars: [Bar] {
        let calendar = Calendar.current
        var result: [Bar] = []
        for back in stride(from: 6, through: 1, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -back, to: month) else { continue }
            result.append(Bar(id: back, label: Ledger.monthName(date, short: true), amount: spent(in: date).double))
        }
        return result
    }

    private static func round50(_ value: Double) -> Decimal {
        Decimal((value / 50).rounded(.up) * 50)
    }

    private func ideas(_ past: [Bar]) -> [Idea] {
        let active: [Double] = past.map { $0.amount }.filter { $0 > 0 }
        var result: [Idea] = []
        if let usual = Ledger.suggestedBudget(entries, now: month)[category.id], usual > 0 {
            result.append(Idea(id: "חודש רגיל", amount: usual))
        }
        if let last = past.last, last.amount > 0 {
            result.append(Idea(id: "החודש שעבר", amount: BudgetSheet.round50(last.amount)))
        }
        if let heavy = active.max() {
            result.append(Idea(id: "החודש הכבד", amount: BudgetSheet.round50(heavy)))
        }
        var seen: Set<Decimal> = []
        return result.filter { seen.insert($0.amount).inserted }
    }

    var body: some View {
        let past: [Bar] = bars
        let list: [Idea] = ideas(past)
        let now: Decimal = spent(in: month)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                        .cascade(0)
                    if !list.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(list) { idea in
                                ideaChip(idea)
                            }
                        }
                        .cascade(1)
                    }
                    if past.contains(where: { $0.amount > 0 }) {
                        chartCard(past)
                            .cascade(2)
                    }
                    monthCard(now)
                        .cascade(3)
                    if saved > 0 {
                        Button("הסרת התקציב של הקבוצה", role: .destructive) {
                            store(0)
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .navigationTitle("תקציב חודשי")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { store(draft) }
                        .disabled(draft == saved)
                }
            }
            .alert(category.title, isPresented: $isTyping) {
                TextField("סכום לחודש", text: $typed)
                    .keyboardType(.numberPad)
                Button("אישור") {
                    if let value = Ledger.amount(from: typed) {
                        withAnimation(.snappy) { draft = value }
                    }
                }
                Button("ביטול", role: .cancel) {}
            } message: {
                Text("כמה מתכננים להוציא בקבוצה הזאת בחודש.")
            }
        }
        .arrives()
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.large])
        .onAppear {
            guard !isLoaded else { return }
            isLoaded = true
            // A group with no budget yet starts from an ordinary month.
            draft = saved > 0 ? saved : (Ledger.suggestedBudget(entries, now: month)[category.id] ?? 0)
        }
    }

    private func step(_ by: Decimal) {
        Feedback.tap()
        withAnimation(.snappy) { draft = max(draft + by, 0) }
    }

    private func store(_ value: Decimal) {
        if let line = lines.first(where: { $0.categoryID == category.id }) {
            line.limit = value
            line.updatedAt = .now
        } else if value > 0 {
            context.insert(BudgetLine(categoryID: category.id, limit: value))
        }
        try? context.save()
        SharedSync.shared.changed(in: context)
        if value > 0 { Feedback.done() } else { Feedback.tap() }
        dismiss()
    }

    private func startTyping() {
        typed = draft > 0 ? Money.digits(draft).replacingOccurrences(of: ",", with: "") : ""
        isTyping = true
    }

    /// The group and its figure, on the group's own color.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.2), in: Circle())
                Text(category.title)
                    .font(.system(size: 20, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Button {
                startTyping()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BigMoney(value: draft.double, size: 56, duration: 0.45)
                    Text("לחודש")
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(0.9)
                }
            }
            .buttonStyle(.pressable)
            .accessibilityHint("הקלדת סכום")
            HStack(spacing: 8) {
                stepButton("minus", "פחות חמישים") { step(-50) }
                stepButton("plus", "עוד חמישים") { step(50) }
                Button {
                    startTyping()
                } label: {
                    Text("הקלדת סכום")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(category.artwork, radius: 26, seed: 0.5, watermark: category.symbol)
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .heavy))
                .frame(width: 52, height: 40)
                .background(.white.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.pressable)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private func ideaChip(_ idea: Idea) -> some View {
        let isOn: Bool = idea.amount == draft
        return Button {
            Feedback.tap()
            withAnimation(.snappy) { draft = idea.amount }
        } label: {
            VStack(spacing: 1) {
                Text(idea.id)
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.85)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(Money.text(idea.amount))
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? AnyShapeStyle(category.artwork.gradient) : AnyShapeStyle(Theme.card),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(isOn ? 0 : 0.06), radius: 8, y: 4)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The last half year in this group, against the figure on the screen.
    private func chartCard(_ past: [Bar]) -> some View {
        let limit: Double = draft.double
        let active: [Bar] = past.filter { $0.amount > 0 }
        let within: Int = active.filter { $0.amount <= limit }.count
        let over: Color = Color(hex: 0xE11D48)
        return VStack(alignment: .leading, spacing: 12) {
            Text("חצי השנה האחרונה")
                .font(.system(size: 20, weight: .heavy))
            Chart {
                ForEach(past) { bar in
                    BarMark(x: .value("חודש", bar.label), y: .value("סכום", bar.amount))
                        .cornerRadius(5)
                        .foregroundStyle(limit > 0 && bar.amount > limit
                                         ? AnyShapeStyle(over.opacity(0.8))
                                         : AnyShapeStyle(category.artwork.gradient))
                }
                if limit > 0 {
                    RuleMark(y: .value("תקציב", limit))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(number >= 1000 ? "\(Int(number / 1000))K" : "\(Int(number))")
                        }
                    }
                }
            }
            .frame(height: 170)
            // Room for the top label of the axis, which sits half above the chart.
            .padding(.top, 8)
            .reveal(.bottom, delay: 0.3)
            .animation(.smooth(duration: 0.3), value: draft)
            if limit > 0, !active.isEmpty {
                Text(within == active.count
                     ? "בכל \(active.count) החודשים האחרונים הייתם בתוך הסכום הזה."
                     : (within == 0
                        ? "באף אחד מ־\(active.count) החודשים האחרונים לא הייתם בתוך הסכום הזה."
                        : "ב־\(within) מתוך \(active.count) החודשים האחרונים הייתם בתוך הסכום הזה."))
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// The month on the screen against the figure.
    private func monthCard(_ now: Decimal) -> some View {
        let calendar = Calendar.current
        let isCurrent: Bool = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        let count: Int = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let daysLeft: Int = isCurrent ? count - calendar.component(.day, from: .now) + 1 : 0
        let left: Decimal = draft - now
        let share: Double = draft > 0 ? min(max((now / draft).double, 0), 1) : 0
        var line: String = ""
        if draft <= 0 {
            line = "בלי תקציב, הקבוצה רק נמדדת."
        } else if left < 0 {
            line = "עם הסכום הזה החודש כבר בחריגה של \(Money.text(-left))."
        } else if daysLeft > 0 {
            line = "נשארים \(Money.text(left)) לעוד \(Ledger.daysText(daysLeft)), כ־\(Money.text(left / Decimal(daysLeft))) ליום."
        } else {
            line = "החודש נסגר עם \(Money.text(left)) שנשארו."
        }
        let shown: String = line
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("ב\(Ledger.monthName(month))")
                    .font(.system(size: 20, weight: .heavy))
                Spacer()
                Text("יצאו \(Money.text(now))")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if draft > 0 {
                GrowBar(share: share, height: 10, delay: 0.3,
                        fill: left < 0 ? AnyShapeStyle(Color(hex: 0xE11D48)) : AnyShapeStyle(category.artwork.gradient))
                    .animation(.smooth(duration: 0.3), value: draft)
            }
            Text(shown)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
