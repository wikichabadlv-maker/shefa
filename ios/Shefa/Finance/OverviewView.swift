import Charts
import SwiftData
import SwiftUI

/// The finance dashboard: the month as pictures, with the story on top.
struct OverviewView: View {
    /// The lines the month totals are made of.
    let entries: [LedgerEntry]
    /// Every line, for looking ahead: bank lines of months that a monthly
    /// summary covers still teach what returns.
    let all: [LedgerEntry]
    let month: Date
    let summary: MonthSummary
    /// The group picked on the round chart.
    @State private var pickedID: String?
    @State private var showsStory = false
    @State private var router = AppRouter.shared
    @Query private var budgetLines: [BudgetLine]

    private struct Slice: Identifiable {
        let id: String
        let category: SpendCategory
        let amount: Double
    }

    private struct MonthPoint: Identifiable {
        let id: String
        let label: String
        let kind: String
        let amount: Double
    }

    private var slices: [Slice] {
        Ledger.groupTotals(entries, month)
            .map { key, value in
                Slice(id: key, category: SpendCategory.find(key) ?? .unknown, amount: value.double)
            }
            .sorted { $0.amount > $1.amount }
    }

    private var history: [MonthPoint] {
        var points: [MonthPoint] = []
        for back in stride(from: 5, through: 0, by: -1) {
            guard let date = Calendar.current.date(byAdding: .month, value: -back, to: month) else { continue }
            let flow = Ledger.flow(entries, date)
            let label = Ledger.monthName(date, short: true)
            points.append(MonthPoint(id: "\(back)-in", label: label, kind: "הכנסות", amount: flow.income.double))
            points.append(MonthPoint(id: "\(back)-out", label: label, kind: "הוצאות", amount: flow.spent.double))
        }
        return points
    }

    private var biggest: [LedgerEntry] {
        Array(Ledger.inMonth(entries, month)
            .filter(Ledger.isSpending)
            .sorted { $0.amount < $1.amount }
            .prefix(5))
    }

    var body: some View {
        let list: [Slice] = slices
        let total: Double = list.reduce(0) { $0 + $1.amount }

        MonthHeroCard(month: summary)
            .cascade(0)

        if Calendar.current.isDate(month, equalTo: .now, toGranularity: .month) {
            // The present month also says what to do, and looks ahead.
            let horizon: Horizon? = Forecast.horizon(all)
            let step: NextStep = NextSteps.pick(entries: entries, summary: summary, budget: budgetLines,
                                                horizon: horizon)
            NextStepCard(step: step, act: act)
                .cascade(1)
                .id("step")
            SpendWeekCard(entries: entries, summary: summary)
                .cascade(2)
                .id("week")
            Button {
                Feedback.tap()
                router.financeRoute = .horizon
            } label: {
                UpcomingCard(horizon: horizon, upcoming: horizon == nil ? ahead : [])
            }
            .buttonStyle(.pressable)
            .cascade(3)
            .id("horizon")
        }

        if summary.income > 0 || !list.isEmpty {
            storyTile
                .cascade(1)
        }

        FlowBar(summary: summary)
            .cascade(2)

        InsightCarousel(insights: Insights.build(entries: entries, month: month, summary: summary),
                        entries: entries, month: month)
            .cascade(3)

        card("לאן הלך הכסף") {
            if list.isEmpty {
                ContentUnavailableView("אין הוצאות בחודש הזה", systemImage: "chart.pie")
            } else {
                donut(list, total: total)
                Text("הקישו על פלח כדי לראות את הקבוצה שלו.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .cascade(4)
        .id("donut")

        if !list.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(list) { slice in
                    NavigationLink {
                        CategoryDetailView(category: slice.category, entries: entries, month: month)
                    } label: {
                        CategoryTile(category: slice.category, amount: slice.amount,
                                     share: slice.amount / max(total, 1))
                    }
                    .buttonStyle(.pressable)
                }
            }
            .cascade(5)
        }

        PaceCard(entries: entries, month: month, summary: summary)
            .cascade(6)

        FixedCard(entries: entries, month: month)
            .cascade(7)
            .id("fixed")

        card("חצי שנה במבט אחד") {
            Chart(history) { point in
                BarMark(x: .value("חודש", point.label), y: .value("סכום", point.amount))
                    .position(by: .value("סוג", point.kind))
                    .foregroundStyle(by: .value("סוג", point.kind))
                    .cornerRadius(5)
            }
            .chartForegroundStyleScale(["הכנסות": Theme.accent, "הוצאות": Color(hex: 0xDB2777)])
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
            .frame(height: 210)
            // Room for the top label of the axis, which sits half above the chart.
            .padding(.top, 8)
            .reveal(.bottom, delay: 0.35)
        }
        .cascade(8)
        .id("history")

        card("השנה כמפה") {
            YearMap(entries: entries, month: month)
        }
        .cascade(9)
        .id("year")

        if !biggest.isEmpty {
            card("ההוצאות הגדולות של החודש") {
                VStack(spacing: 0) {
                    ForEach(biggest) { item in
                        TransactionRow(entry: item)
                        if item.id != biggest.last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
            .cascade(9)
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .heavy))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// What is expected, for a home whose balance is not known.
    private var ahead: [Upcoming] {
        Forecast.upcoming(all, after: Date.now.addingTimeInterval(-86_400), until: Forecast.windowEnd())
    }

    /// Where the button of the next step leads.
    private func act(_ target: NextStep.Target) {
        switch target {
        case .none: break
        case .review: router.isReviewing = true
        case .budget: router.financeSection = .budget
        case .savings: router.financeSection = .savings
        case .maaser: router.financeSection = .maaser
        case .route(let route): router.financeRoute = route
        }
    }

    /// Opens the month as a story of full colorful pages.
    private var storyTile: some View {
        Button {
            showsStory = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.22), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("הסיפור של \(Ledger.monthName(month))")
                        .font(.system(size: 19, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("החודש שלכם בכמה עמודים, כמו סיכום שנה")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.92)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(14)
            .livingCard(MonthStory.cover, radius: 24, seed: 0.5, watermark: "sparkles")
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .fullScreenCover(isPresented: $showsStory) {
            MonthStory(entries: entries, month: month, summary: summary)
        }
        .task {
            guard Launch.screen == "finance-story" else { return }
            try? await Task.sleep(for: .seconds(1))
            showsStory = true
        }
    }

    /// The round chart. A touch on a slice lifts it and names it in the middle.
    private func donut(_ list: [Slice], total: Double) -> some View {
        let picked: Slice? = list.first { $0.id == pickedID }
        let chosen: String = pickedID ?? ""
        return Chart(list) { slice in
            let isPicked: Bool = slice.id == chosen
            let reach: CGFloat = isPicked ? 1.0 : 0.93
            let strength: Double = chosen.isEmpty || isPicked ? 1 : 0.38
            SectorMark(angle: .value("סכום", slice.amount),
                       innerRadius: .ratio(0.66),
                       outerRadius: .ratio(reach),
                       angularInset: 2.5)
                .cornerRadius(6)
                .foregroundStyle(slice.category.artwork.gradient)
                .opacity(strength)
        }
        .chartLegend(.hidden)
        // Always clockwise from the top, so a touch can be matched to a slice.
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: 240)
        .sweepReveal()
        .overlay {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        pick(at: point, in: proxy.size, list: list, total: total)
                    }
            }
        }
        .overlay {
            ZStack {
                if let picked {
                    NavigationLink {
                        CategoryDetailView(category: picked.category, entries: entries, month: month)
                    } label: {
                        VStack(spacing: 1) {
                            Text(picked.category.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(Money.text(Decimal(picked.amount.rounded())))
                                .font(.system(size: 26, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            HStack(spacing: 3) {
                                Text((picked.amount / max(total, 1)).formatted(.percent.precision(.fractionLength(0))))
                                Text("· לפירוט")
                                Image(systemName: "chevron.forward")
                                    .font(.system(size: 10, weight: .heavy))
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        }
                        .frame(width: 138, height: 138)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    .id(picked.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    VStack(spacing: 0) {
                        Text("סך ההוצאות")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        CountUp(value: total) { Money.text(Decimal($0.rounded())) }
                            .font(.system(size: 28, weight: .heavy))
                            .monospacedDigit()
                        Text(Ledger.monthName(month))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .accessibilityLabel("תרשים חלוקת ההוצאות")
    }

    /// Finds the slice under a touch: the slices run clockwise from the top,
    /// in the order of the list.
    private func pick(at point: CGPoint, in size: CGSize, list: [Slice], total: Double) {
        let dx: Double = Double(point.x - size.width / 2)
        let dy: Double = Double(point.y - size.height / 2)
        let distance: Double = (dx * dx + dy * dy).squareRoot()
        let outer: Double = Double(min(size.width, size.height)) / 2
        var next: String? = nil
        if distance >= outer * 0.56, distance <= outer * 1.04, total > 0 {
            var turn: Double = atan2(dx, -dy) / (2 * Double.pi)
            if turn < 0 { turn += 1 }
            var running: Double = 0
            for slice in list {
                running += slice.amount
                if turn * total <= running {
                    next = slice.id
                    break
                }
            }
        }
        if next == pickedID { next = nil }
        if next == nil && pickedID == nil { return }
        Feedback.tap()
        withAnimation(.smooth(duration: 0.35)) { pickedID = next }
    }
}

/// Where the month's income goes, as one bar.
struct FlowBar: View {
    let summary: MonthSummary

    private struct Part: Identifiable {
        let id: String
        let amount: Double
        let color: Color
    }

    private var parts: [Part] {
        let maaser = summary.maaserInPlan
        let spent = summary.variableSpent + summary.onceSpent
        let left = max(summary.remaining, 0)
        return [
            Part(id: "קבועות", amount: summary.fixed.double, color: Color(hex: 0x7C3AED)),
            Part(id: "מעשר", amount: maaser.double, color: Color(hex: 0xD97706)),
            Part(id: "חיסכון", amount: summary.saved.double, color: Color(hex: 0x2563EB)),
            Part(id: "הוצאו", amount: spent.double, color: Color(hex: 0xDB2777)),
            Part(id: "נשאר", amount: left.double, color: Color(hex: 0x10B981)),
        ].filter { $0.amount > 0 }
    }

    var body: some View {
        let total = max(parts.reduce(0) { $0 + $1.amount }, 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(summary.salary > 0 ? "לאן הולכת משכורת הבית" : "לאן הולכת ההכנסה")
                    .font(.system(size: 17, weight: .heavy))
                Spacer()
                Text(Money.text(summary.income))
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(parts) { part in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(part.color)
                            .frame(width: max((proxy.size.width - CGFloat(parts.count - 1) * 3) * part.amount / total, 4))
                    }
                }
            }
            .frame(height: 18)
            .reveal(.leading, delay: 0.3)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8, alignment: .leading)],
                      alignment: .leading, spacing: 8) {
                ForEach(parts) { part in
                    HStack(spacing: 6) {
                        Circle().fill(part.color).frame(width: 9, height: 9)
                        Text(part.id)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(Money.text(Decimal(part.amount)))
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                    }
                }
            }
            if summary.salary > 0 {
                Text(summary.surplus > 0
                     ? "נכנסו \(Money.text(summary.surplus)) מעל משכורת הבית. הם נשארים בבנק, ככרית לחודש חלש."
                     : "החודש בנוי על משכורת הבית. עד עכשיו נכנסו \(Money.text(summary.incomeSoFar)).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

/// Short observations about the month, as swipeable colorful cards.
struct InsightCarousel: View {
    let insights: [Insight]
    let entries: [LedgerEntry]
    let month: Date

    var body: some View {
        if !insights.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(insights) { insight in
                        if let category = SpendCategory.find(insight.categoryID) {
                            NavigationLink {
                                CategoryDetailView(category: category, entries: entries, month: month)
                            } label: {
                                tile(insight)
                            }
                            .buttonStyle(.pressable)
                        } else {
                            tile(insight)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.horizontal, -16)
        }
    }

    private func tile(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: insight.symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.2), in: Circle())
            Spacer(minLength: 0)
            Text(insight.title)
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(insight.text)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.9)
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .padding(14)
        .frame(width: 232, height: 150, alignment: .leading)
        .livingCard(insight.artwork, radius: 24, watermark: insight.symbol, isMoving: false)
        .accessibilityElement(children: .combine)
    }
}

/// One spending group as a colorful cover, like a tile in a music library.
struct CategoryTile: View {
    let category: SpendCategory
    let amount: Double
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: category.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.22), in: Circle())
                Spacer()
                Text(share, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 13, weight: .heavy))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            Spacer(minLength: 10)
            Text(category.title)
                .font(.system(size: 15, weight: .semibold))
                .opacity(0.94)
                .lineLimit(1)
            CountUp(value: amount) { Money.text(Decimal($0.rounded())) }
                .font(.system(size: 23, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GrowBar(share: share, height: 5, track: .white.opacity(0.25), delay: 0.3, fill: Color.white)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
        .livingCard(category.artwork, radius: 22, seed: share * 3, watermark: category.symbol, isMoving: false)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The whole year as a colored grid: groups down, months across.
struct YearMap: View {
    let entries: [LedgerEntry]
    let month: Date

    private struct Row: Identifiable {
        let id: String
        let category: SpendCategory
        let months: [Double]
        var total: Double { months.reduce(0, +) }
    }

    private var rows: [Row] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: month)
        var table: [String: [Double]] = [:]
        for entry in entries where Ledger.isSpending(entry) && calendar.component(.year, from: entry.date) == year {
            let key = entry.categoryID ?? SpendCategory.unknown.id
            let index = calendar.component(.month, from: entry.date) - 1
            var months = table[key] ?? Array(repeating: 0, count: 12)
            months[index] += (-entry.amount).double
            table[key] = months
        }
        return table
            .map { Row(id: $0.key, category: SpendCategory.find($0.key) ?? .unknown, months: $0.value) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        let selected = Calendar.current.component(.month, from: month)
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                Color.clear.frame(width: 84, height: 1)
                ForEach(1...12, id: \.self) { number in
                    Text("\(number)")
                        .font(.system(size: 10, weight: number == selected ? .heavy : .medium))
                        .foregroundStyle(number == selected ? Theme.accent : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(rows) { row in
                NavigationLink {
                    CategoryDetailView(category: row.category, entries: entries, month: month)
                } label: {
                    HStack(spacing: 3) {
                        Text(row.category.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 84, alignment: .leading)
                        let peak = max(row.months.max() ?? 1, 1)
                        ForEach(0..<12, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(row.months[index] > 0
                                      ? row.category.artwork.start.opacity(0.2 + 0.8 * row.months[index] / peak)
                                      : Theme.chip.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .frame(height: 22)
                        }
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("\(row.category.title), \(Money.text(Decimal(row.total))) השנה")
            }
            Text("ככל שהמשבצת כהה יותר, הוצאתם יותר באותו חודש. לחיצה על שורה פותחת את הקבוצה.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }
}
