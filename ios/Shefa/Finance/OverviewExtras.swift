import Charts
import SwiftUI

/// How fast the month's everyday money is being spent, day by day, against
/// an even pace toward what the month can afford.
struct PaceCard: View {
    let entries: [LedgerEntry]
    let month: Date
    let summary: MonthSummary

    private struct Point: Identifiable {
        let id: Int
        let day: Int
        let total: Double
    }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
    }

    private var lastDay: Int {
        let calendar = Calendar.current
        return calendar.isDate(month, equalTo: .now, toGranularity: .month)
            ? calendar.component(.day, from: .now) : daysInMonth
    }

    private var daily: [Int: Double] {
        var sums: [Int: Double] = [:]
        for entry in Ledger.inMonth(entries, month)
        where Ledger.isSpending(entry) && entry.nature != .fixed
            && entry.categoryID != SpendCategory.maaserID && entry.source != ExcelImport.source {
            sums[Calendar.current.component(.day, from: entry.date), default: 0] += (-entry.amount).double
        }
        return sums
    }

    private var points: [Point] {
        let sums = daily
        var running = 0.0
        var result: [Point] = [Point(id: 0, day: 0, total: 0)]
        for day in 1...max(lastDay, 1) {
            running += sums[day] ?? 0
            result.append(Point(id: day, day: day, total: running))
        }
        return result
    }

    var body: some View {
        let budget = max(summary.livingBudget.double, 0)
        let list = points
        let spent = list.last?.total ?? 0
        let even = budget * Double(lastDay) / Double(daysInMonth)
        if daily.count >= 3 {
            VStack(alignment: .leading, spacing: 10) {
                Text("קצב החודש")
                    .font(.system(size: 22, weight: .heavy))
                Text(budget <= 0
                     ? "כך הצטברו ההוצאות המשתנות לאורך החודש"
                     : (spent <= even
                        ? "אתם \(Money.text(Decimal(even - spent))) מתחת לקצב אחיד. יפה."
                        : "אתם \(Money.text(Decimal(spent - even))) מעל קצב אחיד"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(budget > 0 && spent > even ? Color(hex: 0xB45309) : Color.secondary)
                Chart {
                    if budget > 0 {
                        LineMark(x: .value("יום", 0), y: .value("סכום", 0.0), series: .value("קו", "אחיד"))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        LineMark(x: .value("יום", daysInMonth), y: .value("סכום", budget), series: .value("קו", "אחיד"))
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                    ForEach(list) { point in
                        AreaMark(x: .value("יום", point.day), y: .value("סכום", point.total))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: 0xDB2777).opacity(0.35), Color(hex: 0xDB2777).opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("יום", point.day), y: .value("סכום", point.total), series: .value("קו", "בפועל"))
                            .foregroundStyle(Color(hex: 0xDB2777))
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartXScale(domain: 0...daysInMonth)
                .chartXAxis {
                    AxisMarks(values: [1, 8, 15, 22, daysInMonth]) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 170)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel("תרשים קצב ההוצאות לאורך החודש")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }
}

/// The month's fixed commitments: what was already charged and what is
/// still expected, judging by the previous month.
struct FixedCard: View {
    let entries: [LedgerEntry]
    let month: Date

    private struct Line: Identifiable {
        let id: String
        let title: String
        let amount: Decimal
        let isPaid: Bool
        let category: SpendCategory
    }

    private func fixed(_ date: Date) -> [String: (title: String, amount: Decimal, category: SpendCategory)] {
        var result: [String: (title: String, amount: Decimal, category: SpendCategory)] = [:]
        for entry in Ledger.inMonth(entries, date) where Ledger.isSpending(entry) && entry.nature == .fixed {
            let key = entry.subID ?? Ledger.merchantKey(entry.title)
            let title = entry.subTitle ?? entry.title
            let known = result[key]
            result[key] = (title, (known?.amount ?? 0) - entry.amount, entry.category ?? .unknown)
        }
        return result
    }

    private var lines: [Line] {
        let current = fixed(month)
        var result = current.map { Line(id: $0.key, title: $0.value.title, amount: $0.value.amount,
                                        isPaid: true, category: $0.value.category) }
        let isCurrent = Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
        if isCurrent, let previous = Ledger.earlierMonths(entries, before: month, count: 2).first {
            for (key, value) in fixed(previous) where current[key] == nil {
                result.append(Line(id: key, title: value.title, amount: value.amount,
                                   isPaid: false, category: value.category))
            }
        }
        return result.sorted { $0.amount > $1.amount }
    }

    var body: some View {
        let list = lines
        if !list.isEmpty {
            let paid = list.filter(\.isPaid).reduce(Decimal(0)) { $0 + $1.amount }
            let waiting = list.filter { !$0.isPaid }.reduce(Decimal(0)) { $0 + $1.amount }
            VStack(alignment: .leading, spacing: 10) {
                Text("ההתחייבויות הקבועות")
                    .font(.system(size: 22, weight: .heavy))
                Text(waiting > 0
                     ? "ירדו \(Money.text(paid)), ועוד כ־\(Money.text(waiting)) צפויים לרדת"
                     : "סך הכול \(Money.text(paid)) החודש")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(list) { line in
                        HStack(spacing: 12) {
                            ArtworkIcon(artwork: line.category.artwork, symbol: line.category.symbol, size: 34)
                                .opacity(line.isPaid ? 1 : 0.45)
                            Text(line.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Money.text(line.amount))
                                .font(.system(size: 15, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(line.isPaid ? Color.primary : Color.secondary)
                            Image(systemName: line.isPaid ? "checkmark.circle.fill" : "clock")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(line.isPaid ? Theme.accent : Color.secondary)
                                .accessibilityLabel(line.isPaid ? "ירד" : "צפוי")
                        }
                        .frame(height: 46)
                        if line.id != list.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }
}
