import SwiftUI

/// The month told as a story: full colorful pages with one number on each,
/// turning on their own like a year in review.
struct MonthStory: View {
    let entries: [LedgerEntry]
    let month: Date
    let summary: MonthSummary
    @Environment(\.dismiss) private var dismiss
    @State private var index = Int(Launch.anchor) ?? 0
    @State private var isHeld = false
    @State private var pressedAt = Date.now

    /// The colors of the story's cover and of its last page.
    static let cover = Artwork(0x7C3AED, 0xDB2777)
    static let pageSeconds: Double = 6

    struct Bar: Identifiable {
        let id: String
        let title: String
        let amount: Double
        let share: Double
    }

    struct Page: Identifiable {
        let id: String
        let artwork: Artwork
        let symbol: String
        /// The small line on top.
        let kicker: String
        /// The big number, in shekels.
        var number: Double? = nil
        var title: String = ""
        var text: String = ""
        var bars: [Bar] = []
        /// A share from 0 to 1, drawn as one bar.
        var share: Double? = nil
    }

    // MARK: Pages

    private var pages: [Page] {
        var result: [Page] = []
        let calendar = Calendar.current
        let name: String = Ledger.monthName(month)
        let isCurrent: Bool = calendar.isDate(month, equalTo: .now, toGranularity: .month)
        let lines: [LedgerEntry] = Ledger.inMonth(entries, month)
        let isSummary: Bool = lines.contains { $0.source == ExcelImport.source }
        let flow = Ledger.flow(entries, month)
        let groups: [String: Decimal] = Ledger.groupTotals(entries, month)
        let total: Decimal = groups.values.reduce(Decimal(0), +)
        let red = Artwork(0xDC2626, 0x991B1B)

        // 1. Where the month stands.
        if isCurrent {
            let left: Decimal = summary.remaining
            result.append(Page(
                id: "left", artwork: left >= 0 ? Theme.emerald : red, symbol: "banknote.fill",
                kicker: "\(name) עד עכשיו", number: abs(left.double),
                title: left >= 0 ? "נשאר לחיות ממנו" : "חריגה מהמסגרת",
                text: left >= 0
                    ? "כ־\(Money.text(summary.perDay)) ליום, ועוד \(Ledger.daysText(summary.daysLeft)) עד סוף החודש."
                    : "ההוצאות עברו את מה שהחודש יכול לשאת, ונשארו עוד \(Ledger.daysText(summary.daysLeft))."))
        } else if flow.income > 0 || flow.spent > 0 {
            let net: Decimal = flow.income - flow.spent
            result.append(Page(
                id: "net", artwork: net >= 0 ? Theme.emerald : red, symbol: "banknote.fill",
                kicker: name, number: abs(net.double),
                title: net >= 0 ? "החודש נסגר בפלוס" : "החודש נסגר במינוס",
                text: "נכנסו \(Money.text(flow.income)) ויצאו \(Money.text(flow.spent))."))
        }

        // 2. Where the money went.
        let ranked: [(key: String, value: Decimal)] = groups.sorted { $0.value > $1.value }
        if total > 0 {
            let peak: Decimal = ranked.first?.value ?? 1
            var bars: [Bar] = []
            for item in ranked.prefix(4) {
                let title: String = (SpendCategory.find(item.key) ?? .unknown).title
                bars.append(Bar(id: item.key, title: title, amount: item.value.double,
                                share: peak > 0 ? (item.value / peak).double : 0))
            }
            result.append(Page(
                id: "where", artwork: Artwork(0xDB2777, 0x7C3AED), symbol: "chart.pie.fill",
                kicker: "לאן הלך הכסף", number: total.double, title: "", text: "", bars: bars))
        }

        // 3. The biggest group, against a usual month.
        if total > 0, let first = ranked.first, let category = SpendCategory.find(first.key) {
            let share: Int = Int((first.value / total).double * 100)
            let earlier: [Date] = Ledger.earlierMonths(entries, before: month)
            var usual: Decimal = 0
            if !earlier.isEmpty {
                for date in earlier {
                    usual += Ledger.groupTotals(entries, date)[first.key] ?? 0
                }
                usual = usual / Decimal(earlier.count)
            }
            var text: String = "\(share)% מכל ההוצאות."
            if usual > 0, !isCurrent {
                text += first.value > usual
                    ? " בחודש רגיל זה \(Money.text(usual)), כלומר יותר מהרגיל."
                    : " בחודש רגיל זה \(Money.text(usual)), כלומר פחות מהרגיל."
            } else if usual > 0 {
                text += " בחודש רגיל זה מגיע ל־\(Money.text(usual))."
            }
            result.append(Page(
                id: "top", artwork: category.artwork, symbol: category.symbol,
                kicker: "הקבוצה הגדולה של החודש", number: first.value.double,
                title: category.title, text: text))
        }

        // 4. The biggest single expense. A month kept as a summary has none.
        if !isSummary, let biggest = lines.filter(Ledger.isSpending).min(by: { $0.amount < $1.amount }) {
            let day: String = biggest.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide))
            result.append(Page(
                id: "big", artwork: Theme.blue, symbol: "creditcard.fill",
                kicker: "ההוצאה הגדולה של החודש", number: (-biggest.amount).double,
                title: biggest.title, text: "\(day) · \(biggest.category?.title ?? "לבירור")"))
        }

        // 5. Against the month before, up to the same day.
        if let previous = calendar.date(byAdding: .month, value: -1, to: month) {
            let before: [LedgerEntry] = Ledger.inMonth(entries, previous)
            let beforeIsSummary: Bool = before.contains { $0.source == ExcelImport.source }
            let lastDay: Int = isCurrent ? calendar.component(.day, from: .now) : 31
            var spentNow: Decimal = 0
            for entry in lines where Ledger.isSpending(entry) && calendar.component(.day, from: entry.date) <= lastDay {
                spentNow -= entry.amount
            }
            var spentBefore: Decimal = 0
            for entry in before where Ledger.isSpending(entry) && calendar.component(.day, from: entry.date) <= lastDay {
                spentBefore -= entry.amount
            }
            // A summary month has no days, so it cannot be compared part way.
            if spentNow > 0, spentBefore > 0, !(isCurrent && beforeIsSummary) {
                let gap: Decimal = spentNow - spentBefore
                let other: String = Ledger.monthName(previous)
                result.append(Page(
                    id: "compare", artwork: gap <= 0 ? Theme.green : Artwork(0xEA580C, 0x9A3412),
                    symbol: gap <= 0 ? "arrow.down.right" : "arrow.up.right",
                    kicker: "מול \(other)", number: abs(gap.double),
                    title: gap <= 0 ? "פחות מהחודש שעבר" : "יותר מהחודש שעבר",
                    text: isCurrent
                        ? "עד היום הוצאתם \(Money.text(spentNow)). ב\(other), עד אותו יום, \(Money.text(spentBefore))."
                        : "הוצאתם \(Money.text(spentNow)), לעומת \(Money.text(spentBefore)) ב\(other)."))
            }
        }

        // 6. Maaser.
        let due: Decimal = summary.maaserDue
        let given: Decimal = summary.maaserGiven
        if due > 0 || given > 0 {
            let left: Decimal = max(due - given, 0)
            result.append(Page(
                id: "maaser", artwork: Theme.amber, symbol: "heart.fill",
                kicker: "מעשר וצדקה", number: given.double,
                title: left > 0 ? "ניתן עד עכשיו" : "ניתן במלואו",
                text: left > 0 ? "מתוך \(Money.text(due)). עוד \(Money.text(left)) ממתינים לנתינה."
                    : (due > 0 ? "מעשר ההכנסות של החודש ניתן כולו." : ""),
                share: due > 0 ? min((given / due).double, 1) : 1))
        }

        // 7. Savings.
        if summary.saved > 0 {
            let part: Int = summary.income > 0 ? Int((summary.saved / summary.income).double * 100) : 0
            result.append(Page(
                id: "saved", artwork: Artwork(0x0EA5E9, 0x2563EB), symbol: "leaf.fill",
                kicker: "שמנו בצד", number: summary.saved.double, title: "לחיסכון החודש",
                text: part > 0 ? "\(part)% מההכנסה של החודש." : ""))
        }

        // 8. The one next step.
        let maaserLeft: Decimal = max(due - given, 0)
        var step: String = "הכול במקום. ממשיכים כך."
        if isCurrent, summary.remaining < 0 {
            step = "הצעד הבא: לעצור את ההוצאות שאפשר לדחות עד סוף החודש, או להחליט מאיפה מכסים את החריגה."
        } else if isCurrent, maaserLeft > 0 {
            step = "הצעד הבא: \(Money.text(maaserLeft)) ממתינים לנתינה, והחודש סגור מהצד הזה."
        } else if !isCurrent, flow.spent > flow.income, flow.income > 0 {
            step = "יצא יותר ממה שנכנס. שווה לבדוק איזו קבוצה גדלה, ולקבוע לה תקציב."
        }
        result.append(Page(id: "end", artwork: MonthStory.cover, symbol: "sparkles",
                           kicker: name, title: "זה החודש שלכם", text: step))
        return result
    }

    // MARK: Screen

    var body: some View {
        let list: [Page] = pages
        let page: Page = list[min(max(index, 0), list.count - 1)]
        GeometryReader { proxy in
            ZStack {
                StoryPage(page: page)
                    .arrives()
                    .id(page.id)
                    .transition(.opacity)

                VStack(spacing: 12) {
                    StoryBars(count: list.count, index: index, isHeld: $isHeld) {
                        forward(list.count)
                    }
                    HStack {
                        Text("הסיפור של \(Ledger.monthName(month))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.white.opacity(0.22), in: Circle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("סגירה")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
            .gesture(touch(width: proxy.size.width, count: list.count))
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityAction(named: "העמוד הבא") { forward(list.count) }
        .accessibilityAction(named: "העמוד הקודם") { back() }
    }

    /// One touch does it all: a tap on a side turns the page, a hold stops
    /// the clock, and a pull downward closes the story.
    private func touch(width: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isHeld {
                    isHeld = true
                    pressedAt = .now
                }
            }
            .onEnded { value in
                isHeld = false
                let held: Double = Date.now.timeIntervalSince(pressedAt)
                let moved: CGFloat = max(abs(value.translation.width), abs(value.translation.height))
                if value.translation.height > 90 {
                    dismiss()
                } else if held < 0.3, moved < 16 {
                    // Hebrew reads toward the left, so the left side is "onward".
                    if value.startLocation.x < width / 2 {
                        forward(count)
                    } else {
                        back()
                    }
                }
            }
    }

    private func forward(_ count: Int) {
        if index < count - 1 {
            withAnimation(.smooth(duration: 0.35)) { index += 1 }
        } else {
            dismiss()
        }
    }

    private func back() {
        if index > 0 {
            withAnimation(.smooth(duration: 0.35)) { index -= 1 }
        }
    }
}

/// One page of the story.
private struct StoryPage: View {
    let page: MonthStory.Page

    var body: some View {
        ZStack {
            LivingGradient(artwork: page.artwork, seed: 0.2)
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.3)],
                           startPoint: .center, endPoint: .bottom)
            // An overlay, so that a wide symbol cannot make the page wider
            // than the screen.
            Color.clear
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: page.symbol)
                        .font(.system(size: 290, weight: .bold))
                        .foregroundStyle(.white.opacity(0.1))
                        .rotationEffect(.degrees(-14))
                        .fixedSize()
                        .offset(x: -70, y: 50)
                }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                Text(page.kicker)
                    .font(.system(size: 18, weight: .bold))
                    .opacity(0.92)
                    .cascade(0)
                if let number = page.number {
                    BigMoney(value: number, size: 80, duration: 1.3)
                        .cascade(2)
                }
                if !page.title.isEmpty {
                    Text(page.title)
                        .font(.system(size: page.number == nil ? 46 : 32, weight: .heavy))
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .cascade(4)
                }
                if !page.bars.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(page.bars) { bar in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(bar.title)
                                        .font(.system(size: 17, weight: .bold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(Money.text(Decimal(bar.amount.rounded())))
                                        .font(.system(size: 17, weight: .heavy))
                                        .monospacedDigit()
                                }
                                GrowBar(share: bar.share, height: 10, track: .white.opacity(0.22),
                                        delay: 0.45, fill: Color.white)
                            }
                        }
                    }
                    .padding(.top, 6)
                    .cascade(5)
                }
                if let share = page.share {
                    GrowBar(share: share, height: 12, track: .white.opacity(0.22), delay: 0.45, fill: Color.white)
                        .padding(.top, 4)
                        .cascade(5)
                }
                if !page.text.isEmpty {
                    Text(page.text)
                        .font(.system(size: 19, weight: .medium))
                        .lineSpacing(3)
                        .opacity(0.95)
                        .cascade(6)
                }
                Spacer()
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
    }
}

/// The thin bars on top of a story: one for each page, the current one
/// filling up as its time runs.
private struct StoryBars: View {
    let count: Int
    let index: Int
    @Binding var isHeld: Bool
    let onFinish: () -> Void
    @State private var elapsed: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { item in
                GeometryReader { proxy in
                    let part: Double = item < index ? 1 : (item == index ? min(elapsed / MonthStory.pageSeconds, 1) : 0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.3))
                        Capsule().fill(Color.white)
                            .frame(width: proxy.size.width * CGFloat(part))
                    }
                }
                .frame(height: 3)
            }
        }
        .animation(.linear(duration: 0.1), value: elapsed)
        .task(id: index) {
            elapsed = 0
            // A test run stays on its page, and so does a reader who asked
            // the phone for less motion: a tap turns the page.
            guard Launch.screen.isEmpty, !reduceMotion else { return }
            while elapsed < MonthStory.pageSeconds {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                if !isHeld { elapsed += 0.1 }
            }
            onFinish()
        }
        .accessibilityHidden(true)
    }
}
