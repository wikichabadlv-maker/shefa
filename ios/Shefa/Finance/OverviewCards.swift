import Charts
import SwiftUI

/// The one next step, right under the month card.
struct NextStepCard: View {
    let step: NextStep
    let act: (NextStep.Target) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkIcon(artwork: step.artwork, symbol: step.symbol, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.button == nil ? "המצב עכשיו" : "הצעד הבא")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.secondary)
                Text(step.title)
                    .font(.system(size: 18, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let button = step.button {
                    Button {
                        Feedback.tap()
                        act(step.target)
                    } label: {
                        HStack(spacing: 6) {
                            Text(button)
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 12, weight: .heavy))
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(step.artwork.gradient, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The card carries a breath of the step's own color.
            Theme.cardShape.fill(Theme.card)
                .overlay { Theme.cardShape.fill(step.artwork.start.opacity(0.08)) }
                .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A bar that rises from the floor as its screen opens.
struct RiseBar<Fill: ShapeStyle>: View {
    let share: Double
    var delay: Double = 0.15
    let fill: Fill
    @Environment(\.arrived) private var arrived

    var body: some View {
        let clamped: CGFloat = CGFloat(min(max(share, 0), 1))
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill)
                    .frame(height: arrived ? max(proxy.size.height * clamped, clamped > 0 ? 6 : 0) : 0)
                    .animation(.smooth(duration: 0.7).delay(delay), value: arrived)
            }
        }
        .accessibilityHidden(true)
    }
}

/// This week, day by day: what went on everyday things, and what the rest
/// of the week can carry.
struct SpendWeekCard: View {
    let entries: [LedgerEntry]
    let summary: MonthSummary

    private struct Day: Identifiable {
        let id: Int
        let letter: String
        let amount: Double
        let isToday: Bool
        let isAhead: Bool
    }

    private static let letters = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        return calendar
    }

    private var days: [Day] {
        let calendar = self.calendar
        let today: Date = calendar.startOfDay(for: .now)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return [] }
        var sums: [Date: Double] = [:]
        for entry in entries
        where entry.date >= week.start && entry.date < week.end && Ledger.isSpending(entry)
            && entry.nature != .fixed && entry.categoryID != SpendCategory.maaserID
            && entry.source != ExcelImport.source {
            sums[calendar.startOfDay(for: entry.date), default: 0] += (-entry.amount).double
        }
        var result: [Day] = []
        for index in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: index, to: week.start) else { continue }
            result.append(Day(id: index, letter: SpendWeekCard.letters[index], amount: sums[date] ?? 0,
                              isToday: date == today, isAhead: date > today))
        }
        return result
    }

    /// The days from today to the end of the week that still belong to this month.
    private var daysAhead: Int {
        let calendar = self.calendar
        let today: Date = calendar.startOfDay(for: .now)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return 1 }
        let inWeek: Int = (calendar.dateComponents([.day], from: today, to: week.end).day ?? 1)
        return max(min(inWeek, summary.daysLeft), 1)
    }

    var body: some View {
        let list: [Day] = days
        let allowance: Double = summary.perDay.double
        let peak: Double = max(list.map(\.amount).max() ?? 0, allowance * 1.25, 1)
        let spent: Double = list.reduce(0) { $0 + $1.amount }
        let left: Decimal = summary.perDay * Decimal(daysAhead)
        let today: Double = list.first { $0.isToday }?.amount ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("השבוע")
                        .font(.system(size: 22, weight: .heavy))
                    Text(spent > 0 ? "יצאו \(Money.text(Decimal(spent.rounded()))), מהם היום \(Money.text(Decimal(today.rounded())))"
                         : "עוד לא נרשמו הוצאות השבוע")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    CountUp(value: left.double) { Money.text(Decimal($0.rounded())) }
                        .font(.system(size: 24, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                    Text(daysAhead == 1 ? "נשאר להיום" : "נשאר עד סוף השבוע")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(list) { day in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Theme.chip.opacity(day.isAhead ? 0.5 : 1))
                            RiseBar(share: day.amount / peak, delay: 0.2 + Double(day.id) * 0.05,
                                    fill: day.isToday ? AnyShapeStyle(Theme.pink.gradient)
                                        : AnyShapeStyle(Theme.pink.start.opacity(0.45)))
                        }
                        .frame(height: 92)
                        Text(day.letter)
                            .font(.system(size: 12, weight: day.isToday ? .heavy : .medium))
                            .foregroundStyle(day.isToday ? Theme.accent : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("יום \(day.letter): \(Money.text(Decimal(day.amount.rounded())))")
                }
            }
            .overlay(alignment: .top) {
                // What one day can carry, as a line across the week.
                if allowance > 0 {
                    GeometryReader { proxy in
                        let y: CGFloat = 92 * (1 - CGFloat(min(allowance / peak, 1)))
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                        .stroke(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                    .frame(height: 92)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            if allowance > 0 {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Theme.accent.opacity(0.7))
                        .frame(width: 14, height: 1.5)
                    Text("כ־\(Money.text(summary.perDay)) ליום משאירים את החודש במסגרת")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// What is about to move in the bank account, and where the balance is
/// heading. Opens the full horizon.
struct UpcomingCard: View {
    let horizon: Horizon?
    /// What is expected, for a home with no known balance.
    let upcoming: [Upcoming]

    private var events: [Upcoming] { horizon?.events ?? upcoming }

    private var sentence: String {
        guard let horizon else {
            return "כדי לראות לאן היתרה הולכת צריך יתרה. היא מגיעה מהבנק, ואפשר גם להזין אותה."
        }
        if let below = horizon.firstBelowZero {
            let day: String = below.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide))
            return "ב־\(day) החשבון צפוי לרדת מתחת לאפס."
        }
        if let low = horizon.lowest, low.balance < horizon.today {
            let day: String = low.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide))
            return "הנקודה הנמוכה: \(Money.text(Decimal(low.balance.rounded()))) ב־\(day)."
        }
        return "היתרה לא צפויה לרדת מתחת למה שיש היום."
    }

    var body: some View {
        let list: [Upcoming] = Array(events.prefix(3))
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("קו האופק")
                    .font(.system(size: 22, weight: .heavy))
                Spacer()
                HStack(spacing: 3) {
                    Text("לכל התמונה")
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .heavy))
                }
                .font(.system(size: 13, weight: .bold))
                .opacity(0.9)
            }
            if let horizon {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    BigMoney(value: horizon.today.rounded(), size: 36)
                    Text("בבנק היום")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.88)
                }
                HorizonSpark(points: horizon.points)
                    .frame(height: 58)
                    .padding(.top, 2)
            }
            Text(sentence)
                .font(.system(size: 14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !list.isEmpty {
                VStack(spacing: 0) {
                    ForEach(list) { item in
                        HStack(spacing: 10) {
                            Text(item.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.abbreviated)))
                                .font(.system(size: 12, weight: .heavy))
                                .monospacedDigit()
                                .frame(width: 58, alignment: .leading)
                                .opacity(0.9)
                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            if !item.isKnown {
                                Text("הערכה")
                                    .font(.system(size: 10, weight: .heavy))
                                    .padding(.horizontal, 6)
                                    .frame(height: 17)
                                    .background(.white.opacity(0.2), in: Capsule())
                            }
                            Spacer(minLength: 6)
                            Text(Money.text(item.amount, showPlus: true))
                                .font(.system(size: 14, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(item.amount > 0 ? Color(hex: 0xA7F3D0) : Color.white)
                        }
                        .frame(height: 34)
                        if item.id != list.last?.id {
                            Divider().overlay(.white.opacity(0.22))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if events.count > list.count {
                    Text("ועוד \(events.count - list.count) עד סוף החודש הבא")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.85)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(HorizonView.artwork, radius: 26, seed: 0.7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("פתיחת קו האופק")
    }
}

/// The line of the coming weeks, drawn small and white on a colorful card.
struct HorizonSpark: View {
    let points: [Horizon.Point]
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let values: [Double] = points.map(\.balance)
        let low: Double = min(values.min() ?? 0, 0)
        let high: Double = max(values.max() ?? 1, low + 1)
        GeometryReader { proxy in
            let width: CGFloat = proxy.size.width
            let height: CGFloat = proxy.size.height
            let step: CGFloat = values.count > 1 ? width / CGFloat(values.count - 1) : width
            let spot: (Int) -> CGPoint = { index in
                let share: Double = (values[index] - low) / (high - low)
                return CGPoint(x: CGFloat(index) * step, y: height - 4 - (height - 8) * CGFloat(share))
            }
            ZStack {
                if low < 0 {
                    // The zero line, when the balance is going to cross it.
                    let zero: CGFloat = height - 4 - (height - 8) * CGFloat((0 - low) / (high - low))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: zero))
                        path.addLine(to: CGPoint(x: width, y: zero))
                    }
                    .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                if values.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height))
                        for index in values.indices {
                            path.addLine(to: spot(index))
                        }
                        path.addLine(to: CGPoint(x: width, y: height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(arrived || reduceMotion ? 1 : 0)
                    .animation(.smooth(duration: 0.6).delay(0.7), value: arrived)
                    Path { path in
                        path.move(to: spot(0))
                        for index in values.indices.dropFirst() {
                            path.addLine(to: spot(index))
                        }
                    }
                    .trim(from: 0, to: arrived || reduceMotion ? 1 : 0)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .animation(.smooth(duration: 1.1).delay(0.25), value: arrived)
                    if let lowest = values.indices.min(by: { values[$0] < values[$1] }) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                            .position(spot(lowest))
                            .opacity(arrived || reduceMotion ? 1 : 0)
                            .animation(.smooth(duration: 0.3).delay(1.2), value: arrived)
                    }
                }
            }
        }
        // Time runs from left to right, as on every chart in the app.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}
