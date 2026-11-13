import SwiftData
import SwiftUI

/// A colorful rounded square with a symbol, like an album cover.
struct ArtworkIcon: View {
    let artwork: Artwork
    let symbol: String
    var size: CGFloat = 42

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(artwork.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// The round check that starts a list row. It fills at once, with a chime
/// and a ring of sparks, and the row itself changes a moment later, so the
/// eye catches the reward before the row moves away.
struct CheckButton: View {
    let isDone: Bool
    var isImportant = false
    /// Text that belongs to the same touch, for rows that can only be ticked.
    var title: String? = nil
    let action: () -> Void
    @State private var isChecking = false
    @State private var sparks = 0

    var body: some View {
        let isOn: Bool = isDone || isChecking
        Button {
            press()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 25, weight: isImportant ? .bold : .regular))
                    .foregroundStyle(isOn ? Theme.accent : (isImportant ? Color(hex: 0xEA580C) : Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 42, height: 48)
                    .background { SparkBurst(trigger: sparks) }
                if let title {
                    Text(title)
                        .font(.system(size: 17, weight: isOn ? .regular : .semibold))
                        .strikethrough(isOn)
                        .foregroundStyle(isOn ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(title ?? (isDone ? "החזרה לפתוחות" : "סימון כבוצע"))
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }

    private func press() {
        if isDone {
            Feedback.tap()
            action()
            return
        }
        guard !isChecking else { return }
        withAnimation(.snappy) { isChecking = true }
        sparks += 1
        Feedback.done()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            action()
            isChecking = false
        }
    }
}

/// A bold section title with a chevron, as in Apple Music.
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .buttonStyle(.pressable)
        .disabled(action == nil)
        .padding(.horizontal, 4)
    }
}

/// What is on now, floating above the tab bar on every screen like a mini
/// player: a focus session, a routine that is being played, or the part of
/// the day, the practice or the task whose turn it is. Tapping it opens the
/// full screen.
struct NowTaskBar: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }, sort: \ScheduleItem.startMinute)
    private var items: [ScheduleItem]
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" && !$0.removed && !$0.isDone },
           sort: \ListItem.createdAt, order: .reverse)
    private var tasks: [ListItem]
    @Query(filter: #Predicate<Habit> { !$0.removed }, sort: \Habit.order) private var habits: [Habit]
    @State private var timer = FocusTimer.shared
    @State private var router = AppRouter.shared
    @State private var run = RoutineRun.shared

    /// What the bar says at one moment.
    private struct Face {
        let title: String
        let detail: String
        let symbol: String
        let artwork: Artwork
        let share: Double
        /// A step of a routine is on, and the bar belongs to it.
        var isRoutine = false
    }

    private func makeFace(_ deck: OnDeck, now: Date) -> Face {
        if timer.isActive {
            let detail: String = timer.isRunning
                ? "מיקוד · נשארו \(FocusTimer.clock(timer.remaining(at: now)))"
                : "מיקוד מושהה"
            return Face(title: timer.title, detail: detail, symbol: "timer", artwork: deck.artwork,
                        share: timer.progress(at: now))
        }
        if let routine = run.routine, let step = run.step {
            let left: Int = run.remaining(at: now)
            let time: String = left >= 0
                ? "נשארו \(RoutineRun.clock(left))"
                : "מעבר לזמן · \u{2066}+\(RoutineRun.clock(left))\u{2069}"
            return Face(title: step.title, detail: "\(routine.title) · \(time)", symbol: routine.symbol,
                        artwork: routine.artwork, share: run.progress(at: now), isRoutine: true)
        }
        return Face(title: deck.title, detail: deck.detail, symbol: deck.symbol, artwork: deck.artwork,
                    share: deck.progress ?? 0)
    }

    /// The step that is on was done: the next one comes up, or the routine ends.
    private func stepDone() {
        guard let routine = run.routine else { return }
        let count: String = routine.steps.count == 1 ? "צעד אחד" : "\(routine.steps.count) צעדים"
        let text: String = "\(routine.title) · \(count) ב־\(NowStatus.duration(max(run.elapsed(), 1)))"
        var isOver = false
        withAnimation(.section) { isOver = run.finish(done: true) }
        // A celebration brings its own sound; otherwise the usual chime.
        let celebrated: Bool = isOver && Moments.shared.play(
            "routine." + routine.id, symbol: "checkmark", title: "השגרה הושלמה", text: text, artwork: routine.artwork)
        if !celebrated { Feedback.done() }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: timer.isRunning || run.isActive ? 1 : 30)) { timeline in
            let now = timeline.date
            let _ = router.deckPin
            let deck = Deck.current(items: items, habits: habits, tasks: tasks, now: now)
            let face: Face = makeFace(deck, now: now)
            HStack(spacing: 4) {
                Button {
                    if face.isRoutine {
                        AppRouter.shared.isRoutinePlaying = true
                    } else {
                        AppRouter.shared.isNowPlaying = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        ArtworkIcon(artwork: face.artwork, symbol: face.symbol, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(face.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                            Text(face.detail)
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .animation(.section, value: face.title)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("פתיחת מסך מלא")

                if face.isRoutine || deck.canComplete {
                    Button {
                        if face.isRoutine {
                            stepDone()
                        } else {
                            withAnimation(.section) { Deck.complete(deck, in: context) }
                        }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 40, height: 44)
                    }
                    .accessibilityLabel(face.isRoutine ? "הצעד נעשה, הלאה" : "סימון כבוצע")
                }
                Button {
                    AppRouter.shared.isQuickAdding = true
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 40, height: 44)
                }
                .accessibilityLabel("הוספה מהירה")
            }
            .padding(.horizontal, 12)
            .overlay(alignment: .bottom) {
                if face.share > 0 {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: proxy.size.width * face.share, height: 2.5)
                    }
                    .frame(height: 2.5)
                    .padding(.horizontal, 18)
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
    }
}
