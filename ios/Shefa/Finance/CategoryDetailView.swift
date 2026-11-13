import Charts
import SwiftData
import SwiftUI

/// Everything about one spending group: this month, the year, what it is
/// made of, and its lines. The screen opens in the group's own color, like
/// an album page.
struct CategoryDetailView: View {
    let category: SpendCategory
    let entries: [LedgerEntry]
    let month: Date

    @Query private var budgetLines: [BudgetLine]
    @State private var editing: LedgerEntry?
    /// True once the big title has scrolled away under the bar.
    @State private var isScrolled = false
    @Environment(\.layoutDirection) private var direction

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
                    .cascade(0)

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
                    // Room for the top label of the axis, which sits half
                    // above the chart.
                    .padding(.top, 8)
                    .reveal(.bottom, delay: 0.35)
                }
                .padding(16)
                .cardSurface()
                .cascade(1)

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
                                GrowBar(share: part.amount / peak, height: 8, delay: 0.3,
                                        fill: category.artwork.gradient)
                            }
                        }
                    }
                    .padding(16)
                    .cardSurface()
                    .cascade(2)
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
                .cascade(3)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .background(alignment: .top) {
                StageBackdrop(artwork: category.artwork, height: 470)
            }
        }
        .background(Theme.ground)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 110
        } action: { _, isPast in
            withAnimation(.smooth(duration: 0.25)) { isScrolled = isPast }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The name waits in the bar until the big title scrolls away.
            ToolbarItem(placement: .principal) {
                Text(category.title)
                    .font(.system(size: 17, weight: .semibold))
                    .opacity(isScrolled ? 1 : 0)
            }
        }
        .toolbarColorScheme(isScrolled ? nil : .dark, for: .navigationBar)
        .arrives()
        .sheet(item: $editing) { entry in
            EntryDetailSheet(entry: entry)
        }
    }

    /// The top of the stage: white type straight on the color, no card.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: category.symbol)
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 60, height: 60)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                Spacer()
                Text(Ledger.monthName(month))
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            Text(category.title)
                .font(.system(size: 34, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 6)
            BigMoney(value: total.double, size: 62)
            if limit > 0 {
                GrowBar(share: min(max((total / limit).double, 0), 1), height: 8,
                        track: .white.opacity(0.25), fill: Color.white)
                Text(total > limit
                     ? "חריגה של \(Money.text(total - limit)) מהתקציב (\(Money.text(limit)))"
                     : "נשארו \(Money.text(limit - total)) מתוך תקציב של \(Money.text(limit))")
                    .font(.system(size: 14, weight: .semibold))
            } else if average > 0 {
                Text("הממוצע החודשי שלכם: \(Money.text(Decimal(average)))")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            Image(systemName: category.symbol)
                .font(.system(size: 190, weight: .bold))
                .foregroundStyle(.white.opacity(0.1))
                .rotationEffect(.degrees(-14))
                .offset(x: direction == .rightToLeft ? -44 : 44, y: 24)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
