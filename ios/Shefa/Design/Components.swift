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

/// What is on now in the family's schedule, floating above the tab bar on
/// every screen like a mini player. Tapping it opens the full screen.
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 1 : 30)) { timeline in
            let now = timeline.date
            let _ = router.deckPin
            let deck = Deck.current(items: items, habits: habits, tasks: tasks, now: now)
            let title = timer.isActive ? timer.title : deck.title
            let detail = timer.isActive
                ? (timer.isRunning ? "מיקוד · נשארו \(FocusTimer.clock(timer.remaining(at: now)))" : "מיקוד מושהה")
                : deck.detail
            let share = timer.isActive ? timer.progress(at: now) : (deck.progress ?? 0)
            HStack(spacing: 4) {
                Button {
                    AppRouter.shared.isNowPlaying = true
                } label: {
                    HStack(spacing: 10) {
                        ArtworkIcon(artwork: deck.artwork, symbol: timer.isActive ? "timer" : deck.symbol, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                            Text(detail)
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .animation(.section, value: title)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("פתיחת מסך מלא")

                if deck.canComplete {
                    Button {
                        withAnimation(.section) { Deck.complete(deck, in: context) }
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("סימון כבוצע")
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
                if share > 0 {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: proxy.size.width * share, height: 2.5)
                    }
                    .frame(height: 2.5)
                    .padding(.horizontal, 18)
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
    }
}
