import Charts
import SwiftUI

/// The finance dashboard: the month as pictures, with the story on top.
struct OverviewView: View {
    @Namespace private var zoom
    let entries: [LedgerEntry]
    let month: Date
    let summary: MonthSummary

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
        MonthHeroCard(month: summary)

        FlowBar(summary: summary)

        InsightCarousel(insights: Insights.build(entries: entries, month: month, summary: summary),
                        entries: entries, month: month)

        card("לאן הלך הכסף") {
            if slices.isEmpty {
                ContentUnavailableView("אין הוצאות בחודש הזה", systemImage: "chart.pie")
            } else {
                donut
            }
        }
        .id("donut")

        if !slices.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(slices) { slice in
                    NavigationLink {
                        CategoryDetailView(category: slice.category, entries: entries, month: month)
                            .navigationTransition(.zoom(sourceID: slice.category.id, in: zoom))
                    } label: {
                        CategoryTile(category: slice.category, amount: slice.amount,
                                     share: slice.amount / max(slices.reduce(0) { $0 + $1.amount }, 1))
                            .matchedTransitionSource(id: slice.category.id, in: zoom)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }

        PaceCard(entries: entries, month: month, summary: summary)

        FixedCard(entries: entries, month: month)
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
        }
        .id("history")

        card("השנה כמפה") {
            YearMap(entries: entries, month: month)
        }
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

    private var donut: some View {
        let total = slices.reduce(0) { $0 + $1.amount }
        return Chart(slices) { slice in
            SectorMark(angle: .value("סכום", slice.amount), innerRadius: .ratio(0.66), angularInset: 2.5)
                .cornerRadius(6)
                .foregroundStyle(slice.category.artwork.gradient)
        }
        .chartLegend(.hidden)
        .frame(height: 230)
        .overlay {
            VStack(spacing: 0) {
                Text("סך ההוצאות")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(Money.text(Decimal(total)))
                    .font(.system(size: 28, weight: .heavy))
                    .monospacedDigit()
                Text(Ledger.monthName(month))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityLabel("תרשים חלוקת ההוצאות")
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
        let maaser = max(summary.maaserDue, summary.maaserGiven)
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
                Text("לאן הולכת ההכנסה")
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
            }
            .scrollIndicators(.hidden)
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
        .background(insight.artwork.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A colorful tile for one spending group.
struct CategoryTile: View {
    let category: SpendCategory
    let amount: Double
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ArtworkIcon(artwork: category.artwork, symbol: category.symbol, size: 36)
                Spacer()
                Text(share, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(category.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(Money.text(Decimal(amount)))
                .font(.system(size: 22, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.chip)
                    Capsule().fill(category.artwork.gradient)
                        .frame(width: max(proxy.size.width * share, 6))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
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
