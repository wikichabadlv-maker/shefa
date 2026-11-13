import SwiftUI

/// Maaser on its own: this month, the running balance for the year, and
/// every gift that was recorded.
struct MaaserView: View {
    let entries: [LedgerEntry]
    let month: Date
    let summary: MonthSummary
    @AppStorage("givesChomesh") private var isChomesh = false
    @State private var isAdding = false
    @State private var viewing: LedgerEntry?

    private struct MonthRow: Identifiable {
        let id: Date
        let income: Decimal
        let due: Decimal
        let given: Decimal
    }

    private var rate: Decimal { isChomesh ? Decimal(string: "0.2") ?? 0 : Decimal(string: "0.1") ?? 0 }

    /// Every month of the year so far that has any income or giving.
    private var months: [MonthRow] {
        let calendar = Calendar.current
        let number = calendar.component(.month, from: month)
        return (0..<number).compactMap { back in
            guard let date = calendar.date(byAdding: .month, value: -back, to: month) else { return nil }
            let lines = Ledger.inMonth(entries, date)
            var income = Decimal(0)
            var given = Decimal(0)
            for entry in lines where entry.categoryID != SpendCategory.transferID {
                if entry.amount > 0 {
                    income += entry.amount
                } else if entry.categoryID == SpendCategory.maaserID {
                    given -= entry.amount
                }
            }
            guard income > 0 || given > 0 else { return nil }
            return MonthRow(id: date, income: income, due: income * rate, given: given)
        }
    }

    private var gifts: [LedgerEntry] {
        Ledger.inMonth(entries, month)
            .filter { $0.categoryID == SpendCategory.maaserID && $0.amount < 0 }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let rows = months
        let due = rows.reduce(Decimal(0)) { $0 + $1.due }
        let given = rows.reduce(Decimal(0)) { $0 + $1.given }
        let balance = due - given

        MaaserCard(month: summary)

        Button {
            isAdding = true
        } label: {
            Label("תיעוד נתינה", systemImage: "heart.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.pressable)
        .sheet(isPresented: $isAdding) {
            QuickAddSheet(kind: .expense, presetCategory: SpendCategory.maaserID)
        }

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("מתחילת השנה")
                    .font(.system(size: 20, weight: .heavy))
                Text(balance > 0 ? "נשאר לתת \(Money.text(balance))"
                     : (balance < 0 ? "נתתם \(Money.text(-balance)) מעבר לחובה" : "מעודכנים בדיוק"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(balance > 0 ? Theme.amberInk : Theme.accent)
                Text("לפי ההכנסות שנרשמו בפועל בכל חודש. ניתן \(Money.text(given)) מתוך \(Money.text(due)).")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Text("עוד אין הכנסות רשומות השנה.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                let share = row.due > 0 ? min((row.given / row.due).double, 1) : (row.given > 0 ? 1 : 0)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.id.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide)))
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        Text("\(Money.text(row.given)) מתוך \(Money.text(row.due))")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: share)
                        .tint(share >= 1 ? Theme.accent : Theme.amber.start)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()

        if !gifts.isEmpty {
            Text("נתינות החודש")
                .font(.system(size: 22, weight: .heavy))
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(gifts) { entry in
                    Button {
                        viewing = entry
                    } label: {
                        TransactionRow(entry: entry)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    if entry.id != gifts.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
            .sheet(item: $viewing) { entry in
                EntryDetailSheet(entry: entry)
            }
        }

        Text("קניות יהדות, כמו מזוזה או ספר, לא נספרות כאן אלא בקטגוריה משלהן. רק מה שסווג כ״מעשר וצדקה״ נספר כנתינה.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }
}
