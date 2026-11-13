import SwiftData
import SwiftUI

/// Rules for tasks that several screens share.
@MainActor
enum TaskRules {
    /// Marks a task done or open again, with its reward, and creates the
    /// next round of a repeating task.
    static func setDone(_ item: ListItem, _ done: Bool, in context: ModelContext) {
        item.isDone = done
        item.doneAt = done ? .now : nil
        item.updatedAt = .now
        if item.kind == ListItem.task {
            Stats.addDone(done ? 1 : -1)
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
    }

    /// The first free window today that fits, starting from now. On Friday
    /// nothing is placed in the last hour before sunset.
    static func freeSlot(minutes: Int, items: [ScheduleItem], now: Date = .now) -> Int? {
        var start = ((ScheduleItem.minute(of: now) + 9) / 5) * 5
        var limit = 23 * 60 + 30
        if Calendar.current.component(.weekday, from: now) == 6, let sunset = Zmanim(day: now).sunset {
            limit = ScheduleItem.minute(of: sunset) - 60
        }
        for item in NowStatus.today(items, on: now) {
            if start + minutes <= item.startMinute { break }
            if item.endMinute > start { start = item.endMinute }
        }
        return start + minutes <= limit ? start : nil
    }
}

struct TasksView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" && !$0.removed },
           sort: \ListItem.createdAt, order: .reverse)
    private var items: [ListItem]

    @State private var draft = ""
    @State private var draftDay = 0
    @State private var draftImportant = false
    @State private var editing: ListItem?
    @State private var showsDone = false
    @State private var celebrates = false
    @FocusState private var isTyping: Bool

    private var open: [ListItem] { items.filter { !$0.isDone } }

    private var today: [ListItem] {
        open.filter(\.isForToday).sorted { rank($0) < rank($1) }
    }

    private var later: [ListItem] {
        open.filter { !$0.isForToday && $0.due != nil }.sorted { ($0.due ?? .now) < ($1.due ?? .now) }
    }

    private var someday: [ListItem] {
        open.filter { !$0.isForToday && $0.due == nil }.sorted { rank($0) < rank($1) }
    }

    private var doneToday: [ListItem] {
        items.filter { item in
            guard item.isDone, let date = item.doneAt else { return false }
            return Calendar.current.isDateInToday(date)
        }
    }

    private var doneEarlier: [ListItem] {
        Array(items.filter { $0.isDone && !doneToday.map(\.id).contains($0.id) }.prefix(20))
    }

    private func rank(_ item: ListItem) -> Int {
        (item.isOverdue ? 0 : 2) - item.priority
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TasksHero(doneToday: doneToday.count, openToday: today.count,
                              minutesLeft: today.reduce(0) { $0 + $1.minutes })
                    addBar

                    if open.isEmpty && doneToday.isEmpty {
                        emptyState
                    }

                    if !today.isEmpty || !doneToday.isEmpty {
                        section("היום", today, hint: today.count > 5
                                ? "הרבה ליום אחד. מה שלושת הדברים שבאמת חייבים לקרות היום?" : nil)
                    } else if !open.isEmpty {
                        pickHint
                    }
                    if !later.isEmpty { section("בקרוב", later) }
                    if !someday.isEmpty { section("מתישהו", someday) }

                    if !doneToday.isEmpty || !doneEarlier.isEmpty {
                        doneSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.ground)
            .navigationTitle("מטלות")
            .refreshable { await SharedSync.shared.run(in: context) }
            .overlay {
                if celebrates { ConfettiView().allowsHitTesting(false).ignoresSafeArea() }
            }
            .sheet(item: $editing) { item in
                TaskEditor(item: item)
            }
            .task {
                guard Launch.screen == "task" else { return }
                try? await Task.sleep(for: .seconds(1))
                editing = items.first
            }
        }
    }

    // MARK: Add

    private var addBar: some View {
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
            if isTyping || !draft.isEmpty {
                HStack(spacing: 8) {
                    dayChip("היום", 0)
                    dayChip("מחר", 1)
                    dayChip("בלי תאריך", -1)
                    Spacer(minLength: 0)
                    Button {
                        draftImportant.toggle()
                    } label: {
                        Image(systemName: draftImportant ? "flag.fill" : "flag")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 40, height: 34)
                            .foregroundStyle(draftImportant ? Color.white : Color.primary)
                            .background(draftImportant ? Color(hex: 0xEA580C) : Theme.chip, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("חשוב")
                    .accessibilityAddTraits(draftImportant ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .cardSurface()
        .animation(.snappy, value: isTyping)
    }

    private func dayChip(_ title: String, _ value: Int) -> some View {
        let isOn = draftDay == value
        return Button {
            draftDay = value
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(isOn ? Theme.ground : Color.primary)
                .background(isOn ? Color.primary : Theme.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let item = ListItem(kind: ListItem.task, title: text)
        if draftDay >= 0 {
            let start = Calendar.current.startOfDay(for: .now)
            item.due = Calendar.current.date(byAdding: .day, value: draftDay, to: start)
        }
        item.priority = draftImportant ? 1 : 0
        withAnimation(.snappy) { context.insert(item) }
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        Feedback.added()
        draft = ""
        draftImportant = false
        isTyping = true
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
                Text("מה שלושת הדברים של היום?")
                    .font(.system(size: 16, weight: .bold))
                Text("הקישו על השמש ליד מטלה כדי לבחור אותה להיום. מעט ומדויק עובד טוב יותר מרשימה ארוכה.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .cardSurface()
    }

    private func section(_ title: String, _ list: [ListItem], hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                if !list.isEmpty {
                    Text("\(list.count)")
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            if let hint {
                Text(hint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.amberInk)
                    .padding(.horizontal, 4)
            }
            if list.isEmpty {
                Text("סיימתם את כל מה שתוכנן להיום.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { item in
                        TaskRow(item: item, onToggle: { toggle(item) }, onOpen: { editing = item },
                                onToday: { pickForToday(item) })
                        if item.id != list.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .cardSurface()
            }
        }
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
            .buttonStyle(.plain)

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

    private func toggle(_ item: ListItem) {
        let finishing = !item.isDone
        let wasLastToday = finishing && item.isForToday && today.count == 1
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
            TaskRules.setDone(item, finishing, in: context)
        }
        if wasLastToday {
            Feedback.celebrate()
            celebrates = true
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                celebrates = false
            }
        } else if finishing {
            Feedback.done()
        } else {
            Feedback.tap()
        }
    }

    private func pickForToday(_ item: ListItem) {
        withAnimation(.snappy) {
            item.todayDay = DayKey.of()
            item.updatedAt = .now
        }
        try? context.save()
        SharedSync.shared.changed(in: context)
        Feedback.tap()
    }
}

/// The colorful summary of today's tasks.
struct TasksHero: View {
    let doneToday: Int
    let openToday: Int
    let minutesLeft: Int

    private var total: Int { doneToday + openToday }
    private var share: Double { total > 0 ? Double(doneToday) / Double(total) : 0 }

    private var headline: String {
        if total == 0 { return "מה חשוב היום?" }
        if openToday == 0 { return "היום הושלם" }
        if openToday == 1 { return "עוד אחת וסיימתם" }
        return "\(doneToday) מתוך \(total) להיום"
    }

    private var line: String {
        let streak = Stats.streak
        if total == 0 { return "בחרו עד שלוש מטלות, והתחילו מהקטנה ביותר." }
        if openToday == 0 { return streak > 1 ? "\(streak) ימים ברצף של עשייה. ממשיכים מחר." : "יום טוב. מחר ממשיכים." }
        if doneToday == 0 { return "ההתחלה היא החלק הקשה. שתי דקות ראשונות, וזה כבר זז." }
        if minutesLeft > 0 { return "נשארו בערך \(NowStatus.duration(minutesLeft)) של עבודה." }
        return "אתם כבר בתנועה. ממשיכים."
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("היום")
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(0.9)
                    if Stats.streak > 1 {
                        Label("\(Stats.streak)", systemImage: "flame.fill")
                            .font(.system(size: 13, weight: .heavy))
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                }
                Text(headline)
                    .font(.system(size: 30, weight: .heavy))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(line)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.92)
            }
            Spacer(minLength: 0)
            ProgressRing(share: share, lineWidth: 10)
                .frame(width: 84, height: 84)
                .overlay {
                    if total > 0 && openToday == 0 {
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .heavy))
                    } else {
                        Text("\(doneToday)")
                            .font(.system(size: 28, weight: .heavy))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.blue.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(hex: 0x1E3A8A).opacity(0.4), radius: 20, y: 12)
        .accessibilityElement(children: .combine)
    }
}

struct TaskRow: View {
    let item: ListItem
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onToday: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 25, weight: item.priority > 0 ? .bold : .regular))
                    .foregroundStyle(item.isDone ? Theme.accent
                                     : (item.priority > 0 ? Color(hex: 0xEA580C) : Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 42, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "החזרה לפתוחות" : "סימון כבוצע")

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
            .buttonStyle(.plain)

            if let onToday, !item.isDone, !item.isForToday {
                Button(action: onToday) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.amberInk)
                        .frame(width: 40, height: 40)
                        .background(Theme.amberGround, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("להיום")
            }
        }
        .frame(minHeight: 54)
    }

    @ViewBuilder
    private var meta: some View {
        let hasMeta = item.due != nil || item.minutes > 0 || !item.repeatRule.isEmpty
            || !(item.note ?? "").isEmpty || item.priority > 0
        if hasMeta && !item.isDone {
            HStack(spacing: 8) {
                if item.priority > 0 {
                    Image(systemName: "flag.fill").foregroundStyle(Color(hex: 0xEA580C))
                }
                if let text = item.dueText {
                    Text(text).foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                }
                if item.minutes > 0 {
                    Label(NowStatus.duration(item.minutes), systemImage: "clock")
                }
                if !item.repeatRule.isEmpty {
                    Image(systemName: "repeat")
                }
                if !(item.note ?? "").isEmpty {
                    Image(systemName: "text.alignright")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
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
                    Text("מטלה שיש לה שעה ומקום קבועים מתבצעת בסיכוי כפול. ורובנו מעריכים זמן בחסר, אז כדאי להוסיף רבע להערכה.")
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
            .onAppear {
                title = item.title
                note = item.note ?? ""
                hasDue = item.due != nil
                due = item.due ?? .now
                isToday = item.todayDay == DayKey.of()
                isImportant = item.priority > 0
                minutes = item.minutes
                repeatRule = item.repeatRule
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
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
