import Charts
import SwiftData
import SwiftUI

/// Everything about one spending group: this month, the year, what it is
/// made of, and its lines.
struct CategoryDetailView: View {
    let category: SpendCategory
    let entries: [LedgerEntry]
    let month: Date

    @Query private var budgetLines: [BudgetLine]
    @State private var editing: LedgerEntry?

    private struct Bar: Identifiable {
        let id: Int
        let label: String
        let amount: Double
        let isSelected: Bool
    }

    private struct Part: Identifiable {
        let id: String
        let amount: Double
    }

    private var mine: [LedgerEntry] {
        entries.filter { $0.categoryID == category.id && $0.amount < 0 }
    }

    private var lines: [LedgerEntry] {
        Ledger.inMonth(mine, month).sorted { $0.date > $1.date }
    }

    private var total: Decimal { lines.reduce(Decimal(0)) { $0 - $1.amount } }

    private var bars: [Bar] {
        let calendar = Calendar.current
        let selected = calendar.component(.month, from: month)
        guard let year = calendar.dateInterval(of: .year, for: month) else { return [] }
        var sums = Array(repeating: 0.0, count: 12)
        for entry in mine where entry.date >= year.start && entry.date < year.end {
            sums[calendar.component(.month, from: entry.date) - 1] += (-entry.amount).double
        }
        return (1...12).map { Bar(id: $0, label: "\($0)", amount: sums[$0 - 1], isSelected: $0 == selected) }
    }

    private var average: Double {
        let active = bars.filter { $0.amount > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + $1.amount } / Double(active.count)
    }

    private var parts: [Part] {
        var sums: [String: Decimal] = [:]
        for entry in lines {
            sums[entry.subTitle ?? "כללי", default: 0] -= entry.amount
        }
        return sums.map { Part(id: $0.key, amount: $0.value.double) }.sorted { $0.amount > $1.amount }
    }

    private var limit: Decimal {
        budgetLines.first { $0.categoryID == category.id }?.limit ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    Text("לאורך השנה")
                        .font(.system(size: 20, weight: .heavy))
                    Chart {
                        ForEach(bars) { bar in
                            BarMark(x: .value("חודש", bar.label), y: .value("סכום", bar.amount))
                                .cornerRadius(5)
                                .foregroundStyle(bar.isSelected
                                                 ? AnyShapeStyle(category.artwork.gradient)
                                                 : AnyShapeStyle(category.artwork.start.opacity(0.35)))
                        }
                        if average > 0 {
                            RuleMark(y: .value("ממוצע", average))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .foregroundStyle(Color.secondary)
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("ממוצע \(Money.text(Decimal(average)))")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(height: 190)
                }
                .padding(16)
                .cardSurface()

                if parts.count > 1 || (parts.first?.id ?? "כללי") != "כללי" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ממה זה מורכב")
                            .font(.system(size: 20, weight: .heavy))
                        let peak = max(parts.first?.amount ?? 1, 1)
                        ForEach(parts) { part in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(part.id).font(.system(size: 15, weight: .semibold))
                                    Spacer()
                                    Text(Money.text(Decimal(part.amount)))
                                        .font(.system(size: 15, weight: .bold))
                                        .monospacedDigit()
                                }
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(category.artwork.gradient)
                                        .frame(width: max(proxy.size.width * part.amount / peak, 6))
                                }
                                .frame(height: 8)
                            }
                        }
                    }
                    .padding(16)
                    .cardSurface()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("התנועות ב\(Ledger.monthName(month))")
                        .font(.system(size: 20, weight: .heavy))
                        .padding(.horizontal, 4)
                    if lines.isEmpty {
                        ContentUnavailableView("אין תנועות בחודש הזה", systemImage: "tray")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(lines) { item in
                                Button {
                                    editing = item
                                } label: {
                                    TransactionRow(entry: item).contentShape(Rectangle())
                                }
                                .buttonStyle(.pressable)
                                if item.id != lines.last?.id {
                                    Divider().padding(.leading, 54)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .cardSurface()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { entry in
            EntryDetailSheet(entry: entry)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: category.symbol)
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.2), in: Circle())
                Spacer()
                Text(Ledger.monthName(month))
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            Text(Money.text(total))
                .font(.system(size: 46, weight: .heavy))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if limit > 0 {
                ProgressView(value: min(max((total / limit).double, 0), 1))
                    .tint(.white)
                Text(total > limit
                     ? "חריגה של \(Money.text(total - limit)) מהתקציב (\(Money.text(limit)))"
                     : "נשארו \(Money.text(limit - total)) מתוך תקציב של \(Money.text(limit))")
                    .font(.system(size: 13, weight: .semibold))
            } else if average > 0 {
                Text("הממוצע החודשי שלכם: \(Money.text(Decimal(average)))")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(category.artwork.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: category.artwork.end.opacity(0.4), radius: 18, y: 10)
    }
}
