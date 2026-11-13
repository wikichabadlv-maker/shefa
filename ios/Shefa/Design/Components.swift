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
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }, sort: \ScheduleItem.startMinute)
    private var items: [ScheduleItem]
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" && !$0.removed && !$0.isDone },
           sort: \ListItem.createdAt, order: .reverse)
    private var tasks: [ListItem]
    @State private var timer = FocusTimer.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 1 : 30)) { timeline in
            let now = timeline.date
            let top = tasks.first(where: \.isForToday)?.title
            let status = NowStatus.make(items: items, topTask: top, now: now)
            let title = timer.isActive ? timer.title : status.title
            let detail = timer.isActive
                ? (timer.isRunning ? "מיקוד · נשארו \(FocusTimer.clock(timer.remaining(at: now)))" : "מיקוד מושהה")
                : status.detail
            let share = timer.isActive ? timer.progress(at: now) : (status.progress ?? 0)
            HStack(spacing: 10) {
                Button {
                    AppRouter.shared.isNowPlaying = true
                } label: {
                    HStack(spacing: 10) {
                        ArtworkIcon(artwork: status.artwork, symbol: timer.isActive ? "timer" : status.symbol, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(detail)
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityHint("פתיחת מסך מלא")
                Button {
                    AppRouter.shared.isQuickAdding = true
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 44)
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
