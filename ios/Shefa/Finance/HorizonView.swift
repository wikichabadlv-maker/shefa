import Charts
import SwiftUI

/// The bank account in the coming weeks: where the balance is heading, what
/// is about to be charged and to arrive, and what is still owed on purchases
/// paid in payments. The screen opens in deep blue.
struct HorizonView: View {
    /// Every line the app holds. Months that the spreadsheet covers are in
    /// too: their bank lines still teach what returns every month.
    let entries: [LedgerEntry]

    static let artwork = Artwork(0x2563EB, 0x312E81)
    /// A balance below zero.
    static let rose = Color(hex: 0xE11D48)

    private enum Editing: Identifiable {
        case new
        case item(PlannedItem)
        case guess(Upcoming)

        var id: String {
            switch self {
            case .new: return "new"
            case .item(let item): return "item." + item.id
            case .guess(let guess): return "guess." + guess.id
            }
        }
    }

    @State private var plan = FinancePlan.shared
    @State private var bank = BankState.shared
    /// True once the big title has scrolled away under the bar.
    @State private var isScrolled = false
    @State private var editing: Editing? = Launch.screen == "finance-planned" ? .new : nil
    /// The expected line the family touched, and is asked about.
    @State private var asked: Upcoming?
    @State private var isSettingBalance = Launch.screen == "finance-balance"
    @Environment(\.layoutDirection) private var direction

    private var isAsking: Binding<Bool> {
        Binding(get: { asked != nil }, set: { if !$0 { asked = nil } })
    }

    var body: some View {
        let horizon: Horizon? = Forecast.horizon(entries, bank: bank, plan: plan)
        let events: [Upcoming] = horizon?.events ?? Forecast.upcoming(
            entries, after: Date.now.addingTimeInterval(-86_400), until: Forecast.windowEnd(), plan: plan)
        let owed: [Forecast.Commitment] = Forecast.commitments(entries)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(horizon)
                    .cascade(0)
                if let horizon {
                    HorizonChart(horizon: horizon)
                        .cascade(1)
                } else {
                    noBalance
                        .cascade(1)
                }
                eventsCard(events, horizon: horizon)
                    .cascade(2)
                if !owed.isEmpty {
                    commitmentsCard(owed)
                        .cascade(3)
                }
                actions
                    .cascade(4)
                Text("הקו בנוי מחיובי הכרטיסים, מתשלומים ומהכנסות שחוזרים כל חודש, וממה שהוספתם בעצמכם. קניות יומיומיות שלא בכרטיס אינן בתוכו, ולכן כדאי להשאיר מרווח.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .cascade(5)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .background(alignment: .top) {
                StageBackdrop(artwork: HorizonView.artwork, height: horizon == nil ? 360 : 470)
            }
        }
        .background(Theme.ground)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 110
        } action: { _, isPast in
            withAnimation(.smooth(duration: 0.25)) { isScrolled = isPast }
        }
        .task {
            // A test run can open the screen lower down.
            guard !Launch.anchor.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1.5))
            proxy.scrollTo(Launch.anchor, anchor: .top)
        }
        }
        .navigationTitle("קו האופק")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The name waits in the bar until the big title scrolls away.
            ToolbarItem(placement: .principal) {
                Text("קו האופק")
                    .font(.system(size: 17, weight: .semibold))
                    .opacity(isScrolled ? 1 : 0)
            }
        }
        .toolbarColorScheme(isScrolled ? nil : .dark, for: .navigationBar)
        .arrives()
        .sheet(item: $editing) { item in
            switch item {
            case .new: PlannedSheet()
            case .item(let planned): PlannedSheet(item: planned)
            case .guess(let guess): PlannedSheet(guess: guess)
            }
        }
        .sheet(isPresented: $isSettingBalance) {
            BalanceSheet()
        }
        .confirmationDialog(asked?.title ?? "", isPresented: isAsking, titleVisibility: .visible,
                            presenting: asked) { event in
            Button("לקבוע סכום ויום בעצמי") { replace(event) }
            // A bill made of purchases that already arrived is not a guess.
            if !(event.kind == .card && event.isKnown) {
                Button("זה לא יחזור", role: .destructive) {
                    withAnimation(.section) { plan.hide(event.key) }
                }
            }
            Button("ביטול", role: .cancel) {}
        } message: { event in
            Text(event.note ?? "כך זה נראה לפי החודשים הקודמים.")
        }
    }

    /// Where the balance is heading, in one sentence.
    static func sentence(_ horizon: Horizon) -> String {
        let calendar = Calendar.current
        if let below = horizon.firstBelowZero {
            if below.id == 0 {
                if let back = horizon.points.first(where: { $0.balance >= 0 }) {
                    return "החשבון מתחת לאפס. לפי מה שצפוי, הוא חוזר לפלוס ב־\(Ledger.dayText(back.date))."
                }
                return "החשבון מתחת לאפס, ולפי מה שצפוי הוא נשאר כך עד סוף החודש הבא."
            }
            var text: String = "ב־\(Ledger.dayText(below.date)) החשבון צפוי לרדת מתחת לאפס"
            let cause: Upcoming? = horizon.events
                .filter { $0.amount < 0 && calendar.isDate($0.date, inSameDayAs: below.date) }
                .min { $0.amount < $1.amount }
            if let cause { text += ", עם \(cause.title)" }
            return text + "."
        }
        if let low = horizon.lowest, low.balance < horizon.today - 1 {
            var text: String = "הנקודה הנמוכה: \(Money.text(Decimal(low.balance.rounded()))) ב־\(Ledger.dayText(low.date))"
            if let cause = horizon.lowestCause { text += ", אחרי \(cause.title)" }
            return text + "."
        }
        return "היתרה לא צפויה לרדת מתחת למה שיש היום."
    }

    /// The top of the stage: white type straight on the color, no card.
    private func header(_ horizon: Horizon?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 60, height: 60)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                Spacer()
                if let horizon {
                    Text((horizon.isManual ? "הוזנה " : "מעודכן ") + BankState.ago(horizon.asOf))
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }
            Text("קו האופק")
                .font(.system(size: 34, weight: .heavy))
                .padding(.top, 6)
            if let horizon {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BigMoney(value: horizon.today.rounded(), size: 62)
                    Text("בבנק היום")
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(0.9)
                }
                Text(HorizonView.sentence(horizon))
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("מה צפוי לרדת מהחשבון ולהיכנס אליו עד סוף החודש הבא.")
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottomTrailing) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 170, weight: .bold))
                .foregroundStyle(.white.opacity(0.1))
                .offset(x: direction == .rightToLeft ? -30 : 30, y: 20)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Shown in place of the line when no balance is known.
    private var noBalance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("עוד אין יתרה")
                .font(.system(size: 20, weight: .heavy))
            Text("היתרה מגיעה מהבנק עם הסנכרון. אפשר גם להזין אותה עכשיו, והקו יצויר מיד.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Feedback.tap()
                isSettingBalance = true
            } label: {
                Text("הזנת יתרה")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(HorizonView.artwork.gradient, in: Capsule())
            }
            .buttonStyle(.pressable)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: What is expected

    /// The balance at the end of each day that has something expected,
    /// keyed by the last line of that day.
    private func closing(_ events: [Upcoming], horizon: Horizon?) -> [String: Double] {
        guard let horizon else { return [:] }
        let calendar = Calendar.current
        var lastOfDay: [Date: String] = [:]
        for event in events {
            lastOfDay[calendar.startOfDay(for: event.date)] = event.id
        }
        var result: [String: Double] = [:]
        for point in horizon.points {
            if let id = lastOfDay[point.date] { result[id] = point.balance }
        }
        return result
    }

    private func eventsCard(_ events: [Upcoming], horizon: Horizon?) -> some View {
        let incoming: Decimal = events.reduce(Decimal(0)) { $0 + max($1.amount, 0) }
        let outgoing: Decimal = events.reduce(Decimal(0)) { $0 - min($1.amount, 0) }
        let balances: [String: Double] = closing(events, horizon: horizon)
        let hiddenCount: Int = plan.hidden.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("מה צפוי")
                .font(.system(size: 20, weight: .heavy))
            if events.isEmpty {
                Text("עוד לא זוהה שום דבר שחוזר כל חודש. אחרי חודש או שניים של תנועות מהבנק זה יתמלא לבד, ואפשר להוסיף כבר עכשיו.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("עד סוף החודש הבא צפויים להיכנס \(Money.text(incoming)) ולרדת \(Money.text(outgoing)).")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        Button {
                            tapped(event)
                        } label: {
                            row(event, closing: balances[event.id])
                        }
                        .buttonStyle(.pressable)
                        if event.id != events.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
            }
            if hiddenCount > 0 {
                Button {
                    withAnimation(.section) { plan.unhideAll() }
                } label: {
                    Text(hiddenCount == 1 ? "הסתרתם שורה אחת מהקו. להחזיר אותה"
                         : "הסתרתם \(hiddenCount) שורות מהקו. להחזיר אותן")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.pressable)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .id("events")
    }

    private func row(_ event: Upcoming, closing: Double?) -> some View {
        let calendar = Calendar.current
        let color: Color = event.artwork.start
        let number: Int = calendar.component(.day, from: event.date)
        let month: String = event.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.abbreviated))
        var parts: [String] = []
        if calendar.isDateInToday(event.date) {
            parts.append("היום")
        } else if calendar.isDateInTomorrow(event.date) {
            parts.append("מחר")
        } else {
            parts.append(event.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).weekday(.wide)))
        }
        if let note = event.note {
            parts.append(note)
        } else if let id = event.plannedID {
            let item: PlannedItem? = plan.planned.first { $0.id == id }
            if let item, item.isMonthly {
                // A day that fell on a weekend was carried to Sunday; the
                // day the family chose is said, so the move is understood.
                let isMoved: Bool = calendar.component(.day, from: event.date) != item.day
                parts.append(isMoved ? "קבעתם ל־\(item.day) בחודש, כל חודש" : "קבעתם, כל חודש")
            } else {
                parts.append("קבעתם")
            }
        }
        let detail: String = parts.joined(separator: " · ")
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        return HStack(spacing: 12) {
            VStack(spacing: -1) {
                Text("\(number)")
                    .font(.system(size: 19, weight: .heavy))
                    .monospacedDigit()
                Text(month)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(color)
            .frame(width: 46, height: 46)
            .background {
                // A full leaf is a known figure; a dashed one is an estimate.
                if event.isKnown {
                    shape.fill(color.opacity(0.16))
                } else {
                    shape.strokeBorder(color.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Money.text(event.amount, showPlus: true))
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(event.amount > 0 ? Theme.accent : Color.primary)
                if let closing {
                    Text("יתרה \(Money.text(Decimal(closing.rounded())))")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(closing < 0 ? HorizonView.rose : Color.secondary)
                }
            }
        }
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func tapped(_ event: Upcoming) {
        Feedback.tap()
        if let id = event.plannedID, let item = plan.planned.first(where: { $0.id == id }) {
            editing = .item(item)
        } else {
            asked = event
        }
    }

    private func replace(_ event: Upcoming) {
        Task { @MainActor in
            // The question has to finish closing before a sheet can open.
            try? await Task.sleep(for: .seconds(0.35))
            editing = .guess(event)
        }
    }

    // MARK: Payments

    private func commitmentsCard(_ list: [Forecast.Commitment]) -> some View {
        let total: Decimal = list.reduce(Decimal(0)) { $0 + $1.remaining }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("קניות בתשלומים")
                    .font(.system(size: 20, weight: .heavy))
                Spacer()
                Text("נשארו \(Money.text(total))")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ForEach(list) { item in
                let month: String = item.ends.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide).year())
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(Money.text(item.remaining))
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                    }
                    GrowBar(share: Double(item.total - item.left) / Double(max(item.total, 1)), height: 7,
                            delay: 0.3, fill: HorizonView.artwork.gradient)
                    Text(item.left == 1
                         ? "נשאר תשלום אחד של \(Money.text(item.payment)), ב\(month)"
                         : "נשארו \(item.left) תשלומים של \(Money.text(item.payment)), עד \(month)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Text("התשלומים האלה כבר בתוך חיובי הכרטיס שבקו.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .id("payments")
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                Feedback.tap()
                editing = .new
            } label: {
                actionLabel("plus", "תשלום או הכנסה", "מוסיפים לקו")
                    .foregroundStyle(.white)
                    .background(HorizonView.artwork.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.pressable)
            Button {
                Feedback.tap()
                isSettingBalance = true
            } label: {
                actionLabel("pencil", "עדכון יתרה", bank.manual == nil ? "כשהנתון מהבנק ישן" : "הוזנה ידנית")
                    .foregroundStyle(Color.primary)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
            }
            .buttonStyle(.pressable)
        }
    }

    private func actionLabel(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .heavy))
                .frame(height: 22)
            Text(title)
                .font(.system(size: 16, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The line itself. A finger dragged along it reads the balance of any day.
private struct HorizonChart: View {
    let horizon: Horizon
    @State private var scrubbed: Date?

    private struct Dot: Identifiable {
        let id: Int
        let date: Date
        let balance: Double
        let isIn: Bool
    }

    /// One mark for every day on which something is expected.
    private var dots: [Dot] {
        let calendar = Calendar.current
        var net: [Date: Decimal] = [:]
        for event in horizon.events {
            net[calendar.startOfDay(for: event.date), default: 0] += event.amount
        }
        var result: [Dot] = []
        for point in horizon.points {
            guard let change = net[point.date], change != 0 else { continue }
            result.append(Dot(id: point.id, date: point.date, balance: point.balance, isIn: change > 0))
        }
        return result
    }

    private func point(at date: Date) -> Horizon.Point? {
        horizon.points.last { $0.date <= date } ?? horizon.points.first
    }

    private static func short(_ number: Double) -> String {
        let size: Double = abs(number)
        let sign: String = number < 0 ? "−" : ""
        return size >= 1000 ? "\(sign)\(Int((size / 1000).rounded()))K" : "\(sign)\(Int(size))"
    }

    var body: some View {
        let points: [Horizon.Point] = horizon.points
        let blue: Color = HorizonView.artwork.start
        let green: Color = Color(hex: 0x10B981)
        let lowest: Horizon.Point? = horizon.lowest
        let goesBelow: Bool = (lowest?.balance ?? 0) < 0
        let marked: Horizon.Point? = scrubbed.flatMap { point(at: $0) }
        let marks: [Dot] = dots
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("לאן היתרה הולכת")
                    .font(.system(size: 20, weight: .heavy))
                Spacer()
                if let last = points.last {
                    Text("עד \(Ledger.dayText(last.date))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("יום", point.date), y: .value("יתרה", point.balance))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(LinearGradient(colors: [blue.opacity(0.32), blue.opacity(0.05)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("יום", point.date), y: .value("יתרה", point.balance))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(blue)
                }
                if goesBelow {
                    RuleMark(y: .value("אפס", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(HorizonView.rose)
                }
                ForEach(marks) { dot in
                    PointMark(x: .value("יום", dot.date), y: .value("יתרה", dot.balance))
                        .symbolSize(34)
                        .foregroundStyle(dot.isIn ? green : blue)
                }
                if let marked {
                    RuleMark(x: .value("יום", marked.date))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .annotation(position: .top, spacing: 2,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            bubble(marked)
                        }
                    PointMark(x: .value("יום", marked.date), y: .value("יתרה", marked.balance))
                        .symbolSize(110)
                        .foregroundStyle(marked.balance < 0 ? HorizonView.rose : blue)
                } else if let lowest, lowest.balance < horizon.today - 1 {
                    PointMark(x: .value("יום", lowest.date), y: .value("יתרה", lowest.balance))
                        .symbolSize(110)
                        .foregroundStyle(lowest.balance < 0 ? HorizonView.rose : blue)
                }
            }
            .chartXSelection(value: $scrubbed)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.defaultDigits)))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(HorizonChart.short(number))
                        }
                    }
                }
            }
            .frame(height: 210)
            // Room for the top label of the axis, which sits half above the chart.
            .padding(.top, 8)
            .reveal(.leading, delay: 0.3)
            // Time runs from left to right, as on every chart in the app.
            .environment(\.layoutDirection, .leftToRight)
            .sensoryFeedback(.selection, trigger: marked?.id)
            HStack(spacing: 14) {
                legend(green, "נכנס")
                legend(blue, "יורד")
                Spacer(minLength: 0)
                Text("גררו אצבע על הקו כדי לראות כל יום")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("תרשים היתרה הצפויה. \(HorizonView.sentence(horizon))")
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func bubble(_ point: Horizon.Point) -> some View {
        VStack(spacing: 0) {
            Text(point.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(Money.text(Decimal(point.balance.rounded())))
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(point.balance < 0 ? HorizonView.rose : Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A payment or an income the family expects, added to the horizon by hand.
struct PlannedSheet: View {
    private let existing: PlannedItem?
    /// The key of the app's guess that this item takes the place of.
    private let replaces: String?
    @Environment(\.dismiss) private var dismiss
    @State private var isIncome: Bool
    @State private var title: String
    @State private var amountText: String
    @State private var isMonthly: Bool
    @State private var day: Int
    @State private var date: Date
    @FocusState private var isAmountFocused: Bool

    init(item: PlannedItem? = nil, guess: Upcoming? = nil) {
        let calendar = Calendar.current
        existing = item
        replaces = item?.replaces ?? guess?.key
        var income = false
        var name = ""
        var size: Double = 0
        var monthly = true
        var number: Int = calendar.component(.day, from: .now)
        var when: Date = calendar.date(byAdding: .day, value: 7, to: .now) ?? .now
        if let item {
            income = item.amount > 0
            name = item.title
            size = abs(item.amount)
            monthly = item.isMonthly
            number = item.day
            when = item.date ?? when
        } else if let guess {
            income = guess.amount > 0
            name = guess.title
            size = abs(guess.amount.double)
            number = calendar.component(.day, from: guess.date)
            when = guess.date
        }
        _isIncome = State(initialValue: income)
        _title = State(initialValue: name)
        _amountText = State(initialValue: size <= 0 ? "" : (size == size.rounded() ? String(Int(size)) : String(format: "%.2f", size)))
        _isMonthly = State(initialValue: monthly)
        _day = State(initialValue: min(max(number, 1), 31))
        _date = State(initialValue: max(when, calendar.startOfDay(for: .now)))
    }

    private var amount: Decimal? {
        guard let value = Ledger.amount(from: amountText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("סוג", selection: $isIncome) {
                        Text("תשלום").tag(false)
                        Text("הכנסה").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    amountCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    TextField(isIncome ? "ממי? למשל החזר מס" : "על מה? למשל ועד בית", text: $title)
                }

                Section {
                    Toggle("חוזר כל חודש", isOn: $isMonthly)
                    if isMonthly {
                        Picker("באיזה יום", selection: $day) {
                            ForEach(1...31, id: \.self) { number in
                                Text("\(number) בחודש").tag(number)
                            }
                        }
                    } else {
                        DatePicker("תאריך", selection: $date, in: Calendar.current.startOfDay(for: .now)...,
                                   displayedComponents: .date)
                    }
                } footer: {
                    Text(isMonthly
                         ? "בחודש שאין בו יום כזה, זה נרשם ביום האחרון שלו."
                         : "אחרי התאריך הזה השורה יורדת מהקו מעצמה.")
                }

                if replaces != nil, existing == nil {
                    Section {
                        Text("מה שתקבעו כאן יופיע בקו במקום ההערכה של האפליקציה.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                if let existing {
                    Section {
                        Button("הסרה מהקו", role: .destructive) {
                            FinancePlan.shared.removePlanned(existing.id)
                            dismiss()
                        }
                    }
                }
            }
            .animation(.snappy, value: isMonthly)
            .navigationTitle(existing == nil ? "הוספה לקו האופק" : "עריכה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { save() }
                        .disabled(amount == nil)
                }
            }
            .task {
                guard existing == nil, amountText.isEmpty else { return }
                try? await Task.sleep(for: .seconds(0.6))
                isAmountFocused = true
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.large])
    }

    /// The amount, on the color of its direction: blue for money that goes
    /// out, green for money that comes in.
    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isIncome ? "כמה צפוי להיכנס" : "כמה צפוי לרדת")
                .font(.system(size: 14, weight: .bold))
                .opacity(0.92)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("₪")
                    .font(.system(size: 28, weight: .bold))
                    .opacity(0.85)
                TextField("", text: $amountText)
                    .font(.system(size: 50, weight: .heavy))
                    .keyboardType(.decimalPad)
                    .focused($isAmountFocused)
                    .tint(.white)
                    .overlay(alignment: .leading) {
                        if amountText.isEmpty {
                            Text("0")
                                .font(.system(size: 50, weight: .heavy))
                                .opacity(0.4)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(isIncome ? Theme.green : HorizonView.artwork, radius: 24, seed: 0.3,
                    watermark: isIncome ? "banknote.fill" : "calendar", isMoving: false)
        .animation(.smooth(duration: 0.3), value: isIncome)
    }

    private func save() {
        guard let amount else { return }
        let calendar = Calendar.current
        let name: String = title.trimmingCharacters(in: .whitespaces)
        let fallback: String = isIncome ? "הכנסה צפויה" : "תשלום צפוי"
        let signed: Double = isIncome ? amount.double : -amount.double
        var item: PlannedItem = existing ?? PlannedItem(title: fallback, amount: signed, day: day, isMonthly: isMonthly)
        item.title = name.isEmpty ? fallback : name
        item.amount = signed
        item.isMonthly = isMonthly
        item.day = isMonthly ? day : calendar.component(.day, from: date)
        item.date = isMonthly ? nil : calendar.startOfDay(for: date)
        item.replaces = replaces
        FinancePlan.shared.savePlanned(item)
        Feedback.added()
        dismiss()
    }
}

/// The bank balance typed by hand, for a home whose bank is not connected
/// or whose figure is stale.
struct BalanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bank = BankState.shared
    @State private var amountText = ""
    @State private var isBelowZero = false
    @FocusState private var isFocused: Bool

    private var amount: Decimal? { Ledger.amount(from: amountText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(isBelowZero ? "−₪" : "₪")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("", text: $amountText)
                            .font(.system(size: 44, weight: .heavy))
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                            .overlay(alignment: .leading) {
                                // The hint stands where the digits will.
                                if amountText.isEmpty {
                                    Text("0")
                                        .font(.system(size: 44, weight: .heavy))
                                        .foregroundStyle(.tertiary)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    Toggle("החשבון במינוס", isOn: $isBelowZero)
                } header: {
                    Text("כמה יש בחשבון הבנק עכשיו")
                } footer: {
                    Text("כשיגיע מהבנק נתון חדש יותר, הוא יחליף את מה שהוזן כאן.")
                }

                if bank.manual != nil {
                    Section {
                        Button("מחיקת היתרה שהוזנה", role: .destructive) {
                            bank.setManual(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("עדכון יתרה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        guard let amount else { return }
                        bank.setManual(isBelowZero ? -amount.double : amount.double)
                        Feedback.added()
                        dismiss()
                    }
                    .disabled(amount == nil)
                }
            }
            .onAppear {
                guard let manual = bank.manual else { return }
                isBelowZero = manual.amount < 0
                amountText = String(Int(abs(manual.amount).rounded()))
            }
            .task {
                try? await Task.sleep(for: .seconds(0.6))
                isFocused = true
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium, .large])
    }
}
