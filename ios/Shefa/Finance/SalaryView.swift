import Charts
import SwiftUI

/// The house salary: one steady amount the home pays itself every month, so
/// that a good month covers a lean one. The screen opens in teal.
struct SalaryView: View {
    /// The lines the month totals are made of.
    let entries: [LedgerEntry]

    static let artwork = Artwork(0x0D9488, 0x115E59)

    private struct Month: Identifiable {
        let id: Int
        let label: String
        let income: Double
    }

    /// A figure the family can take with one touch.
    private struct Idea: Identifiable {
        let id: String
        let amount: Decimal
    }

    @State private var plan = FinancePlan.shared
    @State private var bank = BankState.shared
    /// The figure on the screen, before it is saved.
    @State private var draft: Decimal = FinancePlan.shared.salary
    /// True once the big title has scrolled away under the bar.
    @State private var isScrolled = false
    @State private var isTyping = false
    @State private var typed = ""
    @State private var confirmsRemoval = false
    @Environment(\.layoutDirection) private var direction

    private static func round100(_ value: Decimal) -> Decimal {
        Decimal((value.double / 100).rounded(.down) * 100)
    }

    private func ideas(_ incomes: [Decimal]) -> [Idea] {
        guard !incomes.isEmpty else { return [] }
        var result: [Idea] = []
        if let careful = Ledger.suggestedSalary(entries) {
            result.append(Idea(id: "זהירה", amount: careful))
        }
        let average: Decimal = incomes.reduce(Decimal(0)) { $0 + $1 } / Decimal(incomes.count)
        result.append(Idea(id: "הממוצע", amount: SalaryView.round100(average)))
        if let lowest = incomes.min() {
            result.append(Idea(id: "החודש החלש", amount: SalaryView.round100(lowest)))
        }
        var seen: Set<Decimal> = []
        return result.filter { $0.amount > 0 && seen.insert($0.amount).inserted }
    }

    var body: some View {
        let past: [(month: Date, income: Decimal)] = Ledger.incomeHistory(entries)
        let incomes: [Decimal] = past.map { $0.income }
        let summary: MonthSummary = Ledger.summary(entries)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                    .cascade(0)
                explanation
                    .cascade(1)
                if !past.isEmpty {
                    chartCard(past, incomes: incomes)
                        .cascade(2)
                }
                if plan.salary > 0 {
                    monthCard(summary)
                        .cascade(3)
                }
                if plan.salary > 0 {
                    Button("ביטול משכורת הבית", role: .destructive) {
                        confirmsRemoval = true
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .cascade(4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .background(alignment: .top) {
                StageBackdrop(artwork: SalaryView.artwork, height: 470)
            }
        }
        .background(Theme.ground)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 110
        } action: { _, isPast in
            withAnimation(.smooth(duration: 0.25)) { isScrolled = isPast }
        }
        .task {
            // A test run can open the screen lower down.
            guard !Launch.anchor.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1.5))
            proxy.scrollTo(Launch.anchor, anchor: .top)
        }
        }
        .navigationTitle("משכורת הבית")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The name waits in the bar until the big title scrolls away.
            ToolbarItem(placement: .principal) {
                Text("משכורת הבית")
                    .font(.system(size: 17, weight: .semibold))
                    .opacity(isScrolled ? 1 : 0)
            }
        }
        .toolbarColorScheme(isScrolled ? nil : .dark, for: .navigationBar)
        .arrives()
        .onAppear {
            // A home that has not set one yet starts from the careful figure.
            if draft <= 0, let careful = Ledger.suggestedSalary(entries) { draft = careful }
        }
        .onChange(of: plan.salary) { _, value in
            // A salary that arrives from elsewhere, such as a restored
            // backup, is the one on the screen.
            if value > 0 { draft = value }
        }
        .alert("משכורת הבית", isPresented: $isTyping) {
            TextField("סכום לחודש", text: $typed)
                .keyboardType(.numberPad)
            Button("אישור") {
                if let value = Ledger.amount(from: typed) {
                    withAnimation(.snappy) { draft = value }
                }
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("הסכום שהבית משלם לעצמו בכל חודש.")
        }
        .confirmationDialog("לבטל את משכורת הבית?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("ביטול משכורת הבית", role: .destructive) {
                withAnimation(.section) { plan.setSalary(0) }
            }
            Button("להשאיר", role: .cancel) {}
        } message: {
            Text("החודש יחזור להיבנות על מה שנכנס בפועל.")
        }
    }

    // MARK: The stage

    private var isChanged: Bool { draft > 0 && draft != plan.salary }

    private func step(_ by: Decimal) {
        Feedback.tap()
        withAnimation(.snappy) { draft = max(draft + by, 0) }
    }

    private func save() {
        let isFirst: Bool = plan.salary <= 0
        withAnimation(.section) { plan.setSalary(draft) }
        if isFirst {
            let shown: Bool = Moments.shared.play(
                "salary", symbol: "equal.circle.fill", title: "משכורת הבית נקבעה",
                text: "מעכשיו החודש נבנה על \(Money.text(draft)), גם כשנכנס יותר וגם כשנכנס פחות.",
                artwork: SalaryView.artwork)
            if !shown { Feedback.done() }
        } else {
            Feedback.done()
        }
    }

    /// The top of the stage: white type straight on the color, no card.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "equal.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 60, height: 60)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                Spacer()
                Text(plan.salary > 0 ? (isChanged ? "שינוי שעוד לא נשמר" : "נקבעה") : "עוד לא נקבעה")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(.white.opacity(0.2), in: Capsule())
                    .contentTransition(.opacity)
            }
            Text("משכורת הבית")
                .font(.system(size: 34, weight: .heavy))
                .padding(.top, 6)
            Button {
                typed = draft > 0 ? Money.digits(draft).replacingOccurrences(of: ",", with: "") : ""
                isTyping = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BigMoney(value: draft.double, size: 62, duration: 0.5)
                    Text("בחודש")
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(0.9)
                }
            }
            .buttonStyle(.pressable)
            .accessibilityHint("הקלדת סכום")
            HStack(spacing: 8) {
                stepButton("minus", "פחות מאה") { step(-100) }
                stepButton("plus", "עוד מאה") { step(100) }
                Button {
                    typed = draft > 0 ? Money.digits(draft).replacingOccurrences(of: ",", with: "") : ""
                    isTyping = true
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
            if isChanged {
                Button {
                    save()
                } label: {
                    Text(plan.salary > 0 ? "שמירת השינוי" : "קביעת משכורת הבית")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(SalaryView.artwork.end)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 6)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.section, value: isChanged)
        .background(alignment: .bottomTrailing) {
            Image(systemName: "equal.circle.fill")
                .font(.system(size: 180, weight: .bold))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: direction == .rightToLeft ? -40 : 40, y: 26)
                .accessibilityHidden(true)
        }
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

    // MARK: Cards

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("איך זה עובד")
                .font(.system(size: 20, weight: .heavy))
            point("arrow.up.circle.fill", Theme.green, "בחודש טוב",
                  "מה שנכנס מעל המשכורת נשאר בבנק, ככרית.")
            point("arrow.down.circle.fill", Theme.amber, "בחודש חלש",
                  "הכרית משלימה את החסר, והחודש נראה אותו דבר.")
            point("calendar", Theme.blue, "כל חודש",
                  "התקציב ומה שנשאר לחיות ממנו נבנים על המשכורת, ולא על מה שנכנס באותו חודש.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func point(_ symbol: String, _ artwork: Artwork, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkIcon(artwork: artwork, symbol: symbol, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func chartCard(_ past: [(month: Date, income: Decimal)], incomes: [Decimal]) -> some View {
        var months: [Month] = []
        for (index, item) in past.reversed().enumerated() {
            months.append(Month(id: index, label: Ledger.monthName(item.month, short: true),
                                income: item.income.double))
        }
        let bars: [Month] = months
        let salary: Double = draft.double
        let reached: Int = bars.filter { $0.income >= salary }.count
        let list: [Idea] = ideas(incomes)
        let low: Color = Color(hex: 0xF59E0B)
        return VStack(alignment: .leading, spacing: 12) {
            Text("ההכנסה שלכם, חודש אחרי חודש")
                .font(.system(size: 20, weight: .heavy))
            Chart {
                ForEach(bars) { bar in
                    BarMark(x: .value("חודש", bar.label), y: .value("הכנסה", bar.income))
                        .cornerRadius(5)
                        .foregroundStyle(bar.income >= salary
                                         ? AnyShapeStyle(SalaryView.artwork.gradient)
                                         : AnyShapeStyle(low.opacity(0.8)))
                }
                if salary > 0 {
                    RuleMark(y: .value("משכורת הבית", salary))
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
            .frame(height: 190)
            // Room for the top label of the axis, which sits half above the chart.
            .padding(.top, 8)
            .reveal(.bottom, delay: 0.35)
            .animation(.smooth(duration: 0.3), value: draft)
            if salary > 0 {
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.75))
                            .frame(width: 14, height: 2)
                        Text("משכורת הבית")
                    }
                    HStack(spacing: 5) {
                        Circle().fill(low.opacity(0.8)).frame(width: 8, height: 8)
                        Text("חודש שנכנס בו פחות")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                Text(reached == bars.count
                     ? "בכל \(bars.count) החודשים האחרונים נכנס לפחות \(Money.text(draft))."
                     : "ב־\(reached) מתוך \(bars.count) החודשים האחרונים נכנס לפחות \(Money.text(draft)).")
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }
            if !list.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("אפשר להתחיל מאחת מאלה")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(list) { idea in
                            ideaChip(idea)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .id("history")
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
            .background(isOn ? AnyShapeStyle(SalaryView.artwork.gradient) : AnyShapeStyle(Theme.chip),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// How this month stands against the salary, and what the bank holds.
    private func monthCard(_ summary: MonthSummary) -> some View {
        let salary: Decimal = plan.salary
        let arrived: Decimal = summary.incomeSoFar
        let share: Double = salary > 0 ? min((arrived / salary).double, 1) : 0
        let balance: Double = bank.current?.amount ?? 0
        let weeks: Int = salary > 0 ? Int((balance / (salary.double / 4.345)).rounded(.down)) : 0
        let span: String = weeks == 1 ? "שבוע אחד" : (weeks == 2 ? "שבועיים" : "\(weeks) שבועות")
        let held: String = Money.text(Decimal(balance.rounded()))
        return VStack(alignment: .leading, spacing: 10) {
            Text("החודש הזה")
                .font(.system(size: 20, weight: .heavy))
            HStack(alignment: .firstTextBaseline) {
                Text("נכנסו עד עכשיו")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Money.text(arrived)) מתוך \(Money.text(salary))")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
            }
            GrowBar(share: share, height: 10, delay: 0.3, fill: SalaryView.artwork.gradient)
            Text(summary.surplus > 0
                 ? "העודף, \(Money.text(summary.surplus)), נשאר בבנק ככרית לחודש חלש."
                 : (summary.daysLeft > 0
                    ? "אם החודש ייסגר מתחת למשכורת, הכרית שבבנק משלימה את ההפרש."
                    : "החודש נסגר מתחת למשכורת, והכרית שבבנק השלימה את ההפרש."))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if balance > 0, salary > 0 {
                Divider()
                Text(weeks >= 1
                     ? "בבנק יש עכשיו \(held). זה מכסה \(span) של משכורת הבית."
                     : "בבנק יש עכשיו \(held), פחות משבוע של משכורת הבית.")
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
