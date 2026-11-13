import SwiftData
import SwiftUI

extension RoutineRun {
    /// Begins a routine, or goes on with the one that is being played, and
    /// opens its screen.
    @MainActor
    static func play(_ routine: Routine, in context: ModelContext, now: Date = .now) {
        if shared.routine?.id != routine.id {
            shared.start(routine.remaining(on: now), now: now)
            // The first signal waits for the family's permission.
            if routine.rings { Task { _ = await Notifier.shared.askPermission() } }
        }
        AppRouter.shared.isRoutinePlaying = true
        Feedback.tap()
        // Its reminder for today is no longer needed.
        Notifier.shared.refresh(in: context)
    }
}

/// The family's routines as a shelf of colorful covers, like playlists:
/// a tap on the play button and the steps come one after another.
struct RoutineShelf: View {
    @Environment(\.modelContext) private var context
    @State private var store = Routines.shared
    @State private var run = RoutineRun.shared
    @State private var editing: Routine?
    @State private var isChoosing = Launch.screen == "routines"
    /// Chosen in the picker; its editor opens once the picker has closed.
    @State private var pending: Routine?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("שגרות")
                    .font(.system(size: 22, weight: .heavy))
                Spacer()
                Button {
                    isChoosing = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Theme.chip, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("שגרה חדשה")
            }
            .padding(.horizontal, 4)

            if store.all.isEmpty {
                starter
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(store.all) { routine in
                            cover(routine)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .padding(.horizontal, -16)
            }
        }
        .sheet(item: $editing) { routine in
            RoutineEditor(routine: routine)
        }
        .sheet(isPresented: $isChoosing, onDismiss: openPending) {
            RoutinePicker { chosen in
                pending = chosen
                isChoosing = false
            }
        }
        // A routine that came or went, or changed its hour, moves its reminder.
        .onChange(of: store.all) { _, _ in Notifier.shared.refresh(in: context) }
        .task {
            // A test run opens the editor of the first routine.
            guard Launch.screen == "routine-edit" else { return }
            try? await Task.sleep(for: .seconds(1.2))
            editing = store.all.first
        }
    }

    private func openPending() {
        guard let chosen = pending else { return }
        pending = nil
        editing = chosen
    }

    /// Before the first routine: what it is, and a few to begin from.
    private var starter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("רצף קבוע של צעדים קצרים, שמתנגן צעד אחרי צעד: בוקר, יציאה מהבית, ערב שבת. לא צריך לחשוב מה עכשיו, ורואים מראש מתי מסיימים.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Routines.templates) { template in
                        Button {
                            withAnimation(.section) { _ = store.add(template: template) }
                            Feedback.added()
                        } label: {
                            Label(template.title, systemImage: template.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 14)
                                .frame(height: 38)
                                .foregroundStyle(.white)
                                .background(template.artwork.gradient, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func cover(_ routine: Routine) -> some View {
        let isPlaying: Bool = run.routine?.id == routine.id
        let count: Int = run.routine?.steps.count ?? routine.steps.count
        let line: String = isPlaying ? "מתנגנת · צעד \(run.index + 1) מתוך \(count)" : routine.summary
        let startBy: String? = routine.isForCandles
            ? "עד הדלקת הנרות"
            : routine.latestStart.map { "להתחיל עד \(ScheduleItem.clock($0))" }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: routine.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.2), in: Circle())
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 30, height: 30)
                    .opacity(0.85)
            }
            Spacer(minLength: 8)
            Text(routine.title)
                .font(.system(size: 20, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(line)
                .font(.system(size: 12, weight: .semibold))
                .opacity(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let startBy {
                Text(startBy)
                    .font(.system(size: 11, weight: .heavy))
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(.white.opacity(0.2), in: Capsule())
                    .padding(.top, 5)
            }
            Button {
                RoutineRun.play(routine, in: context)
            } label: {
                Label(isPlaying ? "להמשיך" : "להתחיל", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundStyle(routine.artwork.end)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(routine.steps.isEmpty)
            .padding(.top, 10)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 176, height: 204, alignment: .leading)
        .livingCard(routine.artwork, radius: 24, seed: Double(abs(routine.palette)) * 0.3,
                    watermark: routine.symbol, isMoving: false)
        .contentShape(Rectangle())
        .onTapGesture { editing = routine }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(routine.title), \(routine.summary)")
    }
}

/// Where a new routine begins: one of the ready-made ones, or an empty one.
struct RoutinePicker: View {
    let choose: (Routine) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Routines.templates) { template in
                        Button {
                            choose(Routines.shared.add(template: template))
                            Feedback.added()
                        } label: {
                            row(template)
                        }
                        .buttonStyle(.pressable)
                    }
                    Button {
                        choose(Routine(title: "", symbol: "play.fill", palette: Routines.shared.all.count + 1))
                    } label: {
                        Label("שגרה ריקה", systemImage: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(Color.primary)
                            .background(Theme.chip, in: Theme.cardShape)
                    }
                    .buttonStyle(.pressable)
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("שגרה חדשה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func row(_ template: Routine) -> some View {
        let names: String = template.steps.map(\.title).joined(separator: " · ")
        return HStack(alignment: .top, spacing: 12) {
            ArtworkIcon(artwork: template.artwork, symbol: template.symbol, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(template.title)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.primary)
                Text(names)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Text(template.summary)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Builds or changes one routine: its steps in order, how long each takes,
/// and when it should all be over.
struct RoutineEditor: View {
    @State private var draft: Routine
    @State private var newStep = ""
    @State private var newMinutes = 10
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @FocusState private var isAdding: Bool

    private let lengths: [Int] = [2, 5, 10, 15, 20, 30, 45, 60, 90, 120]
    private static let symbols: [String] = [
        "sunrise.fill", "moon.stars.fill", "flame.fill", "figure.walk", "book.fill", "house.fill",
        "fork.knife", "car.fill", "bed.double.fill", "briefcase.fill", "heart.fill", "play.fill",
    ]

    init(routine: Routine) {
        _draft = State(initialValue: routine)
    }

    private var isKnown: Bool { Routines.shared.all.contains { $0.id == draft.id } }

    /// 0 for no goal, 1 for a clock time, 2 for candle lighting.
    private var goalKind: Binding<Int> {
        Binding(
            get: { draft.isForCandles ? 2 : (draft.goalMinute == nil ? 0 : 1) },
            set: { kind in
                draft.isForCandles = kind == 2
                if kind == 1 {
                    draft.goalMinute = draft.goalMinute ?? 8 * 60
                } else {
                    draft.goalMinute = nil
                }
            })
    }

    private var goalDate: Binding<Date> {
        Binding(
            get: {
                let minute: Int = draft.goalMinute ?? 8 * 60
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            },
            set: { draft.goalMinute = ScheduleItem.minute(of: $0) })
    }

    private var goalNote: String {
        if draft.isForCandles {
            var text: String = "בערב שבת ובערב חג הצעדים מופיעים בלוח ההכנות, וליד כל אחד השעה שבה צריך להתחיל אותו כדי להספיק עד הדלקת הנרות."
            if draft.reminds { text += " תזכורת אחת מגיעה מעט לפני שצריך להתחיל את מה שנשאר." }
            return text
        }
        if let goal = draft.goalMinute {
            let start: Int = max(goal - draft.minutes, 0)
            var text: String = "כדי לסיים עד \(ScheduleItem.clock(goal)) צריך להתחיל עד \(ScheduleItem.clock(start))."
            if draft.reminds { text += " תזכורת אחת מגיעה חמש דקות לפני כן, בימים שנבחרו." }
            return text
        }
        return "בלי שעת יעד, השגרה מראה מתי תסיימו אם תתחילו עכשיו."
    }

    /// A routine with an hour to end by needs at least one day to be on.
    private var hasNoDays: Bool {
        draft.goalMinute != nil && draft.weekdays & ScheduleItem.weekdaysMask == 0
    }

    /// The working days it is meant for. Shabbat is never one of them.
    private var days: some View {
        HStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { index in
                let isOn: Bool = draft.weekdays & (1 << index) != 0
                Button {
                    draft.weekdays ^= (1 << index)
                } label: {
                    Text(ScheduleItem.dayLetters[index])
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(isOn ? Theme.accent : Theme.chip, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("יום " + ScheduleItem.dayLetters[index])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    var body: some View {
        let total: String = draft.steps.isEmpty
            ? "הוסיפו את הצעד הראשון. צעדים קצרים עובדים הכי טוב."
            : "סך הכול \(NowStatus.duration(draft.minutes)). החלקה על צעד מוחקת אותו, ולחיצה ארוכה מזיזה אותו."
        NavigationStack {
            Form {
                Section {
                    TextField("שם השגרה, למשל: בוקר", text: $draft.title)
                        .font(.system(size: 18, weight: .bold))
                }
                Section {
                    ForEach($draft.steps) { $step in
                        HStack(spacing: 10) {
                            TextField("מה עושים", text: $step.title)
                            Menu {
                                ForEach(lengths, id: \.self) { value in
                                    Button(NowStatus.duration(value)) { step.minutes = value }
                                }
                            } label: {
                                length(step.minutes)
                            }
                        }
                    }
                    .onDelete { draft.steps.remove(atOffsets: $0) }
                    .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
                    HStack(spacing: 10) {
                        TextField("צעד חדש", text: $newStep)
                            .focused($isAdding)
                            .onSubmit { addStep() }
                        Menu {
                            ForEach(lengths, id: \.self) { value in
                                Button(NowStatus.duration(value)) { newMinutes = value }
                            }
                        } label: {
                            length(newMinutes)
                        }
                        Button {
                            addStep()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                        }
                        .buttonStyle(.pressable)
                        .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("הוספת הצעד")
                    }
                } header: {
                    Text("הצעדים, לפי הסדר")
                } footer: {
                    Text(total)
                }
                Section {
                    Picker("מתי היא נגמרת", selection: goalKind) {
                        Text("בלי שעת יעד").tag(0)
                        Text("בשעה קבועה").tag(1)
                        Text("בהדלקת נרות").tag(2)
                    }
                    if draft.goalMinute != nil {
                        DatePicker("לסיים עד", selection: goalDate, displayedComponents: .hourAndMinute)
                        days
                    }
                    if draft.goalMinute != nil || draft.isForCandles {
                        Toggle("להזכיר מתי להתחיל", isOn: $draft.reminds)
                    }
                } footer: {
                    Text(goalNote)
                }
                Section {
                    Toggle("צליל כשהזמן של צעד נגמר", isOn: $draft.rings)
                } footer: {
                    Text("התראה קצרה בסוף הזמן של כל צעד, עם כפתור שמעביר לצעד הבא בלי לפתוח את האפליקציה. לא מתאים לשגרה שיש בה תפילה.")
                }
                Section("מראה") {
                    SymbolGrid(symbols: RoutineEditor.symbols, selection: $draft.symbol)
                    PaletteRow(selection: $draft.palette)
                }
                if isKnown {
                    Section {
                        Button("מחיקת השגרה", role: .destructive) { isDeleting = true }
                    }
                }
            }
            .navigationTitle(isKnown ? "עריכת שגרה" : "שגרה חדשה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { save() }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || hasNoDays)
                }
            }
            .confirmationDialog("למחוק את השגרה?", isPresented: $isDeleting, titleVisibility: .visible) {
                Button("מחיקה", role: .destructive) {
                    if RoutineRun.shared.routine?.id == draft.id { RoutineRun.shared.stop() }
                    Routines.shared.remove(draft.id)
                    Notifier.shared.refresh(in: context)
                    dismiss()
                }
                Button("ביטול", role: .cancel) {}
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func length(_ minutes: Int) -> some View {
        Text(NowStatus.duration(minutes))
            .font(.system(size: 14, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.chip, in: Capsule())
    }

    private func addStep() {
        let text: String = newStep.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        withAnimation(.section) { draft.steps.append(Routine.Step(title: text, minutes: newMinutes)) }
        newStep = ""
        isAdding = true
        Feedback.tap()
    }

    private func save() {
        addStep()
        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
        draft.steps = draft.steps.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        if draft.isForCandles {
            // Only one routine leads up to the candles.
            for other in Routines.shared.all where other.isForCandles && other.id != draft.id {
                var changed: Routine = other
                changed.isForCandles = false
                Routines.shared.put(changed)
            }
        }
        if draft.goalMinute == nil && !draft.isForCandles { draft.reminds = false }
        Routines.shared.put(draft)
        if draft.reminds || draft.rings { Task { _ = await Notifier.shared.askPermission() } }
        Notifier.shared.refresh(in: context)
        Feedback.done()
        dismiss()
    }
}

/// A routine being played, on the whole screen: the step that is on, the
/// time it has left, and when it will all be over.
struct RoutinePlayer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var run = RoutineRun.shared
    @State private var summary: Summary?
    @State private var sparks = 0

    /// What is said once the last step is done.
    private struct Summary {
        let title: String
        let artwork: Artwork
        let steps: Int
        let minutes: Int
        let note: String
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ZStack {
                if let routine = run.routine, let step = run.step {
                    playing(routine, step: step, now: timeline.date)
                        .transition(.opacity)
                } else if let summary {
                    ending(summary)
                        .transition(.opacity)
                } else {
                    Theme.ground
                        .ignoresSafeArea()
                        .onAppear { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .arrives()
    }

    // MARK: A step that is on

    /// The minute the routine aims to end by today, when it has one.
    private func goal(_ routine: Routine, now: Date) -> (minute: Int, name: String)? {
        if routine.isForCandles {
            guard JewishDay.of(now).isEve,
                  let candles = Zmanim(day: now).list.first(where: { $0.id == "candles" }) else { return nil }
            return (ScheduleItem.minute(of: candles.date), "הדלקת הנרות")
        }
        if let minute = routine.goalMinute { return (minute, "היעד") }
        return nil
    }

    private func endLine(_ routine: Routine, now: Date) -> String {
        let end: Int = ScheduleItem.minute(of: run.end(at: now))
        var text: String = "סיום משוער ב־\(ScheduleItem.clock(end))"
        if let target = goal(routine, now: now) {
            let gap: Int = target.minute - end
            if gap >= 0 {
                text += " · \(NowStatus.duration(gap)) לפני \(target.name)"
            } else {
                text += " · \(NowStatus.duration(-gap)) אחרי \(target.name)"
            }
        }
        return text
    }

    private func playing(_ routine: Routine, step: Routine.Step, now: Date) -> some View {
        let left: Int = run.remaining(at: now)
        let isOver: Bool = left < 0
        let clock: String = (isOver ? "+" : "") + RoutineRun.clock(left)
        let after: String = run.following.map { "אחר כך: \($0.title) · \(NowStatus.duration($0.minutes))" } ?? "זה הצעד האחרון"
        let ends: String = endLine(routine, now: now)
        return VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("מזעור. השגרה ממשיכה")
                Spacer()
                VStack(spacing: 1) {
                    Text(routine.title)
                        .font(.system(size: 16, weight: .heavy))
                    Text("צעד \(run.index + 1) מתוך \(routine.steps.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.85)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button {
                    run.stop()
                    dismiss()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("עצירת השגרה")
            }
            segments(routine, now: now)
                .padding(.top, 14)

            Spacer(minLength: 12)

            ZStack {
                ProgressRing(share: run.progress(at: now), lineWidth: 14)
                VStack(spacing: 2) {
                    Text(clock)
                        .font(.system(size: 56, weight: .heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(isOver ? "מעבר לזמן, וזה בסדר" : "נשארו")
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(0.85)
                }
                .padding(.horizontal, 30)
            }
            .frame(width: 252, height: 252)
            .environment(\.layoutDirection, .rightToLeft)

            Spacer(minLength: 12)

            VStack(spacing: 6) {
                Text(step.title)
                    .font(.system(size: 32, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .id(step.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -26)), removal: .opacity))
                Text(after)
                    .font(.system(size: 15, weight: .medium))
                    .opacity(0.85)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(ends)
                    .font(.system(size: 13, weight: .heavy))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(.white.opacity(0.18), in: Capsule())
                    .padding(.top, 6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 12)

            controls(routine)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background {
            LivingGradient(artwork: routine.artwork)
                .ignoresSafeArea()
        }
    }

    /// One short line for every step: the ones behind are full, the one
    /// that is on fills as its time passes.
    private func segments(_ routine: Routine, now: Date) -> some View {
        let share: CGFloat = CGFloat(run.progress(at: now))
        let current: Int = run.index
        return HStack(spacing: 4) {
            ForEach(0..<routine.steps.count, id: \.self) { index in
                let fill: CGFloat = index < current ? 1 : (index == current ? share : 0)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.28))
                        Capsule().fill(.white)
                            .frame(width: proxy.size.width * fill)
                    }
                }
                .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private func roundButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .bold))
                .frame(width: 60, height: 60)
                .background(.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    private func controls(_ routine: Routine) -> some View {
        let isFirst: Bool = run.index == 0
        let isLast: Bool = run.following == nil
        // Playback buttons keep their places in every language.
        return HStack(spacing: 14) {
            roundButton("backward.end.fill", label: "הצעד הקודם") {
                withAnimation(.section) { run.back() }
                Feedback.tap()
            }
            .opacity(isFirst ? 0.35 : 1)
            .disabled(isFirst)
            Button {
                finish(done: true)
            } label: {
                Label(isLast ? "סיימתי" : "סיימתי, הלאה", systemImage: "checkmark")
                    .font(.system(size: 18, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .foregroundStyle(routine.artwork.end)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.pressable)
            roundButton("forward.end.fill", label: "לדלג על הצעד") {
                finish(done: false)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func finish(done: Bool) {
        guard let routine = run.routine else { return }
        let now: Date = .now
        if run.following != nil {
            withAnimation(.section) { _ = run.finish(done: done, now: now) }
            if done { Feedback.done() } else { Feedback.tap() }
            return
        }
        // The last step: say how it went before the run is gone.
        var note: String = ""
        if let target = goal(routine, now: now) {
            let gap: Int = target.minute - ScheduleItem.minute(of: now)
            note = gap >= 0
                ? "סיימתם \(NowStatus.duration(gap)) לפני \(target.name)."
                : "סיימתם \(NowStatus.duration(-gap)) אחרי \(target.name). אפשר להתחיל מוקדם יותר, או לקצר צעד."
        }
        let made = Summary(title: routine.title, artwork: routine.artwork, steps: routine.steps.count,
                           minutes: max(run.elapsed(at: now), 1), note: note)
        withAnimation(.section) {
            summary = made
            _ = run.finish(done: done, now: now)
        }
        Feedback.celebrate()
    }

    // MARK: The end

    private func ending(_ summary: Summary) -> some View {
        let count: String = summary.steps == 1 ? "צעד אחד" : "\(summary.steps) צעדים"
        return VStack(spacing: 16) {
            Spacer()
            ZStack {
                SparkBurst(trigger: sparks, color: .white, reach: 70, radius: 76)
                Image(systemName: "checkmark")
                    .font(.system(size: 54, weight: .heavy))
                    .frame(width: 132, height: 132)
                    .background(.white.opacity(0.2), in: Circle())
            }
            Text("השגרה הושלמה")
                .font(.system(size: 34, weight: .heavy))
            Text("\(summary.title) · \(count) ב־\(NowStatus.duration(summary.minutes))")
                .font(.system(size: 17, weight: .semibold))
                .opacity(0.92)
                .multilineTextAlignment(.center)
            if !summary.note.isEmpty {
                Text(summary.note)
                    .font(.system(size: 15, weight: .medium))
                    .opacity(0.88)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("סגירה")
                    .font(.system(size: 18, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .foregroundStyle(summary.artwork.end)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background {
            LivingGradient(artwork: summary.artwork)
                .ignoresSafeArea()
        }
        .onAppear { sparks += 1 }
    }
}

/// The board of a day that ends in candle lighting: how long until the
/// candles, what is still to be done, and by when each thing has to begin.
struct ErevCard: View {
    let now: Date
    @Environment(\.modelContext) private var context
    @State private var store = Routines.shared

    static let artwork = Artwork(0xF59E0B, 0xDB2777)

    var body: some View {
        // Counted again whenever a step is marked, here or in the player.
        let _: Int = store.turn
        if let board = ErevBoard.make(now: now, routine: store.forCandles) {
            VStack(alignment: .leading, spacing: 12) {
                hero(board)
                if let candle = board.chanukahCandle {
                    note("הערב נר \(JewishDay.ordinal(candle)) של חנוכה. בערב שבת מדליקים אותו לפני נרות השבת.",
                         symbol: "flame.fill")
                }
                if store.forCandles == nil {
                    offer
                } else if !board.lines.isEmpty {
                    list(board)
                }
            }
        }
    }

    private func hero(_ board: ErevBoard) -> some View {
        let total: Int = board.lines.reduce(0) { $0 + $1.minutes }
        let share: Double = total > 0 ? Double(total - board.left) / Double(total) : 0
        let until: String = board.untilCandles > 0 ? "בעוד \(NowStatus.duration(board.untilCandles))" : ""
        let verdict: String = board.verdict
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(board.eveName, systemImage: "flame.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(.white.opacity(0.2), in: Capsule())
                Spacer(minLength: 0)
                Text(until)
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text("הדלקת נרות ב־\(ScheduleItem.clock(board.candlesMinute))")
                .font(.system(size: 30, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !verdict.isEmpty {
                Text(verdict)
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.94)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if total > 0 {
                GrowBar(share: share, height: 7, track: .white.opacity(0.25), fill: Color.white)
                    .animation(.smooth(duration: 0.4), value: share)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(ErevCard.artwork, seed: 0.6, watermark: "flame.fill")
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.amberInk)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.amberInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.amberGround, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Before the family has a board of its own: one tap brings a first one.
    private var offer: some View {
        Button {
            if let template = Routines.templates.first(where: { $0.isForCandles }) {
                withAnimation(.section) { _ = store.add(template: template) }
                Feedback.added()
                Task { _ = await Notifier.shared.askPermission() }
                Notifier.shared.refresh(in: context)
            }
        } label: {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: ErevCard.artwork, symbol: "checklist")
                VStack(alignment: .leading, spacing: 2) {
                    Text("להוסיף את לוח ההכנות")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text("רשימת ההכנות שלכם, עם השעה שבה כל דבר צריך להתחיל כדי להספיק, ותזכורת אחת כשמגיע הזמן. אפשר לשנות בה הכול.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .cardSurface()
        }
        .buttonStyle(.pressable)
    }

    private func list(_ board: ErevBoard) -> some View {
        let minute: Int = ScheduleItem.minute(of: now)
        let canPlay: Bool = board.left > 0 && board.untilCandles > 0
        return VStack(spacing: 0) {
            HStack {
                Text("ההכנות, לפי הסדר")
                    .font(.system(size: 15, weight: .heavy))
                Spacer()
                if canPlay, let routine = store.forCandles {
                    Button {
                        RoutineRun.play(routine, in: context)
                    } label: {
                        Label("צעד אחרי צעד", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .heavy))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .foregroundStyle(.white)
                            .background(ErevCard.artwork.gradient, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.vertical, 12)
            ForEach(board.lines) { line in
                Divider()
                row(line, minute: minute)
            }
        }
        .padding(.horizontal, 14)
        .cardSurface()
    }

    private func row(_ line: ErevBoard.Line, minute: Int) -> some View {
        let isLate: Bool = (line.latest ?? Int.max) <= minute
        let when: String = line.latest.map { isLate ? "להתחיל עכשיו" : "להתחיל עד \(ScheduleItem.clock($0))" } ?? "נעשה"
        return HStack(spacing: 12) {
            CheckButton(isDone: line.isDone) {
                withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                    ErevBoard.setDone(line.id, !line.isDone, on: .now)
                }
                // The reminder to begin moves with what is left.
                Notifier.shared.refresh(in: context)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(line.title)
                    .font(.system(size: 16, weight: .bold))
                    .strikethrough(line.isDone)
                    .lineLimit(2)
                Text(NowStatus.duration(line.minutes))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(when)
                .font(.system(size: 13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(line.isDone ? Color.secondary : (isLate ? Theme.amberInk : Theme.accent))
        }
        .opacity(line.isDone ? 0.55 : 1)
        .frame(minHeight: 54)
    }
}
