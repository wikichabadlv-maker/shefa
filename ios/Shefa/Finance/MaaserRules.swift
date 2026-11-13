import SwiftUI

/// What maaser is reckoned from: one decision for each kind of income. The
/// family decides, with their rav. The app keeps the decisions and does the
/// arithmetic, and rules on nothing.
struct MaaserRulesView: View {
    let entries: [LedgerEntry]
    let month: Date
    @State private var plan = FinancePlan.shared

    private struct Kind: Identifiable {
        let id: String
        let title: String
        let total: Decimal
    }

    private var yearLines: [LedgerEntry] {
        guard let year = Calendar.current.dateInterval(of: .year, for: month) else { return [] }
        return entries.filter {
            $0.amount > 0 && $0.categoryID != SpendCategory.transferID && $0.date >= year.start && $0.date < year.end
        }
    }

    /// Every kind of income that came in this year, the largest first.
    private var kinds: [Kind] {
        var sums: [String: Decimal] = [:]
        var names: [String: String] = [:]
        for entry in yearLines {
            let key: String = MaaserBook.key(for: entry)
            sums[key, default: 0] += entry.amount
            if let name = entry.subTitle { names[key] = name }
        }
        var result: [Kind] = []
        for (key, total) in sums {
            let title: String = SubCategory.find(key)?.title ?? names[key] ?? "הכנסה שלא סווגה"
            result.append(Kind(id: key, title: title, total: total))
        }
        return result.sorted { $0.total != $1.total ? $0.total > $1.total : $0.id < $1.id }
    }

    var body: some View {
        let list: [Kind] = kinds
        let book = MaaserBook(plan: plan)
        let lines: [LedgerEntry] = yearLines
        let base: Decimal = book.base(lines)
        let waiting: Decimal = book.waiting(lines)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(base: base, due: book.due(lines), waiting: waiting)
                    .cascade(0)

                if list.isEmpty {
                    Text("עוד אין הכנסות רשומות השנה. כשיירשמו, כל סוג הכנסה יופיע כאן.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                }

                ForEach(Array(list.enumerated()), id: \.element.id) { index, kind in
                    card(kind, book: book)
                        .cascade(index + 1)
                }

                general
                    .cascade(list.count + 1)

                Text("ברירת המחדל היא שכל הכנסה נכללת, ושום סכום לא משתנה עד שאתם קובעים אחרת. ״לשאול רב״ מחזיק את ההכנסה בצד עד שתהיה תשובה. הכול כאן בלי נדר.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background { AmbientGround(artwork: Theme.amber) }
        .navigationTitle("ממה מפרישים")
        .navigationBarTitleDisplayMode(.inline)
        .arrives()
    }

    private func header(base: Decimal, due: Decimal, waiting: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.recordOnly ? "ההכנסות שנכללות השנה" : (plan.isChomesh ? "חומש ההכנסות השנה" : "מעשר ההכנסות השנה"))
                .font(.system(size: 15, weight: .semibold))
                .opacity(0.9)
            BigMoney(value: (plan.recordOnly ? base : due).double, size: 48)
            if !plan.recordOnly {
                Text("מתוך \(Money.text(base)) שנכללים בחשבון")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(0.92)
            }
            if waiting > 0 {
                Label("\(Money.text(waiting)) מחכים לתשובת רב", systemImage: "questionmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(Theme.amber, seed: 0.5, watermark: "heart.fill")
        .accessibilityElement(children: .combine)
    }

    private func card(_ kind: Kind, book: MaaserBook) -> some View {
        let rule: MaaserRule = book.rule(kind.id)
        let share: Double = book.share(kind.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title)
                    .font(.system(size: 17, weight: .heavy))
                Spacer(minLength: 8)
                Text("\(Money.text(kind.total)) השנה")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if MaaserBook.disputed.contains(kind.id) {
                Label("יש בזה דעות שונות, כדאי לשאול רב", systemImage: "info.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.amberInk)
            }
            HStack(spacing: 6) {
                ForEach(MaaserRule.allCases) { item in
                    chip(item, isOn: rule == item) {
                        Feedback.tap()
                        withAnimation(.snappy) { plan.setRule(item, for: kind.id) }
                    }
                }
            }
            if rule == .partial {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("נכללים \(Int((share * 100).rounded()))% מהסכום")
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                        Spacer()
                        Text(Money.text(kind.total * Decimal(share)))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    }
                    Slider(value: Binding(get: { book.share(kind.id) }, set: { plan.setShare($0, for: kind.id) }),
                           in: 0.3...1, step: 0.05)
                        .tint(Theme.amber.start)
                        .environment(\.layoutDirection, .leftToRight)
                    Text("למשל אחרי הוצאות העסק, מסים או הוצאות שכרוכות בעבודה, כפי שנפסק לכם.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if rule == .ask {
                Text("ההכנסה הזאת מוחזקת בצד ולא נכללת בחשבון עד שתשנו את הבחירה.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func chip(_ rule: MaaserRule, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: rule.symbol)
                    .font(.system(size: 15, weight: .bold))
                Text(rule.title)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? AnyShapeStyle(Theme.amber.gradient) : AnyShapeStyle(Theme.chip),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("כללי")
                .font(.system(size: 17, weight: .heavy))
            Toggle(isOn: Binding(get: { plan.recordOnly }, set: { value in
                withAnimation(.snappy) { plan.setRecordOnly(value) }
            })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("רק לתעד נתינות")
                        .font(.system(size: 16, weight: .semibold))
                    Text("בלי סכום יעד ובלי חשבון. רואים כמה ניתן, וזה הכול.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            if !plan.recordOnly {
                Divider()
                HStack {
                    Text("השיעור")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Picker("שיעור", selection: Binding(get: { plan.isChomesh }, set: { plan.setChomesh($0) })) {
                        Text("מעשר 10%").tag(false)
                        Text("חומש 20%").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
