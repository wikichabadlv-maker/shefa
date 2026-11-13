import SwiftUI

/// Maaser on its own: this month, the year so far, and every gift that was
/// recorded. The money is shown as tzedakah that is held and waits to be
/// given, by the rules the family set for each kind of income.
struct MaaserView: View {
    let entries: [LedgerEntry]
    let month: Date
    let summary: MonthSummary
    @State private var plan = FinancePlan.shared
    @State private var isAdding = false
    @State private var viewing: LedgerEntry?
    @State private var showsRules = Launch.screen == "finance-rules"

    private struct MonthRow: Identifiable {
        let id: Date
        let due: Decimal
        let given: Decimal
    }

    /// Every month of the year so far that has any income or giving.
    private var months: [MonthRow] {
        let calendar = Calendar.current
        let book = MaaserBook(plan: plan)
        let number: Int = calendar.component(.month, from: month)
        var result: [MonthRow] = []
        for back in 0..<number {
            guard let date = calendar.date(byAdding: .month, value: -back, to: month) else { continue }
            let lines: [LedgerEntry] = Ledger.inMonth(entries, date)
            var given = Decimal(0)
            for entry in lines where entry.categoryID == SpendCategory.maaserID && entry.amount < 0 {
                given -= entry.amount
            }
            let base: Decimal = book.base(lines)
            guard base > 0 || given > 0 else { continue }
            result.append(MonthRow(id: date, due: book.due(lines), given: given))
        }
        return result
    }

    private var gifts: [LedgerEntry] {
        Ledger.inMonth(entries, month)
            .filter { $0.categoryID == SpendCategory.maaserID && $0.amount < 0 }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        let rows: [MonthRow] = months
        let due: Decimal = rows.reduce(Decimal(0)) { $0 + $1.due }
        let given: Decimal = rows.reduce(Decimal(0)) { $0 + $1.given }
        let balance: Decimal = due - given
        let waiting: Decimal = MaaserBook(plan: plan).waiting(Ledger.inMonth(entries, month))

        MaaserCard(month: summary, monthKey: String(DayKey.of(month).prefix(7)), waiting: waiting)

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

        rulesRow

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("מתחילת השנה")
                    .font(.system(size: 20, weight: .heavy))
                if plan.recordOnly {
                    Text("ניתנו \(Money.text(given))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text(balance > 0 ? "\(Money.text(balance)) ממתינים לנתינה"
                         : (balance < 0 ? "ניתנו \(Money.text(-balance)) מעבר למעשר ההכנסות" : "מעודכנים בדיוק"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(balance > 0 ? Theme.amberInk : Theme.accent)
                    Text("לפי מה שנכנס בפועל בכל חודש. ניתנו \(Money.text(given)) מתוך \(Money.text(due)).")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            if rows.isEmpty {
                Text("עוד אין הכנסות רשומות השנה.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                let share: Double = row.due > 0 ? min((row.given / row.due).double, 1) : (row.given > 0 ? 1 : 0)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(row.id.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide)))
                            .font(.system(size: 15, weight: .bold))
                        Spacer()
                        Text(plan.recordOnly ? Money.text(row.given)
                             : "\(Money.text(row.given)) מתוך \(Money.text(row.due))")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if !plan.recordOnly {
                        GrowBar(share: share, height: 6, fill: share >= 1 ? Theme.accent : Theme.amber.start)
                    }
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

        Text("רק מה שסווג כ״מעשר וצדקה״ נספר כנתינה. קניות יהדות, כמו מזוזה או ספר, נספרות בקטגוריה משלהן. הכול כאן בלי נדר: האפליקציה מחשבת לפי מה שקבעתם, ובכל שאלה פונים לרב.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
    }

    /// Opens the decisions about what maaser is reckoned from.
    private var rulesRow: some View {
        let asking: Int = plan.maaserRules.values.filter { $0 == MaaserRule.ask.rawValue }.count
        let changed: Int = plan.maaserRules.values.filter { $0 != MaaserRule.full.rawValue }.count
        let line: String
        if plan.recordOnly {
            line = "מתעדים נתינות בלי סכום יעד"
        } else if asking > 0 {
            line = asking == 1 ? "סוג הכנסה אחד מחכה לתשובת רב" : "\(asking) סוגי הכנסה מחכים לתשובת רב"
        } else if changed > 0 {
            line = "לפי מה שקבעתם לכל סוג הכנסה"
        } else {
            line = "כרגע מכל הכנסה. אפשר לקבוע לכל סוג בנפרד."
        }
        return Button {
            showsRules = true
        } label: {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: Theme.amber, symbol: "slider.horizontal.3")
                VStack(alignment: .leading, spacing: 1) {
                    Text("ממה מפרישים")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text(plan.isChomesh ? "20%" : "10%")
                    .font(.system(size: 13, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.amberInk)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Theme.amberGround, in: Capsule())
                    .opacity(plan.recordOnly ? 0 : 1)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.secondary)
            }
            .padding(14)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .navigationDestination(isPresented: $showsRules) {
            MaaserRulesView(entries: entries, month: month)
        }
    }
}
