import SwiftData
import SwiftUI

/// Rules for tasks that several screens share.
@MainActor
enum TaskRules {
    /// Marks a task done or open again and creates the next round of a
    /// repeating task. When this was the last thing planned for today, the
    /// day's celebration plays; returns true when it did.
    @discardableResult
    static func setDone(_ item: ListItem, _ done: Bool, in context: ModelContext) -> Bool {
        let wasForToday: Bool = item.kind == ListItem.task && item.isForToday
        item.isDone = done
        item.doneAt = done ? .now : nil
        item.updatedAt = .now
        if item.kind == ListItem.task {
            Stats.addDone(done ? 1 : -1)
        }
        if done, item.kind == ListItem.task {
            // A task that was started with the timer teaches how long such
            // tasks really take.
            if FocusTimer.shared.isActive, FocusTimer.shared.taskID == item.id { FocusTimer.shared.stop() }
            if let minutes = FocusTimer.takeMinutes(of: item.id) {
                DayJournal.addSample(estimate: item.minutes, actual: minutes)
            }
        }
        if done, !item.repeatRule.isEmpty {
            let step = item.repeatRule == "weekly" ? 7 : 1
            let base = max(item.due ?? .now, Calendar.current.startOfDay(for: .now))
            let next = ListItem(kind: item.kind, title: item.title)
            next.due = Calendar.current.date(byAdding: .day, value: step, to: base)
            next.priority = item.priority
            next.minutes = item.minutes
            next.note = item.note
            next.repeatRule = item.repeatRule
            item.repeatRule = ""
            context.insert(next)
        }
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        if item.kind == ListItem.task { noteDay(in: context) }

        guard done, wasForToday else { return false }
        let descriptor = FetchDescriptor<ListItem>(
            predicate: #Predicate<ListItem> { $0.kind == "task" && !$0.removed && !$0.isDone })
        let open: [ListItem] = (try? context.fetch(descriptor)) ?? []
        let id: String = item.id
        if open.contains(where: { $0.id != id && $0.isForToday }) { return false }
        let streak: Int = Stats.streak
        return Moments.shared.play(
            "tasks", symbol: "checkmark", title: "היום הושלם",
            text: streak > 1 ? "כל מה שתוכנן להיום נעשה. \(streak) ימים ברצף." : "כל מה שתוכנן להיום נעשה.",
            artwork: Theme.blue)
    }

    /// The first free window today that fits, starting from now. Before
    /// Shabbat or a festival nothing is placed in the last hour before the
    /// candles, and on the day itself nothing at all.
    static func freeSlot(minutes: Int, items: [ScheduleItem], now: Date = .now) -> Int? {
        let kind: JewishDay = JewishDay.of(now)
        guard !kind.isRest else { return nil }
        var start = ((ScheduleItem.minute(of: now) + 9) / 5) * 5
        let limit: Int = kind.hasCandles ? DayPlan.closing(day: now, kind: kind) : 23 * 60 + 30
        for item in NowStatus.today(items, on: now) {
            let from: Int = item.start(on: now)
            let to: Int = item.end(on: now)
            if start + minutes <= from { break }
            if to > start { start = to }
        }
        return start + minutes <= limit ? start : nil
    }
}

struct TasksView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" && !$0.removed },
           sort: \ListItem.createdAt, order: .reverse)
    private var items: [ListItem]
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }) private var schedule: [ScheduleItem]

    @State private var router = AppRouter.shared
    @State private var feed = CalendarFeed.shared
    @State private var editing: ListItem?
    @State private var stuck: ListItem?
    @State private var showsDone = false
    /// Counts up when the day's journal changed, so the screen reads it again.
    @State private var turn = 0

    private var open: [ListItem] { items.filter { !$0.isDone } }

    /// Chosen for a day that has passed, and not yet asked about.
    private var leftovers: [ListItem] {
        open.filter { $0.isLeftOver && !$0.isForToday }
    }

    private var later: [ListItem] {
        let list: [ListItem] = open.filter { !$0.isForToday && !$0.isLeftOver && $0.due != nil }
        return list.sorted { ($0.due ?? .now) < ($1.due ?? .now) }
    }

    private var someday: [ListItem] {
        let list: [ListItem] = open.filter { !$0.isForToday && !$0.isLeftOver && $0.due == nil }
        return list.sorted { $0.priority > $1.priority }
    }

    private var doneToday: [ListItem] {
        items.filter { item in
            guard item.isDone, let date = item.doneAt else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }

    private var doneEarlier: [ListItem] {
        let today: Set<String> = Set(doneToday.map(\.id))
        return Array(items.filter { $0.isDone && !today.contains($0.id) }.prefix(20))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("מדור", selection: $router.tasksSection) {
                        ForEach(TasksSection.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Group {
                        if router.tasksSection == .shopping {
                            ShoppingBoard()
                        } else {
                            // The day's room shrinks as the clock moves.
                            TimelineView(.everyMinute) { timeline in
                                board(now: timeline.date)
                            }
                        }
                    }
                    .arrives()
                    .id(router.tasksSection)
                    .transition(.sectionSwap)
                }
                .animation(.section, value: router.tasksSection)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background {
                AmbientGround(artwork: router.tasksSection == .shopping ? Theme.green : Theme.blue)
            }
            .navigationTitle(router.tasksSection == .shopping ? "קניות" : "מטלות")
            .toolbar {
                if router.tasksSection == .tasks {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("בונים את היום", systemImage: "sun.max.fill") { router.isPlanningDay = true }
                            Button("סוגרים את היום", systemImage: "moon.stars.fill") { router.isClosingDay = true }
                        } label: {
                            Image(systemName: "sun.and.horizon.fill")
                        }
                        .accessibilityLabel("תכנון היום וסגירתו")
                    }
                }
            }
            .refreshable { await SharedSync.shared.run(in: context) }
            .sheet(item: $editing) { item in
                TaskEditor(item: item)
            }
            .sheet(item: $stuck) { item in
                StuckSheet(task: item)
            }
            .onChange(of: router.isPlanningDay) { _, _ in turn += 1 }
            .onChange(of: router.isClosingDay) { _, _ in turn += 1 }
            .task {
                guard Launch.screen == "task" || Launch.screen == "task-stuck" else { return }
                try? await Task.sleep(for: .seconds(1))
                if Launch.screen == "task" {
                    editing = items.first
                } else {
                    stuck = open.first(where: { $0.isStuck }) ?? open.first
                }
            }
        }
    }

    // MARK: The day

    @ViewBuilder
    private func board(now: Date) -> some View {
        let _ = turn
        let plan: DayPlan = DayPlan.make(day: now, tasks: items, schedule: schedule, events: feed.on(now), now: now)
        let left: [ListItem] = leftovers
        let finished: [ListItem] = doneToday
        let minute: Int = ScheduleItem.minute(of: now)
        let canPlan: Bool = plan.offersPlanning(minute: minute, hasOpen: !open.isEmpty)
        let canClose: Bool = plan.offersClosing(minute: minute, hasDone: !finished.isEmpty)
        let planDay: (() -> Void)? = canPlan ? { router.isPlanningDay = true } : nil
        let closeDay: (() -> Void)? = canClose ? { router.isClosingDay = true } : nil
        VStack(alignment: .leading, spacing: 18) {
            DayRingHero(plan: plan, doneCount: finished.count, now: now,
                        start: { begin($0) }, planDay: planDay, closeDay: closeDay)
                .cascade(0)

            if plan.load == .over, !plan.tasks.isEmpty {
                overload(plan)
                    .transition(.sectionSwap)
            }

            TaskAddBar(plan: plan)
                .cascade(1)

            if open.isEmpty && finished.isEmpty {
                emptyState
            }

            if !left.isEmpty {
                LeftoverCard(tasks: left, toToday: { pick($0) }, later: { move($0, toTomorrow: false) },
                             untangle: { stuck = $0 })
                    .transition(.sectionSwap)
            }

            if !plan.tasks.isEmpty || !finished.isEmpty {
                todaySection(plan)
            } else if !open.isEmpty && left.isEmpty {
                pickHint
            }
            if !later.isEmpty { section("בקרוב", later) }
            if !someday.isEmpty { section("מתישהו", someday) }

            if !finished.isEmpty || !doneEarlier.isEmpty {
                doneSection
            }
        }
    }

    private func overload(_ plan: DayPlan) -> some View {
        // A day that ends in candle lighting cannot be stretched.
        let canStretch: Bool = !plan.kind.hasCandles && !DayJournal.acceptsLateToday && plan.closing < 23 * 60 + 30
        let stretch: (() -> Void)? = canStretch ? { acceptLate() } : nil
        return OverloadCard(plan: plan, moveToTomorrow: { move($0, toTomorrow: true) },
                            trim: { task, minutes in trim(task, to: minutes) }, acceptLate: stretch)
    }

    private func acceptLate() {
        DayJournal.acceptLate()
        withAnimation(.section) { turn += 1 }
        Feedback.tap()
    }

    private func trim(_ task: ListItem, to minutes: Int) {
        withAnimation(.section) { TaskRules.trim(task, to: minutes, in: context) }
        Feedback.tap()
    }

    // MARK: Lists

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("הראש נקי")
                .font(.system(size: 20, weight: .heavy))
            Text("כתבו למעלה את הדבר הראשון שעולה לכם. לפרוק מהראש לרשימה זה כבר חצי מהעבודה.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var pickHint: some View {
        HStack(spacing: 12) {
            ArtworkIcon(artwork: Theme.amber, symbol: "sun.max.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text("מה נכנס היום?")
                    .font(.system(size: 16, weight: .bold))
                Text("הקישו על השמש ליד מטלה כדי לבחור אותה להיום. הטבעת למעלה תראה כמה מקום נשאר.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .cardSurface()
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 22, weight: .heavy))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Today's tasks in the order the day will take them, each with the
    /// place the day has for it.
    private func todaySection(_ plan: DayPlan) -> some View {
        let list: [PlannedTask] = plan.tasks
        let showsRoom: Bool = plan.load != .rest
        return VStack(alignment: .leading, spacing: 8) {
            header("היום", count: list.count)
            if list.isEmpty {
                Text("סיימתם את כל מה שתוכנן להיום.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { planned in
                        row(planned.task, span: planned.span, isOut: showsRoom && planned.span == nil)
                        if planned.id != list.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .cardSurface()
            }
        }
    }

    private func section(_ title: String, _ list: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(title, count: list.count)
            VStack(spacing: 0) {
                ForEach(list) { item in
                    row(item)
                    if item.id != list.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .padding(.horizontal, 12)
            .cardSurface()
        }
    }

    private func row(_ item: ListItem, span: DaySpan? = nil, isOut: Bool = false) -> some View {
        let actions = TaskActions(
            start: { begin(item) },
            tomorrow: { move(item, toTomorrow: true) },
            later: { move(item, toTomorrow: false) },
            flag: { flag(item) },
            stuck: { stuck = item },
            delete: { remove(item) })
        return TaskRow(item: item, span: span, isOut: isOut, onToggle: { toggle(item) },
                       onOpen: { editing = item }, onToday: { pick(item) }, actions: actions)
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { showsDone.toggle() }
            } label: {
                HStack {
                    Text("הושלמו")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color.primary)
                    Text("\(doneToday.count) היום")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: showsDone ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            if showsDone {
                let list = doneToday + doneEarlier
                VStack(spacing: 0) {
                    ForEach(list) { item in
                        TaskRow(item: item, onToggle: { toggle(item) }, onOpen: { editing = item }, onToday: nil)
                        if item.id != list.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .cardSurface()

                Button("ניקוי כל מה שהושלם", role: .destructive) {
                    for item in items where item.isDone {
                        item.removed = true
                        item.updatedAt = .now
                    }
                    try? context.save()
                    SharedSync.shared.changed(in: context)
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: Actions

    /// The check button has already given the tap and the chime.
    private func toggle(_ item: ListItem) {
        let finishing = !item.isDone
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
            _ = TaskRules.setDone(item, finishing, in: context)
        }
    }

    private func pick(_ item: ListItem) {
        withAnimation(.snappy) { TaskRules.pick(item, in: context) }
        Notifier.shared.refresh(in: context)
        Feedback.tap()
    }

    /// Starting a task makes it one of today's.
    private func begin(_ item: ListItem) {
        if !item.isForToday { TaskRules.pick(item, in: context) }
        TaskRules.start(item)
    }

    private func move(_ item: ListItem, toTomorrow: Bool) {
        let before: Int = item.pushed
        withAnimation(.section) { TaskRules.putOff(item, toTomorrow: toTomorrow, in: context) }
        Feedback.tap()
        // The third time a task is put off, the app asks what is stuck.
        if before < 3, item.pushed >= 3 { stuck = item }
    }

    private func flag(_ item: ListItem) {
        withAnimation(.snappy) {
            item.priority = item.priority > 0 ? 0 : 1
            item.updatedAt = .now
        }
        try? context.save()
        SharedSync.shared.changed(in: context)
        Feedback.tap()
    }

    private func remove(_ item: ListItem) {
        withAnimation(.section) { TaskRules.release(item, in: context) }
        Feedback.tap()
    }
}

/// The line where a new task is written. It understands a day, a length and
/// an exclamation mark at the end of the line, and offers the same three as
/// touches. A new task goes to today only while today has room for it.
struct TaskAddBar: View {
    let plan: DayPlan
    @Environment(\.modelContext) private var context
    @State private var draft = ""
    /// Chosen by touch, in days from today; -1 is no day.
    @State private var day: Int?
    @State private var minutes: Int?
    @State private var isImportant = false
    @FocusState private var isTyping: Bool

    private static let lengths = [5, 10, 15, 20, 30, 45, 60, 90, 120]

    /// Days from today to the next working day.
    private var ahead: Int {
        let calendar = Calendar.current
        let next: Date = DayPlan.nextWorkDay(after: plan.day)
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: plan.day),
                                       to: calendar.startOfDay(for: next)).day ?? 1
    }

    /// Whether today can still take one more task of the usual length.
    private var hasRoomToday: Bool {
        switch plan.load {
        case .rest, .closed, .over: return false
        case .empty, .light, .full: return plan.roomMinutes - plan.plannedMinutes >= DayJournal.typicalMinutes
        }
    }

    var body: some View {
        let parsed: TaskParser.Result = TaskParser.parse(draft)
        let usual: Int = hasRoomToday ? 0 : ahead
        let chosenDay: Int = parsed.day ?? day ?? usual
        let chosenMinutes: Int = parsed.minutes ?? minutes ?? 0
        let flagged: Bool = parsed.isImportant || isImportant
        let isOpen: Bool = isTyping || !draft.isEmpty
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent)
                TextField("מה צריך לעשות?", text: $draft)
                    .font(.system(size: 17))
                    .focused($isTyping)
                    .submitLabel(.done)
                    .onSubmit { add() }
            }
            if isOpen {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        dayChip("היום", 0, chosen: chosenDay)
                        dayChip(DayPlan.name(ofComing: DayPlan.nextWorkDay(after: plan.day), now: plan.day), ahead,
                                chosen: chosenDay)
                        if chosenDay > 0, chosenDay != ahead {
                            dayChip(TaskAddBar.name(of: chosenDay, from: plan.day), chosenDay, chosen: chosenDay)
                        }
                        dayChip("בלי תאריך", -1, chosen: chosenDay)
                        lengthMenu(chosenMinutes)
                        Button {
                            isImportant.toggle()
                        } label: {
                            Image(systemName: flagged ? "flag.fill" : "flag")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 40, height: 34)
                                .foregroundStyle(flagged ? Color.white : Color.primary)
                                .background(flagged ? Color(hex: 0xEA580C) : Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("חשוב")
                        .accessibilityAddTraits(flagged ? .isSelected : [])
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                Text(hint(usual: usual, chosen: chosenDay))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .cardSurface()
        .animation(.snappy, value: isOpen)
        .animation(.snappy, value: chosenDay)
    }

    /// One line under the chips: why the task is not going to today, or
    /// what can be written in the line itself.
    private func hint(usual: Int, chosen: Int) -> String {
        if usual > 0, chosen == usual, day == nil {
            let name: String = DayPlan.name(ofComing: DayPlan.nextWorkDay(after: plan.day), now: plan.day)
            switch plan.load {
            case .rest: return "המטלה תיכנס ל\(name)."
            case .closed: return "יום העבודה נסגר, ולכן היא תיכנס ל\(name). אפשר לשנות."
            default: return "היום כבר מלא, ולכן היא תיכנס ל\(name). אפשר לשנות."
            }
        }
        return "אפשר לכתוב הכול בשורה אחת: להתקשר לביטוח מחר 20 דק׳"
    }

    private static func name(of days: Int, from day: Date) -> String {
        let date: Date = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
        return days == 2 ? "מחרתיים" : HebrewDate.weekday(date)
    }

    private func dayChip(_ title: String, _ value: Int, chosen: Int) -> some View {
        let isOn: Bool = chosen == value
        return Button {
            day = value
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(isOn ? Theme.ground : Color.primary)
                .background(isOn ? Color.primary : Theme.chip, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func lengthMenu(_ chosen: Int) -> some View {
        Menu {
            Button("לא הוערך") { minutes = 0 }
            ForEach(TaskAddBar.lengths, id: \.self) { value in
                Button(NowStatus.duration(value)) { minutes = value }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 13, weight: .bold))
                Text(chosen > 0 ? NowStatus.duration(chosen) : "כמה זמן?")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .foregroundStyle(chosen > 0 ? Theme.ground : Color.primary)
            .background(chosen > 0 ? Color.primary : Theme.chip, in: Capsule())
        }
    }

    private func add() {
        let text: String = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        var parsed: TaskParser.Result = TaskParser.parse(text)
        // A line that is all instructions is taken as a name after all.
        if parsed.title.isEmpty { parsed = TaskParser.Result(title: text) }
        let item = ListItem(kind: ListItem.task, title: parsed.title)
        let when: Int = parsed.day ?? day ?? (hasRoomToday ? 0 : ahead)
        if when >= 0 {
            let start: Date = Calendar.current.startOfDay(for: .now)
            item.due = Calendar.current.date(byAdding: .day, value: when, to: start)
        }
        item.priority = parsed.isImportant || isImportant ? 1 : 0
        item.minutes = parsed.minutes ?? minutes ?? 0
        withAnimation(.snappy) { context.insert(item) }
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        TaskRules.noteDay(in: context)
        Feedback.added()
        draft = ""
        day = nil
        minutes = nil
        isImportant = false
        isTyping = true
    }
}

struct TaskRow: View {
    let item: ListItem
    /// Where today has room for it, for one of today's tasks.
    var span: DaySpan? = nil
    /// One of today's tasks that the day has no room left for.
    var isOut = false
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onToday: (() -> Void)?
    var actions: TaskActions? = nil

    var body: some View {
        HStack(spacing: 4) {
            CheckButton(isDone: item.isDone, isImportant: item.priority > 0, action: onToggle)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 16, weight: item.isDone ? .regular : .semibold))
                        .strikethrough(item.isDone)
                        .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    meta
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            trailing
        }
        .frame(minHeight: 54)
        .contextMenu { menu }
    }

    /// Today's tasks can be started; the others can be chosen for today.
    @ViewBuilder
    private var trailing: some View {
        if !item.isDone {
            if item.isForToday, let actions {
                Button(action: actions.start) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40, height: 40)
                        .background(Theme.chip, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("להתחיל עכשיו")
            } else if let onToday, !item.isForToday {
                Button(action: onToday) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.amberInk)
                        .frame(width: 40, height: 40)
                        .background(Theme.amberGround, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("להיום")
            }
        }
    }

    @ViewBuilder
    private var menu: some View {
        if let actions, !item.isDone {
            let coming: String = "ל" + DayPlan.name(ofComing: DayPlan.nextWorkDay())
            Button("להתחיל עכשיו", systemImage: "play.fill", action: actions.start)
            if item.isForToday {
                Button(coming, systemImage: "sunrise", action: actions.tomorrow)
                Button("לא היום", systemImage: "tray.and.arrow.down", action: actions.later)
            } else {
                if let onToday {
                    Button("להיום", systemImage: "sun.max", action: onToday)
                }
                Button(coming, systemImage: "sunrise", action: actions.tomorrow)
            }
            Button(item.priority > 0 ? "להוריד את הדגל" : "חשוב", systemImage: item.priority > 0 ? "flag.slash" : "flag",
                   action: actions.flag)
            if item.pushed >= 2 {
                Button("מה תקוע?", systemImage: "hourglass", action: actions.stuck)
            }
            Button("עריכה", systemImage: "pencil", action: onOpen)
            Divider()
            Button("מחיקה", systemImage: "trash", role: .destructive, action: actions.delete)
        }
    }

    /// For example "10:30–11:15".
    static func range(_ span: DaySpan) -> String {
        "\(ScheduleItem.clock(span.start))–\(ScheduleItem.clock(span.end))"
    }

    @ViewBuilder
    private var meta: some View {
        if !item.isDone {
            let note: String = item.note ?? ""
            let due: String? = item.dueText
            // A task with a place in today needs no "today" next to it.
            let showsDue: Bool = due != nil && !(due == "היום" && (span != nil || isOut))
            let hasMeta: Bool = span != nil || isOut || showsDue || item.minutes > 0 || item.priority > 0
                || item.isStuck || !item.repeatRule.isEmpty || !note.isEmpty
            if hasMeta {
                HStack(spacing: 8) {
                    if item.priority > 0 {
                        Image(systemName: "flag.fill").foregroundStyle(Color(hex: 0xEA580C))
                    }
                    if let span {
                        Label(TaskRow.range(span), systemImage: "clock")
                            .foregroundStyle(Theme.accent)
                    } else if isOut {
                        Text("אין לה מקום היום").foregroundStyle(Theme.amberInk)
                    }
                    if showsDue, let due {
                        // A day that has passed is said calmly, in amber.
                        Text(due).foregroundStyle(item.isOverdue ? Theme.amberInk : Color.secondary)
                    }
                    if item.minutes > 0, span == nil {
                        Label(NowStatus.duration(item.minutes), systemImage: "clock")
                    }
                    if item.isStuck {
                        Label("נדחתה \(item.pushed) פעמים", systemImage: "hourglass")
                            .foregroundStyle(Theme.amberInk)
                    }
                    if !item.repeatRule.isEmpty {
                        Image(systemName: "repeat")
                    }
                    if !note.isEmpty {
                        Image(systemName: "text.alignright")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
            }
        }
    }
}

/// Everything about one task.
struct TaskEditor: View {
    let item: ListItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }) private var schedule: [ScheduleItem]
    @State private var title = ""
    @State private var note = ""
    @State private var hasDue = false
    @State private var due = Date.now
    @State private var isToday = false
    @State private var isImportant = false
    @State private var minutes = 0
    @State private var repeatRule = ""
    @State private var slotMessage: String?
    @State private var untangling = false

    private let lengths = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("מה צריך לעשות?", text: $title, axis: .vertical)
                        .font(.system(size: 18, weight: .semibold))
                    TextField("הערות, פרטים, קישור", text: $note, axis: .vertical)
                        .lineLimit(1...5)
                }

                Section {
                    Toggle(isOn: $isToday) {
                        Label("אחד מהדברים של היום", systemImage: "sun.max.fill")
                    }
                    Toggle(isOn: $isImportant) {
                        Label("חשוב", systemImage: "flag.fill")
                    }
                    Toggle(isOn: $hasDue.animation()) {
                        Label("תאריך יעד", systemImage: "calendar")
                    }
                    if hasDue {
                        DatePicker("עד מתי", selection: $due, displayedComponents: .date)
                    }
                    Picker(selection: $repeatRule) {
                        Text("לא חוזרת").tag("")
                        Text("כל יום").tag("daily")
                        Text("כל שבוע").tag("weekly")
                    } label: {
                        Label("חזרה", systemImage: "repeat")
                    }
                }

                Section {
                    Picker(selection: $minutes) {
                        ForEach(lengths, id: \.self) { value in
                            Text(value == 0 ? "לא הוערך" : NowStatus.duration(value)).tag(value)
                        }
                    } label: {
                        Label("כמה זמן זה ייקח", systemImage: "clock")
                    }
                    if let likely = DayJournal.likely(for: minutes) {
                        // What their own finished tasks have shown.
                        Label("מטלות כאלה לוקחות לכם בדרך כלל כ־\(NowStatus.duration(likely)).",
                              systemImage: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.amberInk)
                    }
                    Button {
                        slot()
                    } label: {
                        Label("שיבוץ בחלון הפנוי הבא היום", systemImage: "calendar.badge.plus")
                    }
                    if let slotMessage {
                        Text(slotMessage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("מתי בדיוק?")
                } footer: {
                    Text("מטלה שיש לה שעה ומקום קבועים מתבצעת בסיכוי כפול. רובנו מעריכים זמן בחסר, ולכן כשהאפליקציה בודקת מה נכנס ביום היא מוסיפה מרווח בעצמה.")
                }

                if item.pushed >= 2, !item.isDone {
                    Section {
                        Button {
                            untangling = true
                        } label: {
                            Label("נדחתה \(item.pushed) פעמים. מה תקוע?", systemImage: "hourglass")
                        }
                        .foregroundStyle(Theme.amberInk)
                    }
                }

                Section {
                    Button("מחיקת המטלה", role: .destructive) {
                        item.removed = true
                        item.updatedAt = .now
                        try? context.save()
                        SharedSync.shared.changed(in: context)
                        dismiss()
                    }
                }
            }
            .navigationTitle("מטלה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") {
                        apply()
                        dismiss()
                    }
                }
            }
            .onAppear { load() }
            .sheet(isPresented: $untangling, onDismiss: {
                // The task may have been let go, shortened or taken apart.
                if item.removed { dismiss() } else { load() }
            }) {
                StuckSheet(task: item)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func load() {
        title = item.title
        note = item.note ?? ""
        hasDue = item.due != nil
        due = item.due ?? .now
        isToday = item.todayDay == DayKey.of()
        isImportant = item.priority > 0
        minutes = item.minutes
        repeatRule = item.repeatRule
    }

    private func apply() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { item.title = name }
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = text.isEmpty ? nil : text
        item.due = hasDue ? Calendar.current.startOfDay(for: due) : nil
        item.todayDay = isToday ? DayKey.of() : ""
        item.priority = isImportant ? 1 : 0
        item.minutes = minutes
        item.repeatRule = repeatRule
        item.updatedAt = .now
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
    }

    private func slot() {
        let length = minutes > 0 ? minutes : 30
        guard let start = TaskRules.freeSlot(minutes: length, items: schedule) else {
            slotMessage = "לא נשאר היום חלון פנוי של \(NowStatus.duration(length))."
            return
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = ScheduleItem(title: name.isEmpty ? item.title : name, startMinute: start,
                                 durationMinutes: length, weekdays: 0, symbol: "checklist", palette: 3)
        block.onlyDay = DayKey.of()
        context.insert(block)
        isToday = true
        apply()
        slotMessage = "שובץ להיום בשעה \(ScheduleItem.clock(start))."
        Feedback.added()
    }
}
