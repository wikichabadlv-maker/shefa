import SwiftData
import SwiftUI

/// The frame the day's two sittings share: a title, how far along it is, a
/// way out, the step itself and one main button at the bottom.
struct FlowFrame<Content: View>: View {
    let title: String
    let subtitle: String
    /// Counted from 0.
    let step: Int
    let steps: Int
    let artwork: Artwork
    let mainTitle: String
    var mainSymbol: String = "arrow.forward"
    var isMainOn: Bool = true
    var back: (() -> Void)? = nil
    let close: () -> Void
    let main: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            top
            ScrollView {
                content()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    .id(step)
                    // Forward is leftward in a right-to-left layout.
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -26)),
                                            removal: .opacity))
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            bottom
        }
        .animation(.smooth(duration: 0.32), value: step)
    }

    private var top: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 28, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.primary)
                        .frame(width: 40, height: 40)
                        .background(Theme.chip, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("סגירה")
            }
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AnyShapeStyle(artwork.gradient) : AnyShapeStyle(Theme.chip))
                        .frame(height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var bottom: some View {
        HStack(spacing: 10) {
            if let back {
                Button(action: back) {
                    Image(systemName: "arrow.backward")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color.primary)
                        .frame(width: 54, height: 54)
                        .background(Theme.chip, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("חזרה")
            }
            Button(action: main) {
                HStack(spacing: 8) {
                    Text(mainTitle)
                        .font(.system(size: 17, weight: .heavy))
                    Image(systemName: mainSymbol)
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(artwork.gradient, in: Capsule())
                .opacity(isMainOn ? 1 : 0.4)
            }
            .buttonStyle(.pressable)
            .disabled(!isMainOn)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

/// The last page of a sitting: one picture, a few words and the way out.
private struct FlowEnding: View {
    let symbol: String
    let artwork: Artwork
    let title: String
    let text: String
    var extraTitle: String? = nil
    var extra: (() -> Void)? = nil
    let doneTitle: String
    let done: () -> Void
    @State private var isIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 62, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 140, height: 140)
                .background(artwork.gradient, in: Circle())
                .shadow(color: artwork.end.opacity(0.4), radius: 22, y: 12)
                .scaleEffect(isIn || reduceMotion ? 1 : 0.7)
                .opacity(isIn ? 1 : 0)
            Text(title)
                .font(.system(size: 30, weight: .heavy))
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
            Spacer()
            if let extraTitle, let extra {
                Button(action: extra) {
                    Label(extraTitle, systemImage: "play.fill")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(artwork.gradient, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
            Button(action: done) {
                Text(doneTitle)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(extra == nil ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(extra == nil ? AnyShapeStyle(artwork.gradient) : AnyShapeStyle(Theme.chip), in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) { isIn = true }
        }
    }
}

/// A small label on a colorful card.
private struct OnColorBadge: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .heavy))
            }
            Text(text)
                .font(.system(size: 12, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(.white.opacity(0.2), in: Capsule())
    }
}

// MARK: - Building the day

/// The morning sitting, in three steps: the day as it stands, what goes
/// into it, and where and when the first step is taken. Nothing is written
/// until the last step is confirmed.
struct PlanDayFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" && !$0.removed && !$0.isDone },
           sort: \ListItem.createdAt, order: .reverse)
    private var tasks: [ListItem]
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }) private var schedule: [ScheduleItem]
    @State private var feed = CalendarFeed.shared

    @State private var step = Launch.flowStep
    /// The tasks chosen for today in this sitting.
    @State private var picked: Set<String> = []
    @State private var hasLoaded = false
    /// The task to begin with, when another than the first was chosen.
    @State private var firstID: String?
    @State private var firstMinute: Int?
    @State private var place = UserDefaults.standard.string(forKey: PlanDayFlow.placeKey) ?? ""
    @State private var customTime = Date.now
    @State private var showsClock = false
    @State private var isDone = false
    @FocusState private var isTyping: Bool

    private static let placeKey = "coach.place"
    private static let places = ["בבית", "בעבודה", "ליד המחשב", "בטלפון", "בדרך"]
    private static let lengths = [5, 10, 15, 20, 30, 45, 60, 90, 120]
    private static let morning = Artwork(0xF59E0B, 0xDB2777)

    private var chosen: [ListItem] { tasks.filter { picked.contains($0.id) } }

    var body: some View {
        let now: Date = .now
        let events: [DayEvent] = feed.on(now)
        // The day with nothing in it, and the day with what was chosen so far.
        let base: DayPlan = DayPlan.make(day: now, tasks: tasks, schedule: schedule, events: events, now: now,
                                         chosen: [], intention: nil)
        let first: ListItem? = firstTask(in: base, now: now)
        let cue: DayJournal.Intention? = intention(for: first)
        let trial: DayPlan = DayPlan.make(day: now, tasks: tasks, schedule: schedule, events: events, now: now,
                                          chosen: chosen, intention: cue)
        ZStack {
            AmbientGround(artwork: step == 0 ? PlanDayFlow.morning : (trial.load == .over ? Theme.amber : Theme.blue))
            if isDone {
                ending(trial, first: first, now: now)
            } else {
                FlowFrame(title: title, subtitle: subtitle(trial), step: step, steps: 3,
                          artwork: step == 0 ? PlanDayFlow.morning : Theme.blue,
                          mainTitle: step == 2 ? "זה היום שלי" : (step == 0 ? "מה נכנס היום?" : "הצעד הראשון"),
                          mainSymbol: step == 2 ? "checkmark" : "arrow.forward",
                          back: step > 0 ? { step -= 1 } : nil,
                          close: { dismiss() },
                          main: { advance(trial, first: first) }) {
                    switch step {
                    case 0: dayPage(base, now: now)
                    case 1: pickPage(trial, now: now)
                    default: firstPage(base: base, trial: trial, first: first, now: now)
                    }
                }
            }
        }
        .arrives()
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { load() }
        .onChange(of: tasks.count) { _, _ in load() }
    }

    /// What is already on the day is where the sitting begins.
    private func load() {
        guard !hasLoaded, !tasks.isEmpty else { return }
        hasLoaded = true
        picked = Set(tasks.filter(\.isForToday).map(\.id))
        if let saved = DayJournal.intention {
            firstID = saved.taskID
            firstMinute = saved.minute
            if !saved.place.isEmpty { place = saved.place }
        }
    }

    private var title: String {
        switch step {
        case 0: return "בונים את היום"
        case 1: return "מה נכנס היום?"
        default: return "הצעד הראשון"
        }
    }

    private func subtitle(_ trial: DayPlan) -> String {
        switch step {
        case 0: return "שלושה צעדים קצרים, ופחות משתי דקות"
        case 1:
            if picked.isEmpty { return "בחרו מעט. מה שנעשה שווה יותר ממה שנדחה" }
            return picked.count == 1 ? "נבחרה מטלה אחת" : "נבחרו \(picked.count) מטלות"
        default: return "מי שקובע מראש מתי ואיפה, מתחיל"
        }
    }

    // MARK: The day as it stands

    private func dayPage(_ base: DayPlan, now: Date) -> some View {
        let sky: Sky = Sky.now(now)
        let date: String = now.formatted(Date.FormatStyle(locale: Ledger.hebrew).weekday(.wide).day().month(.wide))
        let minute: Int = ScheduleItem.minute(of: now)
        let parts: [DayBlock] = base.blocks.filter { $0.span.end > minute }
        let hasRoom: Bool = base.roomMinutes >= 10
        let headline: String = hasRoom ? "מקום לכ־\(NowStatus.duration((base.roomMinutes / 5) * 5))" : "אין היום זמן פנוי"
        let text: String = hasRoom
            ? "זה הזמן שנשאר למטלות בין החלקים הקבועים של היום, אחרי מרווח לדברים שמתארכים."
            : "החלקים הקבועים ממלאים את היום. מה שייבחר ייכנס ליום הבא."
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    OnColorBadge(text: date)
                    OnColorBadge(text: HebrewDate.text(now))
                }
                if let name = base.dayName {
                    Text(name)
                        .font(.system(size: 15, weight: .heavy))
                        .opacity(0.95)
                        .padding(.top, 2)
                }
                Text(headline)
                    .font(.system(size: 34, weight: .heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
                DayMap(plan: base, now: now, height: 26, isOnColor: true)
                    .padding(.top, 6)
                if let note = base.closingNote {
                    Label(note, systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.95)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .livingCard(sky.isNight ? sky.artwork : PlanDayFlow.morning, seed: 0.5,
                        watermark: sky.isNight ? "moon.stars.fill" : "sun.max.fill")
            .cascade(0)

            if !parts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("מה כבר קבוע היום")
                        .font(.system(size: 20, weight: .heavy))
                        .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(parts) { block in
                            fixedRow(block)
                            if block.id != parts.last?.id {
                                Divider().padding(.leading, 20)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .cardSurface()
                }
                .cascade(1)
            }
        }
    }

    private func fixedRow(_ block: DayBlock) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(block.artwork.gradient)
                .frame(width: 6, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(TaskRow.range(block.span))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if block.isOpen {
                Text("זמן למטלות")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Theme.chip, in: Capsule())
            }
            if block.isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(minHeight: 54)
        .opacity(block.isDone ? 0.6 : 1)
    }

    // MARK: What goes in

    private func pickPage(_ trial: DayPlan, now: Date) -> some View {
        let left: [ListItem] = tasks.filter { $0.isLeftOver && !$0.isForToday }
        let todays: [ListItem] = DayPlan.ordered(tasks.filter(\.isForToday))
        let dated: [ListItem] = tasks.filter { !$0.isForToday && !$0.isLeftOver && $0.due != nil }
        let soon: [ListItem] = dated.sorted { ($0.due ?? .now) < ($1.due ?? .now) }
        let someday: [ListItem] = tasks.filter { !$0.isForToday && !$0.isLeftOver && $0.due == nil }
        return VStack(alignment: .leading, spacing: 16) {
            DayRingHero(plan: trial, doneCount: 0, now: now)
            if tasks.isEmpty {
                Text("אין מטלות פתוחות. אפשר לסגור, ולהוסיף מטלות במסך המטלות.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            group("נשארו מיום קודם", left)
            group("כבר על היום", todays)
            group("בקרוב", soon)
            group("מתישהו", someday)
        }
    }

    @ViewBuilder
    private func group(_ name: String, _ list: [ListItem]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.system(size: 20, weight: .heavy))
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(list) { task in
                        pickRow(task)
                        if task.id != list.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .cardSurface()
            }
        }
    }

    private func pickRow(_ task: ListItem) -> some View {
        let isOn: Bool = picked.contains(task.id)
        let due: String? = task.dueText
        return HStack(spacing: 8) {
            Button {
                Feedback.tap()
                var next: Set<String> = picked
                if isOn { next.remove(task.id) } else { next.insert(task.id) }
                withAnimation(.snappy) { picked = next }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isOn ? AnyShapeStyle(Theme.amber.gradient) : AnyShapeStyle(Theme.chip))
                        Image(systemName: isOn ? "sun.max.fill" : "plus")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(isOn ? Color.white : Color.secondary)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            if task.priority > 0 {
                                Image(systemName: "flag.fill").foregroundStyle(Color(hex: 0xEA580C))
                            }
                            if let due {
                                Text(due).foregroundStyle(task.isOverdue ? Theme.amberInk : Color.secondary)
                            }
                            if task.isStuck {
                                Text("נדחתה \(task.pushed) פעמים").foregroundStyle(Theme.amberInk)
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityAddTraits(isOn ? .isSelected : [])

            lengthMenu(task)
        }
        .frame(minHeight: 56)
    }

    /// The task's length, which decides how much of the day it takes.
    private func lengthMenu(_ task: ListItem) -> some View {
        let isSet: Bool = task.minutes > 0
        let text: String = isSet ? NowStatus.duration(task.minutes) : "כ־" + NowStatus.duration(DayJournal.typicalMinutes)
        return Menu {
            ForEach(PlanDayFlow.lengths, id: \.self) { value in
                Button(NowStatus.duration(value)) {
                    withAnimation(.snappy) { TaskRules.trim(task, to: value, in: context) }
                }
            }
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isSet ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.chip, in: Capsule())
        }
        .accessibilityLabel("כמה זמן זה ייקח")
    }

    // MARK: The first step

    /// The task the day begins with: the one chosen for it, or the first in
    /// the order of the day.
    private func firstTask(in base: DayPlan, now: Date) -> ListItem? {
        let list: [ListItem] = DayPlan.ordered(chosen)
        if let firstID, let task = list.first(where: { $0.id == firstID }) { return task }
        return list.first
    }

    private func intention(for first: ListItem?) -> DayJournal.Intention? {
        guard let first, let firstMinute else { return nil }
        return DayJournal.Intention(day: DayKey.of(), taskID: first.id, minute: firstMinute,
                                    place: place.trimmingCharacters(in: .whitespaces))
    }

    /// The moments the day offers for a beginning: now, and after each of
    /// its fixed parts.
    private func timeOptions(_ base: DayPlan, now: Date) -> [(minute: Int, title: String)] {
        let current: Int = ScheduleItem.minute(of: now)
        var result: [(minute: Int, title: String)] = []
        for window in base.free.prefix(4) {
            if window.start <= current + 10 {
                result.append((window.start, "עכשיו"))
            } else if let block = base.blocks.first(where: { $0.span.end == window.start }) {
                result.append((window.start, "אחרי \(block.title) · \(ScheduleItem.clock(window.start))"))
            } else {
                result.append((window.start, "ב־\(ScheduleItem.clock(window.start))"))
            }
        }
        return result
    }

    private func firstPage(base: DayPlan, trial: DayPlan, first: ListItem?, now: Date) -> some View {
        let options: [(minute: Int, title: String)] = timeOptions(base, now: now)
        let current: Int = ScheduleItem.minute(of: now)
        let order: [ListItem] = DayPlan.ordered(chosen)
        let isCustom: Bool = firstMinute != nil && !options.contains(where: { $0.minute == firstMinute })
        return VStack(alignment: .leading, spacing: 16) {
            if let first {
                sentenceCard(first, current: current)
                    .cascade(0)

                if order.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        label("במה מתחילים?")
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(order) { task in
                                    chip(task.title, isOn: task.id == first.id) { firstID = task.id }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .scrollIndicators(.hidden)
                        .padding(.horizontal, -16)
                    }
                    .cascade(1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    label("מתי?")
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(options, id: \.minute) { option in
                                chip(option.title, isOn: firstMinute == option.minute) {
                                    firstMinute = option.minute
                                    showsClock = false
                                }
                            }
                            chip(isCustom ? "ב־" + ScheduleItem.clock(firstMinute ?? 0) : "שעה אחרת",
                                 isOn: isCustom || showsClock) {
                                showsClock.toggle()
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -16)
                    if showsClock {
                        DatePicker("באיזו שעה", selection: $customTime, displayedComponents: .hourAndMinute)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 54)
                            .cardSurface()
                            .onChange(of: customTime) { _, value in
                                firstMinute = ScheduleItem.minute(of: value)
                            }
                            .transition(.sectionSwap)
                    }
                }
                .cascade(2)

                VStack(alignment: .leading, spacing: 8) {
                    label("איפה?")
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(PlanDayFlow.places, id: \.self) { name in
                                chip(name, isOn: place == name) {
                                    place = place == name ? "" : name
                                    isTyping = false
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -16)
                    TextField("מקום אחר", text: $place)
                        .focused($isTyping)
                        .submitLabel(.done)
                        .font(.system(size: 16))
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .background(Theme.card, in: Capsule())
                }
                .cascade(3)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("לא נבחרו מטלות להיום")
                        .font(.system(size: 20, weight: .heavy))
                    Text("גם יום כזה הוא יום. החלקים הקבועים שלו נשארים, והמטלות מחכות ברשימה.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
        .animation(.smooth(duration: 0.3), value: showsClock)
    }

    /// The first step said as one sentence, the way it will be remembered.
    private func sentenceCard(_ first: ListItem, current: Int) -> some View {
        var parts: [String] = []
        if let firstMinute {
            parts.append(firstMinute <= current + 10 ? "עכשיו" : "ב־" + ScheduleItem.clock(firstMinute))
        }
        let spot: String = place.trimmingCharacters(in: .whitespaces)
        if !spot.isEmpty { parts.append(spot) }
        let lead: String = parts.isEmpty ? "אתחיל ב:" : parts.joined(separator: ", ") + ", אתחיל ב:"
        return VStack(alignment: .leading, spacing: 6) {
            OnColorBadge(text: "הצעד הראשון", symbol: "figure.walk")
            Text(lead)
                .font(.system(size: 17, weight: .semibold))
                .opacity(0.95)
                .padding(.top, 6)
                .contentTransition(.opacity)
            Text(first.title)
                .font(.system(size: 28, weight: .heavy))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if firstMinute == nil {
                Text("בחרו מתי ואיפה. משפט אחד כזה מעלה מאוד את הסיכוי שזה יקרה.")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(Theme.violet, seed: 0.7, watermark: "figure.walk")
        .animation(.smooth(duration: 0.25), value: lead)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .heavy))
            .padding(.horizontal, 4)
    }

    private func chip(_ name: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Feedback.tap()
            withAnimation(.snappy) { action() }
        } label: {
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? AnyShapeStyle(Theme.violet.gradient) : AnyShapeStyle(Theme.card), in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Writing it down

    private func advance(_ trial: DayPlan, first: ListItem?) {
        Feedback.tap()
        isTyping = false
        guard step == 2 else {
            step += 1
            return
        }
        // Only now is anything written: what was chosen is today's, and
        // what was taken off goes back to the list.
        for task in tasks {
            let isOn: Bool = picked.contains(task.id)
            if isOn, !task.isForToday {
                TaskRules.pick(task, in: context)
            } else if !isOn, task.isForToday || task.isLeftOver {
                TaskRules.putOff(task, toTomorrow: false, in: context)
            }
        }
        let spot: String = place.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(spot, forKey: PlanDayFlow.placeKey)
        DayJournal.setIntention(intention(for: first))
        DayJournal.markPlanned()
        TaskRules.noteDay(in: context)
        Notifier.shared.refresh(in: context)
        Feedback.celebrate()
        withAnimation(.smooth(duration: 0.35)) { isDone = true }
    }

    private func ending(_ trial: DayPlan, first: ListItem?, now: Date) -> some View {
        let count: Int = trial.tasks.count
        var text: String = "היום נשאר פתוח. החלקים הקבועים שלו מחכים לכם."
        if count > 0 {
            text = count == 1 ? "מטלה אחת להיום." : "\(count) מטלות להיום."
            if let finish = trial.finish {
                text += " לפי הקצב שלכם, הסיום ב־\(ScheduleItem.clock(finish)) בערך."
            } else {
                text += " לא הכול נכנס, וזה בסדר לדעת את זה כבר עכשיו."
            }
        }
        let current: Int = ScheduleItem.minute(of: now)
        let startsNow: Bool = first != nil && (firstMinute ?? Int.max) <= current + 10
        var begin: (() -> Void)?
        if startsNow, let first {
            begin = {
                dismiss()
                Task { @MainActor in
                    // The cover leaves first; the player opens after it.
                    try? await Task.sleep(for: .seconds(0.5))
                    TaskRules.start(first)
                }
            }
        }
        return FlowEnding(symbol: "sun.max.fill", artwork: PlanDayFlow.morning, title: "היום שלכם מוכן", text: text,
                          extraTitle: startsNow ? "להתחיל עכשיו" : nil, extra: begin,
                          doneTitle: startsNow ? "אחר כך" : "יוצאים לדרך", done: { dismiss() })
    }
}

// MARK: - Closing the day

/// The evening sitting: what was done, a decision about each thing that was
/// not, a look at the next day, and one touch on how the day felt.
struct CloseDayFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" && !$0.removed },
           sort: \ListItem.createdAt, order: .reverse)
    private var tasks: [ListItem]
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }) private var schedule: [ScheduleItem]
    @Query(filter: #Predicate<Habit> { !$0.removed }, sort: \Habit.order) private var habits: [Habit]
    @State private var feed = CalendarFeed.shared

    @State private var step = Launch.flowStep
    @State private var mood: Int? = DayJournal.mood()
    @State private var stuck: ListItem?
    /// How many tasks waited for a decision when the sitting began.
    @State private var startCount: Int?

    private static let night = Artwork(0x4338CA, 0x1E1B4B)
    private static let stone = Artwork(0x57534E, 0x292524)

    private var doneToday: [ListItem] {
        tasks.filter { item in
            guard item.isDone, let date = item.doneAt else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }

    private var remaining: [ListItem] {
        DayPlan.ordered(tasks.filter { !$0.isDone && $0.isForToday })
    }

    var body: some View {
        let now: Date = .now
        let left: [ListItem] = remaining
        let next: Date = DayPlan.nextWorkDay(after: now)
        let coming: String = DayPlan.name(ofComing: next, now: now)
        ZStack {
            AmbientGround(artwork: step == 0 ? Theme.emerald : CloseDayFlow.night)
            FlowFrame(title: title(coming), subtitle: subtitle(left: left.count), step: step, steps: 3,
                      artwork: step == 0 ? Theme.emerald : CloseDayFlow.night,
                      mainTitle: step == 2 ? "סוגרים את היום" : (step == 0 ? "מה נשאר?" : "מבט על \(coming)"),
                      mainSymbol: step == 2 ? "moon.stars.fill" : "arrow.forward",
                      back: step > 0 ? { step -= 1 } : nil,
                      close: { dismiss() },
                      main: { advance(now: now) }) {
                switch step {
                case 0: donePage(now: now)
                case 1: leftPage(left, coming: coming)
                default: nextPage(next, coming: coming, now: now)
                }
            }
        }
        .arrives()
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            if startCount == nil { startCount = remaining.count }
        }
        .sheet(item: $stuck) { task in
            StuckSheet(task: task)
        }
    }

    private func title(_ coming: String) -> String {
        switch step {
        case 0: return "סוגרים את היום"
        case 1: return "מה נשאר"
        default: return coming == "מחר" ? "מחר" : coming
        }
    }

    private func subtitle(left: Int) -> String {
        switch step {
        case 0: return "קודם כול, מה כן נעשה"
        case 1:
            if left == 0 { return "הכול הוחלט" }
            return left == 1 ? "מטלה אחת מחכה להחלטה" : "\(left) מטלות מחכות להחלטה"
        default: return "כדי לקום ליום שכבר יש לו צורה"
        }
    }

    // MARK: What was done

    private func donePage(now: Date) -> some View {
        let done: [ListItem] = doneToday
        let minutes: Int = done.reduce(0) { $0 + DayJournal.estimate($1) }
        let kept: Int = habits.filter { $0.isDone(on: now) }.count
        let headline: String = done.isEmpty ? "גם זה יום" : (done.count == 1 ? "מטלה אחת נעשתה" : "\(done.count) מטלות נעשו")
        let text: String = done.isEmpty
            ? "לא נסגרה היום מטלה. זה קורה, וזה לא אומר דבר על מחר. נסדר את מה שנשאר, ונסגור."
            : "בערך \(NowStatus.duration(max((minutes / 5) * 5, 5))) של עשייה. זה מה שהיום הזה נתן."
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    OnColorBadge(text: "היום", symbol: "checkmark")
                    Text(headline)
                        .font(.system(size: 30, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 4)
                    Text(text)
                        .font(.system(size: 14, weight: .medium))
                        .opacity(0.92)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !done.isEmpty {
                    CountUp(value: Double(done.count), duration: 0.8) { "\(Int($0.rounded()))" }
                        .font(.system(size: 56, weight: .heavy))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .livingCard(done.isEmpty ? CloseDayFlow.stone : Theme.emerald, seed: 0.3,
                        watermark: done.isEmpty ? "leaf.fill" : "checkmark.seal.fill")
            .cascade(0)

            if !done.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(done.enumerated()), id: \.element.id) { index, task in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text(task.title)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 50)
                        .cascade(index + 1)
                        if task.id != done.last?.id {
                            Divider().padding(.leading, 34)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .cardSurface()
            }

            if !habits.isEmpty {
                HStack(spacing: 12) {
                    ProgressRing(share: Double(kept) / Double(max(habits.count, 1)), lineWidth: 5,
                                 track: Theme.chip, fill: Theme.accent)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(kept) מתוך \(habits.count) מקביעות היום")
                            .font(.system(size: 16, weight: .bold))
                        Text(kept == habits.count ? "יום מלא." : "מה שנשמר, נשמר. מחר יום חדש.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .cardSurface()
                .cascade(done.count + 1)
            }
        }
    }

    // MARK: What is left

    @ViewBuilder
    private func leftPage(_ left: [ListItem], coming: String) -> some View {
        if let task = left.first {
            VStack(alignment: .leading, spacing: 16) {
                taskCard(task)
                    .id(task.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 18)),
                                            removal: .opacity))
                Text("מה איתה?")
                    .font(.system(size: 20, weight: .heavy))
                    .padding(.horizontal, 4)
                VStack(spacing: 10) {
                    choice("ל" + coming, "היא תחכה שם, עם מקום משלה", symbol: "sunrise.fill", artwork: Theme.blue) {
                        TaskRules.putOff(task, toTomorrow: true, in: context)
                    }
                    choice("אחר כך", "חוזרת לרשימה, בלי יום", symbol: "tray.fill", artwork: Theme.violet) {
                        TaskRules.putOff(task, toTomorrow: false, in: context)
                    }
                    choice("בעצם נעשתה", "רק לא סומנה", symbol: "checkmark", artwork: Theme.emerald) {
                        _ = TaskRules.setDone(task, true, in: context)
                    }
                    choice("לוותר עליה", "בלב שלם. לא כל מטלה חייבת לקרות", symbol: "leaf.fill",
                           artwork: CloseDayFlow.stone) {
                        TaskRules.release(task, in: context)
                    }
                }
            }
            .animation(.smooth(duration: 0.3), value: task.id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 112, height: 112)
                    .background(Theme.emerald.gradient, in: Circle())
                    .shadow(color: Theme.emerald.end.opacity(0.35), radius: 18, y: 10)
                Text((startCount ?? 0) == 0 ? "לא נשאר דבר על היום" : "לכל מטלה יש עכשיו מקום")
                    .font(.system(size: 24, weight: .heavy))
                    .multilineTextAlignment(.center)
                Text("שום דבר לא נגרר למחר בלי שהחלטתם עליו.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .transition(.opacity)
        }
    }

    /// The task in question, large.
    private func taskCard(_ task: ListItem) -> some View {
        let times: String = task.pushed == 1 ? "נדחתה פעם אחת" : "נדחתה \(task.pushed) פעמים"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if task.minutes > 0 {
                    OnColorBadge(text: NowStatus.duration(task.minutes), symbol: "clock")
                }
                if task.priority > 0 {
                    OnColorBadge(text: "חשוב", symbol: "flag.fill")
                }
                if task.pushed > 0 {
                    OnColorBadge(text: times, symbol: "hourglass")
                }
            }
            Text(task.title)
                .font(.system(size: 28, weight: .heavy))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .padding(.top, 6)
            if task.pushed >= 2 {
                Button {
                    stuck = task
                } label: {
                    Label("היא נדחית שוב ושוב. מה תקוע?", systemImage: "questionmark.circle.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(.white.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(task.pushed >= 2 ? Theme.amber : CloseDayFlow.night, radius: 28, seed: 0.2,
                    watermark: "moon.stars.fill")
    }

    private func choice(_ name: String, _ text: String, symbol: String, artwork: Artwork,
                        action: @escaping () -> Void) -> some View {
        Button {
            Feedback.done()
            withAnimation(.smooth(duration: 0.3)) { action() }
        } label: {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: artwork, symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Color.primary)
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.pressable)
    }

    // MARK: The next day

    private func nextPage(_ next: Date, coming: String, now: Date) -> some View {
        let plan: DayPlan = DayPlan.make(day: next, tasks: tasks, schedule: schedule, events: feed.on(next), now: now)
        let date: String = next.formatted(Date.FormatStyle(locale: Ledger.hebrew).weekday(.wide).day().month(.wide))
        var headline: String = "יום פתוח"
        switch plan.load {
        case .over: headline = "כבר גדוש"
        case .light, .full:
            headline = plan.tasks.count == 1 ? "מטלה אחת מחכה" : "\(plan.tasks.count) מטלות מחכות"
        default: break
        }
        let shown: String = headline
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    OnColorBadge(text: date)
                    if let name = plan.kind.title {
                        // A day with a long name keeps its first part here.
                        ViewThatFits(in: .horizontal) {
                            OnColorBadge(text: name)
                            OnColorBadge(text: name.components(separatedBy: " · ").first ?? name)
                        }
                    }
                }
                Text(shown)
                    .font(.system(size: 32, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)
                Text(plan.sentence)
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
                DayMap(plan: plan, now: now, height: 26, isOnColor: true)
                    .padding(.top, 6)
                if let note = plan.closingNote {
                    Label(note, systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.95)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .livingCard(plan.load == .over ? Theme.amber : CloseDayFlow.night, seed: 0.6, watermark: "sunrise.fill")
            .cascade(0)

            if !plan.tasks.isEmpty {
                VStack(spacing: 0) {
                    ForEach(plan.tasks.prefix(6)) { planned in
                        HStack(spacing: 12) {
                            Image(systemName: "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(planned.task.title)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if let span = planned.span {
                                Text(ScheduleItem.clock(span.start))
                                    .font(.system(size: 13, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(minHeight: 48)
                        if planned.id != plan.tasks.prefix(6).last?.id {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .cardSurface()
                .cascade(1)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("איך היה היום?")
                    .font(.system(size: 20, weight: .heavy))
                HStack(spacing: 8) {
                    moodButton(1, "כבד", symbol: "cloud.rain.fill")
                    moodButton(2, "בסדר", symbol: "cloud.sun.fill")
                    moodButton(3, "טוב", symbol: "sun.max.fill")
                }
                Text("נגיעה אחת. עם הזמן האפליקציה תראה אילו ימים מרגישים לכם טוב, ולמה.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .cascade(2)
        }
    }

    private func moodButton(_ value: Int, _ name: String, symbol: String) -> some View {
        let isOn: Bool = mood == value
        return Button {
            Feedback.tap()
            withAnimation(.snappy) { mood = isOn ? nil : value }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                Text(name)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isOn ? AnyShapeStyle(CloseDayFlow.night.gradient) : AnyShapeStyle(Theme.chip),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Closing

    private func advance(now: Date) {
        Feedback.tap()
        guard step == 2 else {
            step += 1
            return
        }
        if let mood { DayJournal.setMood(mood) }
        DayJournal.markClosed()
        TaskRules.noteDay(in: context)
        Notifier.shared.refresh(in: context)
        let kind: JewishDay = JewishDay.of(now)
        var title: String = "היום נסגר"
        var text: String = "מה שנעשה, נעשה. מה שנשאר מחכה ביום שבחרתם לו."
        if kind.isEve {
            title = kind.next.greeting
            text = "השבוע נסגר. מה שנשאר מחכה ל" + DayPlan.name(ofComing: DayPlan.nextWorkDay(after: now), now: now) + "."
        }
        dismiss()
        Moments.shared.play("dayclosed", symbol: "moon.stars.fill", title: title, text: text,
                            artwork: CloseDayFlow.night, after: 0.45)
    }
}
