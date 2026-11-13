import SwiftData
import SwiftUI

/// The steadiness of the measured practices as one small number.
struct ConsistencyChip: View {
    let share: Double
    var tint: Color = Theme.accent

    var body: some View {
        let text: String = share.formatted(.percent.precision(.fractionLength(0)))
        HStack(spacing: 5) {
            ProgressRing(share: share, lineWidth: 2.5, track: tint.opacity(0.2), fill: tint)
                .frame(width: 15, height: 15)
            Text(text)
                .font(.system(size: 13, weight: .heavy))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("עקביות בארבעת השבועות האחרונים: \(text)")
    }
}

/// Today's practices as round buttons. The thin ring around a practice shows
/// how steadily it was kept over four weeks.
struct HabitsCard: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.removed }, sort: \Habit.order) private var habits: [Habit]
    @State private var isEditing = Launch.screen == "habits"
    @State private var opened: Habit?
    /// Rises by one for a practice each time it is kept, to throw its sparks.
    @State private var sparks: [String: Int] = [:]
    /// Rises when a sheet closes, since a day may have been set aside there.
    @State private var turn = 0

    private func measure(now: Date) -> [String: Habit.Strength] {
        var all: [String: Habit.Strength] = [:]
        for habit in habits { all[habit.id] = habit.strength(now: now) }
        return all
    }

    private func line(done: Int, back: Habit?, free: String?, now: Date) -> String {
        let left: Int = habits.count - done
        if habits.isEmpty { return "" }
        if left == 0 { return "יום מלא. כל הכבוד!" }
        if let free { return "\(free). היום לא נספר, ומה שתסמנו נשמר." }
        if let back { return "חזרתם ל\(back.title). לחזור אחרי יום שהוחמץ, זה מה שבונה קביעות." }
        if ScheduleItem.minute(of: now) >= 19 * 60 + 30,
           let open = habits.first(where: { !$0.isDone(on: now) && !$0.small.isEmpty }) {
            return "יום עמוס? הגרסה הקטנה של \(open.title): \(open.small)."
        }
        if left == 1 { return "עוד אחת והיום שלם" }
        if done == 0 {
            let yesterday: Date = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            let wasCounted: Bool = Habit.freeNote(on: yesterday) == nil
            let missedYesterday: Bool = wasCounted && !habits.contains { $0.isDone(on: yesterday) }
            return missedYesterday ? "מתחילים מחדש. צעד אחד קטן מספיק" : "מתחילים עם הראשונה"
        }
        return "\(done) מתוך \(habits.count) כבר מאחוריכם"
    }

    var body: some View {
        let now: Date = .now
        let _: Int = turn
        let strengths: [String: Habit.Strength] = measure(now: now)
        let done: Int = habits.filter { $0.isDone(on: now) }.count
        let overall: Double? = Habit.average(habits.filter { !$0.isQuiet }.compactMap { strengths[$0.id] })
        let back: Habit? = habits.first { strengths[$0.id]?.isBack == true }
        let text: String = line(done: done, back: back, free: Habit.freeNote(on: now), now: now)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("קביעות היום")
                    .font(.system(size: 20, weight: .heavy))
                Text("\(done)/\(habits.count)")
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(done == habits.count && !habits.isEmpty ? Theme.accent : Color.secondary)
                Spacer(minLength: 4)
                if let overall {
                    ConsistencyChip(share: overall)
                        .transition(.opacity)
                }
                Button("עריכה") { isEditing = true }
                    .font(.system(size: 14, weight: .bold))
            }

            if habits.isEmpty {
                Text("הוסיפו את הדברים שחשוב לכם לשמור עליהם כל יום.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(habits) { habit in
                        button(habit, strength: strengths[habit.id], now: now)
                    }
                }
                GrowBar(share: Double(done) / Double(max(habits.count, 1)), height: 6,
                        fill: Theme.emerald.gradient)
                    .animation(.smooth(duration: 0.4), value: done)
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.smooth(duration: 0.3), value: text)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .sheet(isPresented: $isEditing, onDismiss: { turn += 1 }) {
            HabitsSheet()
        }
        .sheet(item: $opened, onDismiss: { turn += 1 }) { habit in
            NavigationStack {
                HabitDetail(habit: habit, isAlone: true)
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .task {
            // A test run opens one practice's own page.
            guard Launch.screen == "habit" else { return }
            try? await Task.sleep(for: .seconds(1.2))
            opened = habits.first { $0.id == "habit-torah" } ?? habits.first
        }
    }

    private func toggle(_ habit: Habit, wasDone: Bool) {
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { habit.toggle() }
        try? context.save()
        if wasDone {
            Feedback.tap()
        } else {
            sparks[habit.id, default: 0] += 1
            if !Habit.celebrateIfDayFull(in: context) { Feedback.done() }
        }
    }

    private func button(_ habit: Habit, strength: Habit.Strength?, now: Date) -> some View {
        let isDone: Bool = habit.isDone(on: now)
        var ring: Double?
        if let strength, !habit.isQuiet, !strength.isNew { ring = strength.share }
        let color: Color = habit.artwork.start
        let steadiness: String = ring.map { "עקביות " + $0.formatted(.percent.precision(.fractionLength(0))) } ?? ""
        return Button {
            toggle(habit, wasDone: isDone)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    SparkBurst(trigger: sparks[habit.id] ?? 0, color: color, reach: 20, radius: 34)
                    if let ring {
                        ProgressRing(share: ring, lineWidth: 3, track: color.opacity(0.16), fill: color)
                            .frame(width: 64, height: 64)
                    }
                    Circle()
                        .fill(isDone ? AnyShapeStyle(habit.artwork.gradient) : AnyShapeStyle(Theme.chip))
                        .frame(width: 54, height: 54)
                    Image(systemName: isDone ? "checkmark" : habit.symbol)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(isDone ? Color.white : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 64, height: 64)
                .scaleEffect(isDone ? 1.0 : 0.94)
                Text(habit.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDone ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .contextMenu {
            Button("העקביות והפרטים", systemImage: "chart.bar.fill") { opened = habit }
            if !isDone && !habit.small.isEmpty {
                Button("הגרסה הקטנה: \(habit.small)", systemImage: "leaf.fill") {
                    toggle(habit, wasDone: false)
                }
            }
        }
        .accessibilityLabel(habit.title)
        .accessibilityValue(steadiness)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}

/// A practice's consistency inside a row: a small ring and its number, or a
/// word when there is nothing to measure.
private struct HabitGauge: View {
    let habit: Habit
    let strength: Habit.Strength

    var body: some View {
        let color: Color = habit.artwork.start
        if habit.isQuiet || strength.isNew {
            Text(habit.isQuiet ? "בלי מדידה" : "חדשה")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Text(strength.percent)
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(color)
                ProgressRing(share: strength.share, lineWidth: 3.5, track: color.opacity(0.18), fill: color)
                    .frame(width: 24, height: 24)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("עקביות \(strength.percent)")
        }
    }
}

/// The list of practices: each with its consistency and its last week, the
/// way into its own page, a new one, and a day set aside.
struct HabitsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Habit> { !$0.removed }, sort: \Habit.order) private var habits: [Habit]
    @State private var newTitle = ""
    @State private var opened: Habit?
    @State private var isOff: Bool = OffDays.isOff()

    private var week: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
    }

    var body: some View {
        let rest: String? = Habit.restNote()
        NavigationStack {
            List {
                Section {
                    ForEach(habits) { habit in
                        row(habit)
                    }
                    .onMove(perform: move)
                } footer: {
                    Text("הטבעת מראה כמה כל קביעות יציבה בארבעת השבועות האחרונים. החמצה אחת בשבוע לא נספרת, ושבת, חג וצום לא נספרים בכלל. אפשר לסמן גם ימים קודמים, ולגרור שורה כדי לשנות את הסדר.")
                }

                Section {
                    if let rest {
                        Label("\(rest). היום לא נספר.", systemImage: "moon.stars.fill")
                            .font(.system(size: 15, weight: .semibold))
                    } else {
                        Toggle(isOn: $isOff) {
                            Label {
                                Text("היום יום חריג")
                                    .font(.system(size: 16, weight: .bold))
                            } icon: {
                                Image(systemName: "moon.zzz.fill")
                                    .foregroundStyle(Theme.violet.start)
                            }
                        }
                        .tint(Theme.accent)
                    }
                } footer: {
                    Text("נסיעה, מחלה או שמחה: ביום חריג לא מצופה כלום, והעקביות לא נפגעת. מה שתסמנו בכל זאת נשמר.")
                }

                Section("קביעות חדשה") {
                    HStack {
                        TextField("למשל: רמב״ם יומי", text: $newTitle)
                            .onSubmit { add() }
                        Button("הוספה") { add() }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("הקביעויות שלי")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $opened) { habit in
                HabitDetail(habit: habit)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
            .onChange(of: isOff) { _, value in
                OffDays.set(value)
                Feedback.tap()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func row(_ habit: Habit) -> some View {
        let strength: Habit.Strength = habit.strength()
        let anchor: String = habit.anchor.trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                opened = habit
            } label: {
                HStack(spacing: 10) {
                    ArtworkIcon(artwork: habit.artwork, symbol: habit.symbol, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(habit.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.primary)
                        if !anchor.isEmpty {
                            Text(anchor)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    HabitGauge(habit: habit, strength: strength)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("פותח את דף הקביעות")

            HStack(spacing: 6) {
                ForEach(week, id: \.self) { day in
                    let isDone: Bool = habit.isDone(on: day)
                    let index: Int = Calendar.current.component(.weekday, from: day) - 1
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { habit.toggle(on: day) }
                        try? context.save()
                        Feedback.tap()
                    } label: {
                        Text(ScheduleItem.dayLetters[index])
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .foregroundStyle(isDone ? Color.white : Color.secondary)
                            .background(isDone ? AnyShapeStyle(habit.artwork.gradient) : AnyShapeStyle(Theme.chip),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(HebrewDate.weekday(day))
                    .accessibilityAddTraits(isDone ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list: [Habit] = habits
        list.move(fromOffsets: source, toOffset: destination)
        for (index, habit) in list.enumerated() { habit.order = index }
        try? context.save()
    }

    private func add() {
        let text: String = newTitle.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let symbols: [String] = ["star.fill", "book.fill", "heart.fill", "figure.walk", "leaf.fill", "drop.fill"]
        context.insert(Habit(title: text, symbol: symbols[habits.count % symbols.count],
                             palette: habits.count, order: (habits.map(\.order).max() ?? -1) + 1))
        try? context.save()
        newTitle = ""
        Feedback.added()
    }
}

/// One practice: how steadily it is kept, its four weeks, and what holds it.
struct HabitDetail: View {
    @Bindable var habit: Habit
    /// Opened on its own and not from the list, so it closes itself.
    var isAlone = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isDeleting = false
    @State private var sparks = 0

    private static let symbols: [String] = [
        "sunrise.fill", "book.fill", "text.book.closed.fill", "sun.max.fill", "heart.fill", "moon.stars.fill",
        "drop.fill", "figure.walk", "leaf.fill", "star.fill", "flame.fill", "bed.double.fill", "fork.knife",
        "pencil", "phone.fill", "dumbbell.fill", "music.note", "person.2.fill",
    ]
    private static let anchors: [String] = [
        "אחרי שחרית", "לפני התפילה", "אחרי ארוחת הבוקר", "אחרי מנחה", "אחרי ארוחת הערב", "לפני השינה",
    ]

    var body: some View {
        let now: Date = .now
        let strength: Habit.Strength = habit.strength(now: now)
        ScrollView {
            VStack(spacing: 18) {
                hero(strength, now: now)
                    .cascade(0)
                weeks(strength, now: now)
                    .cascade(1)
                holds
                    .cascade(2)
                look
                    .cascade(3)
                measure
                    .cascade(4)
                Button("למחוק את הקביעות", systemImage: "trash", role: .destructive) { isDeleting = true }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.vertical, 6)
                    .cascade(5)
            }
            .padding(16)
            .animation(.section, value: habit.isQuiet)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AmbientGround(artwork: habit.artwork) }
        .navigationTitle(habit.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isAlone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
        }
        .confirmationDialog("למחוק את הקביעות?", isPresented: $isDeleting, titleVisibility: .visible) {
            Button("מחיקה", role: .destructive) {
                habit.removed = true
                try? context.save()
                dismiss()
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("\(habit.title) תרד מהרשימה ומדף הבית.")
        }
        .onAppear { name = habit.title }
        .onChange(of: name) { _, value in
            let text: String = value.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { habit.title = text }
        }
        .onDisappear { try? context.save() }
        .arrives()
    }

    // MARK: The number

    private func headline(_ strength: Habit.Strength) -> String {
        if habit.isQuiet { return habit.title }
        if strength.isNew { return "ימים ראשונים" }
        if strength.share >= 0.9 { return "קביעות יציבה" }
        if strength.share >= 0.7 { return "קביעות טובה" }
        if strength.share >= 0.4 { return "הולכת ונבנית" }
        return "מתחילים מחדש"
    }

    private func detail(_ strength: Habit.Strength) -> String {
        if habit.isQuiet { return "מסמנים, בלי אחוזים ובלי השוואות. הסימון הוא בשבילכם." }
        if strength.isNew { return "אחרי שלושה ימים שנספרו תופיע כאן העקביות." }
        var text: String = strength.kept == 1 ? "נשמרה ביום אחד" : "נשמרה ב־\(strength.kept) ימים"
        if strength.missed > 0 {
            text += strength.missed == 1 ? ", הוחמצה ביום אחד" : ", הוחמצה ב־\(strength.missed)"
        }
        if strength.forgiven > 0 {
            text += strength.forgiven == 1 ? ", והחמצה אחת לא נספרה" : ", ו־\(strength.forgiven) החמצות לא נספרו"
        }
        text += "."
        if strength.hasReserve { text += " השבוע יש לכם עוד החמצה אחת שלא נספרת." }
        return text
    }

    private func hero(_ strength: Habit.Strength, now: Date) -> some View {
        let isDone: Bool = habit.isDone(on: now)
        let title: String = headline(strength)
        let text: String = detail(strength)
        let label: String = habit.isQuiet ? "בלי מדידה" : "עקביות · ארבעה שבועות"
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                if habit.isQuiet || strength.isNew {
                    Image(systemName: habit.symbol)
                        .font(.system(size: 32, weight: .bold))
                        .frame(width: 76, height: 76)
                        .background(.white.opacity(0.18), in: Circle())
                } else {
                    ZStack {
                        ProgressRing(share: strength.share, lineWidth: 10)
                        CountUp(value: strength.share) { $0.formatted(.percent.precision(.fractionLength(0))) }
                            .font(.system(size: 26, weight: .heavy))
                            .monospacedDigit()
                    }
                    .frame(width: 104, height: 104)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(0.9)
                    Text(title)
                        .font(.system(size: 26, weight: .heavy))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(text)
                        .font(.system(size: 14, weight: .medium))
                        .opacity(0.92)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) { habit.toggle(on: now) }
                try? context.save()
                if isDone {
                    Feedback.tap()
                } else {
                    sparks += 1
                    if !Habit.celebrateIfDayFull(in: context) { Feedback.done() }
                }
            } label: {
                Label(isDone ? "נשמרה היום" : "לסמן את היום", systemImage: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(isDone ? Color.white : habit.artwork.end)
                    .background(isDone ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(Color.white),
                                in: Capsule())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .background { SparkBurst(trigger: sparks, color: .white, reach: 30, radius: 40) }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(habit.artwork, watermark: habit.symbol)
    }

    // MARK: Four weeks

    private func ink(_ mark: Habit.DayMark, isToday: Bool, isAhead: Bool) -> Color {
        if isAhead { return Color.secondary.opacity(0.35) }
        switch mark {
        case .kept: return .white
        case .forgiven: return habit.artwork.start
        case .missed: return .secondary
        case .free: return Color.secondary.opacity(0.55)
        case .blank: return isToday ? Color.primary : Color.secondary.opacity(0.35)
        }
    }

    private func said(_ mark: Habit.DayMark, isToday: Bool) -> String {
        switch mark {
        case .kept: return "נשמרה"
        case .forgiven: return "החמצה שלא נספרת"
        case .missed: return "הוחמצה"
        case .free: return "לא נספר"
        case .blank: return isToday ? "עוד פתוח" : ""
        }
    }

    private func cell(_ index: Int, strength: Habit.Strength, now: Date) -> some View {
        let mark: Habit.DayMark = strength.marks[index]
        let isAhead: Bool = index > strength.todayIndex
        let isToday: Bool = index == strength.todayIndex
        let day: Date = Habit.day(at: index, in: strength, now: now)
        let number: String = "\(Calendar.current.component(.day, from: day))"
        let color: Color = habit.artwork.start
        let dash: [CGFloat] = mark == .kept ? [] : [4, 3]
        let weight: Font.Weight = mark == .kept || isToday ? .heavy : .medium
        return Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) { habit.toggle(on: day) }
            try? context.save()
            if mark == .kept { Feedback.tap() } else { Feedback.done() }
        } label: {
            ZStack {
                switch mark {
                case .kept:
                    Circle().fill(habit.artwork.gradient)
                case .forgiven:
                    Circle().fill(color.opacity(0.2))
                case .missed:
                    Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1.5)
                case .free, .blank:
                    Circle().fill(Color.clear)
                }
                if isToday {
                    Circle()
                        .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: dash))
                        .padding(-4)
                }
                Text(number)
                    .font(.system(size: 14, weight: weight))
                    .monospacedDigit()
                    .foregroundStyle(ink(mark, isToday: isToday, isAhead: isAhead))
            }
            .frame(width: 34, height: 34)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(isAhead)
        .accessibilityLabel("\(HebrewDate.weekday(day)) \(number)")
        .accessibilityValue(isAhead ? "" : said(mark, isToday: isToday))
    }

    private func key<Mark: View>(_ text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) {
            mark()
                .frame(width: 12, height: 12)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func weeks(_ strength: Habit.Strength, now: Date) -> some View {
        let color: Color = habit.artwork.start
        return VStack(alignment: .leading, spacing: 12) {
            Text("ארבעה שבועות")
                .font(.system(size: 20, weight: .heavy))
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Text(ScheduleItem.dayLetters[index] + "׳")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<4, id: \.self) { week in
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { weekday in
                        cell(week * 7 + weekday, strength: strength, now: now)
                    }
                }
            }
            if !habit.isQuiet {
                HStack(spacing: 14) {
                    key("נשמרה") { Circle().fill(habit.artwork.gradient) }
                    key("החמצה שלא נספרת") { Circle().fill(color.opacity(0.25)) }
                    key("הוחמצה") { Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5) }
                }
                .padding(.top, 2)
            }
            Text(habit.isQuiet
                 ? "נגיעה ביום מסמנת אותו."
                 : "שבת, חג, צום ויום חריג לא נספרים. נגיעה ביום מסמנת אותו.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: What holds it

    private var promise: String {
        let anchor: String = habit.anchor.trimmingCharacters(in: .whitespaces)
        let small: String = habit.small.trimmingCharacters(in: .whitespaces)
        var parts: [String] = []
        if !anchor.isEmpty { parts.append("\(anchor): \(habit.title).") }
        if !small.isEmpty { parts.append("ביום עמוס: \(small).") }
        return parts.joined(separator: " ")
    }

    private func field(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .font(.system(size: 16))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var holds: some View {
        let sentence: String = promise
        return VStack(alignment: .leading, spacing: 14) {
            Text("מה מחזיק אותה")
                .font(.system(size: 20, weight: .heavy))
            VStack(alignment: .leading, spacing: 8) {
                Text("אחרי מה?")
                    .font(.system(size: 15, weight: .bold))
                Text("קביעות נתפסת כשהיא נשענת על משהו שכבר קורה כל יום.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                field("למשל: אחרי שחרית", text: $habit.anchor)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Self.anchors, id: \.self) { text in
                            let isOn: Bool = habit.anchor == text
                            Button {
                                withAnimation(.section) { habit.anchor = isOn ? "" : text }
                                Feedback.tap()
                            } label: {
                                Text(text)
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .foregroundStyle(isOn ? Color.white : Color.primary)
                                    .background(isOn ? AnyShapeStyle(habit.artwork.gradient) : AnyShapeStyle(Theme.chip),
                                                in: Capsule())
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("הגרסה הקטנה")
                    .font(.system(size: 15, weight: .bold))
                Text("מה נחשב גם ביום הכי עמוס? משהו של שתי דקות, שאפשר תמיד.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                field("למשל: משנה אחת", text: $habit.small)
            }
            if !sentence.isEmpty {
                Text(sentence)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(habit.artwork.start.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .animation(.section, value: sentence.isEmpty)
    }

    // MARK: Name and look

    private var look: some View {
        let count: Int = SavingsGoal.palettes.count
        let chosen: Int = abs(habit.palette) % count
        return VStack(alignment: .leading, spacing: 14) {
            Text("שם ומראה")
                .font(.system(size: 20, weight: .heavy))
            field("שם הקביעות", text: $name)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        let isOn: Bool = habit.symbol == symbol
                        Button {
                            withAnimation(.section) { habit.symbol = symbol }
                            Feedback.tap()
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 42, height: 42)
                                .foregroundStyle(isOn ? Color.white : Color.secondary)
                                .background(isOn ? AnyShapeStyle(habit.artwork.gradient) : AnyShapeStyle(Theme.chip),
                                            in: Circle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    Button {
                        withAnimation(.section) { habit.palette = index }
                        Feedback.tap()
                    } label: {
                        Circle()
                            .fill(SavingsGoal.palettes[index].gradient)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if chosen == index {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("צבע \(index + 1)")
                    .accessibilityAddTraits(chosen == index ? .isSelected : [])
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var measure: some View {
        Toggle(isOn: $habit.isQuiet) {
            VStack(alignment: .leading, spacing: 3) {
                Text("בלי מדידה")
                    .font(.system(size: 16, weight: .bold))
                Text("מסמנים, אבל בלי אחוזים ובלי טבעת. כך מוגדרות התפילות מלכתחילה.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.accent)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
