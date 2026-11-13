import Charts
import SwiftUI

/// Where the money goes, as pictures rather than rows.
struct OverviewView: View {
    let entries: [LedgerEntry]
    let month: Date
    let summary: MonthSummary

    private struct Slice: Identifiable {
        let id: String
        let title: String
        let amount: Double
        let color: Color
    }

    private struct MonthPoint: Identifiable {
        let id: String
        let label: String
        let kind: String
        let amount: Double
    }

    private static func number(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private var slices: [Slice] {
        var sums: [String: Decimal] = [:]
        for entry in Ledger.inMonth(entries, month) where entry.amount < 0 {
            let category = entry.categoryID ?? SpendCategory.unknown.id
            if SpendCategory.notSpending.contains(category) { continue }
            sums[category, default: 0] -= entry.amount
        }
        return sums
            .map { key, value -> Slice in
                let category = SpendCategory.find(key) ?? .unknown
                return Slice(id: key, title: category.title, amount: Self.number(value),
                             color: category.artwork.start)
            }
            .sorted { $0.amount > $1.amount }
    }

    private var history: [MonthPoint] {
        let calendar = Calendar.current
        var points: [MonthPoint] = []
        for back in stride(from: 5, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -back, to: month) else { continue }
            let lines = Ledger.inMonth(entries, date)
            let label = date.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.abbreviated))
            var income = Decimal(0)
            var spent = Decimal(0)
            for entry in lines {
                let category = entry.categoryID ?? ""
                if SpendCategory.notSpending.contains(category) { continue }
                if entry.amount > 0 { income += entry.amount } else { spent -= entry.amount }
            }
            points.append(MonthPoint(id: "\(back)-in", label: label, kind: "הכנסות", amount: Self.number(income)))
            points.append(MonthPoint(id: "\(back)-out", label: label, kind: "הוצאות", amount: Self.number(spent)))
        }
        return points
    }

    var body: some View {
        MonthHeroCard(month: summary)

        natureCard

        VStack(alignment: .leading, spacing: 12) {
            Text("לאן הלך הכסף")
                .font(.system(size: 22, weight: .heavy))
            if slices.isEmpty {
                ContentUnavailableView("אין הוצאות בחודש הזה", systemImage: "chart.pie")
            } else {
                donut
                legend
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()

        VStack(alignment: .leading, spacing: 12) {
            Text("חצי שנה במבט אחד")
                .font(.system(size: 22, weight: .heavy))
            Chart(history) { point in
                BarMark(x: .value("חודש", point.label), y: .value("סכום", point.amount))
                    .position(by: .value("סוג", point.kind))
                    .foregroundStyle(by: .value("סוג", point.kind))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(["הכנסות": Theme.accent, "הוצאות": Color(hex: 0xDB2777)])
            .frame(height: 200)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var donut: some View {
        let total = slices.reduce(0) { $0 + $1.amount }
        return Chart(slices) { slice in
            SectorMark(angle: .value("סכום", slice.amount), innerRadius: .ratio(0.64), angularInset: 2)
                .cornerRadius(5)
                .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .frame(height: 210)
        .overlay {
            VStack(spacing: 0) {
                Text("סך ההוצאות")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(Money.text(Decimal(total)))
                    .font(.system(size: 26, weight: .heavy))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("תרשים חלוקת ההוצאות")
    }

    private var legend: some View {
        let total = max(slices.reduce(0) { $0 + $1.amount }, 1)
        return VStack(spacing: 10) {
            ForEach(slices.prefix(7)) { slice in
                HStack(spacing: 10) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 10, height: 10)
                    Text(slice.title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(slice.amount / total, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(Money.text(Decimal(slice.amount)))
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .frame(minWidth: 72, alignment: .trailing)
                }
            }
        }
    }

    /// Fixed, variable and one-time spending side by side.
    private var natureCard: some View {
        let parts: [(String, Decimal, Color)] = [
            ("קבועות", summary.fixedPaid, Color(hex: 0x7C3AED)),
            ("משתנות", summary.variableSpent, Color(hex: 0x2563EB)),
            ("חד פעמיות", summary.onceSpent, Color(hex: 0xD97706)),
        ]
        return HStack(spacing: 10) {
            ForEach(parts, id: \.0) { part in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(part.2)
                        .frame(width: 28, height: 5)
                    Text(Money.text(part.1))
                        .font(.system(size: 18, weight: .heavy))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(part.0)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}
