import SwiftData
import SwiftUI

/// The full "now playing" screen that opens from the floating bar: the part
/// of the day that is on, a focus timer, and what comes next.
struct NowPlayingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }, sort: \ScheduleItem.startMinute)
    private var allItems: [ScheduleItem]
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" && !$0.removed && !$0.isDone },
           sort: \ListItem.createdAt, order: .reverse)
    private var openTasks: [ListItem]

    @State private var timer = FocusTimer.shared
    @State private var picked: Int?
    @State private var editing: ScheduleItem?

    private var todayTasks: [ListItem] { openTasks.filter(\.isForToday) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            content(now: timeline.date)
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(item: $editing) { item in
            ScheduleEditor(item: item, draft: ScheduleDraft(item), day: .now)
        }
    }

    private struct Shown {
        let title: String
        let subtitle: String
        let symbol: String
        let artwork: Artwork
        let item: ScheduleItem?
        let isCurrent: Bool
        let minutes: Int
    }

    private func shown(list: [ScheduleItem], index: Int?, minute: Int) -> Shown {
        if let index, list.indices.contains(index) {
            let item = list[index]
            let isCurrent = item.startMinute <= minute && minute < item.endMinute
            let left = isCurrent ? item.endMinute - minute : item.durationMinutes
            return Shown(title: item.title, subtitle: "\(item.timeText) · \(item.daysText)", symbol: item.symbol,
                         artwork: item.artwork, item: item, isCurrent: isCurrent, minutes: max(left, 1))
        }
        if let task = todayTasks.first ?? openTasks.first {
            return Shown(title: task.title, subtitle: "המטלה הבאה שלך", symbol: "checklist",
                         artwork: Theme.emerald, item: nil, isCurrent: false,
                         minutes: task.minutes > 0 ? task.minutes : 25)
        }
        return Shown(title: "מיקוד חופשי", subtitle: "25 דקות על דבר אחד", symbol: "timer",
                     artwork: Theme.violet, item: nil, isCurrent: false, minutes: 25)
    }

    private func defaultIndex(_ list: [ScheduleItem], minute: Int) -> Int? {
        if let current = list.firstIndex(where: { $0.startMinute <= minute && minute < $0.endMinute }) { return current }
        if let next = list.firstIndex(where: { $0.startMinute > minute }) { return next }
        return list.isEmpty ? nil : list.count - 1
    }

    private func content(now: Date) -> some View {
        let minute = ScheduleItem.minute(of: now)
        let list = NowStatus.today(allItems, on: now)
        let index = picked ?? defaultIndex(list, minute: minute)
        let item = shown(list: list, index: index, minute: minute)
        let focusOn = timer.isActive
        let isLive = focusOn ? timer.isRunning : item.isCurrent

        return ScrollView {
            VStack(spacing: 22) {
                Text(focusOn ? "מיקוד" : (item.isCurrent ? "עכשיו בלו״ז" : (item.item != nil ? "בלו״ז היום" : "מוכנים להתחיל?")))
                    .font(.system(size: 13, weight: .heavy))
                    .opacity(0.8)
                    .padding(.top, 26)

                artwork(item, isLive: isLive)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(focusOn ? timer.title : item.title)
                            .font(.system(size: 24, weight: .heavy))
                            .lineLimit(2)
                        Text(focusOn ? "נשארו \(FocusTimer.clock(timer.remaining(at: now)))" : item.subtitle)
                            .font(.system(size: 15, weight: .medium))
                            .opacity(0.8)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    if let real = item.item {
                        Menu {
                            Button("עריכה", systemImage: "pencil") { editing = real }
                            Button("דחייה ב־15 דקות", systemImage: "clock.arrow.circlepath") { push(real, by: 15) }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.18), in: Circle())
                        }
                        .accessibilityLabel("אפשרויות")
                    }
                }

                progress(item, now: now, minute: minute)

                controls(item, list: list, index: index, now: now)

                actions(item)

                queue(list: list, index: index, minute: minute)
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 40)
            .foregroundStyle(.white)
        }
        .scrollIndicators(.hidden)
        .background {
            LinearGradient(colors: [item.artwork.start, item.artwork.end, Color(hex: 0x0B1220)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: item.title)
        }
        .presentationBackground(Color(hex: 0x0B1220))
    }

    private func artwork(_ item: Shown, isLive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Image(systemName: item.symbol)
                    .font(.system(size: 110, weight: .bold))
                    .symbolEffect(.pulse, isActive: isLive)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 300)
            .scaleEffect(isLive ? 1 : 0.84)
            .shadow(color: .black.opacity(0.3), radius: 30, y: 18)
            .animation(.spring(duration: 0.5, bounce: 0.35), value: isLive)
            .accessibilityHidden(true)
    }

    private func progress(_ item: Shown, now: Date, minute: Int) -> some View {
        var share = 0.0
        var leading = "0:00"
        var trailing = NowStatus.duration(item.minutes)
        if timer.isActive {
            share = timer.progress(at: now)
            leading = FocusTimer.clock(timer.total - timer.remaining(at: now))
            trailing = "−" + FocusTimer.clock(timer.remaining(at: now))
        } else if item.isCurrent, let real = item.item {
            let seconds = now.timeIntervalSince(Calendar.current.startOfDay(for: now)) - Double(real.startMinute) * 60
            share = min(max(seconds / Double(max(real.durationMinutes, 1) * 60), 0), 1)
            leading = FocusTimer.clock(max(seconds, 0))
            trailing = "−" + FocusTimer.clock(max(Double(real.durationMinutes) * 60 - seconds, 0))
        }
        return VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white)
                        .frame(width: max(proxy.size.width * share, share > 0 ? 8 : 0))
                }
            }
            .frame(height: 7)
            .environment(\.layoutDirection, .leftToRight)
            HStack {
                Text(leading)
                Spacer()
                Text(trailing)
            }
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .opacity(0.8)
            .environment(\.layoutDirection, .leftToRight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("התקדמות")
        .accessibilityValue("\(Int(share * 100)) אחוזים")
    }

    private func controls(_ item: Shown, list: [ScheduleItem], index: Int?, now: Date) -> some View {
        HStack(spacing: 44) {
            Button {
                step(-1, list: list, index: index)
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30))
                    .frame(width: 56, height: 56)
            }
            .disabled((index ?? 0) <= 0)
            .accessibilityLabel("הקודם")

            Button {
                if timer.isRunning {
                    timer.pause()
                } else if timer.isActive {
                    timer.resume()
                } else {
                    Task { _ = await Notifier.shared.askPermission() }
                    timer.start(title: item.title, minutes: item.minutes)
                }
                Feedback.tap()
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 46))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 84, height: 84)
            }
            .accessibilityLabel(timer.isRunning ? "השהיה" : "התחלת מיקוד")

            Button {
                step(1, list: list, index: index)
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30))
                    .frame(width: 56, height: 56)
            }
            .disabled(index == nil || (index ?? 0) >= list.count - 1)
            .accessibilityLabel("הבא")
        }
        .buttonStyle(.plain)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func actions(_ item: Shown) -> some View {
        HStack(spacing: 10) {
            if let real = item.item {
                let isDone = real.isDone()
                pill(isDone ? "בוצע" : "סימון כבוצע", isDone ? "checkmark.circle.fill" : "checkmark.circle") {
                    real.setDone(!isDone)
                    try? context.save()
                    SharedSync.shared.changed(in: context)
                    if isDone { Feedback.tap() } else { Feedback.done() }
                }
            }
            if timer.isActive {
                pill("סיום המיקוד", "stop.fill") {
                    timer.stop()
                    Feedback.tap()
                }
            }
            pill("הוספה", "bolt.fill") {
                dismiss()
                AppRouter.shared.isQuickAdding = true
            }
        }
    }

    private func pill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.white.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func queue(list: [ScheduleItem], index: Int?, minute: Int) -> some View {
        let upcoming = list.enumerated().filter { $0.element.endMinute > minute && $0.offset != index }
        return VStack(alignment: .leading, spacing: 10) {
            if !upcoming.isEmpty {
                Text("הבא בתור")
                    .font(.system(size: 18, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(upcoming, id: \.element.id) { pair in
                    Button {
                        withAnimation(.snappy) { picked = pair.offset }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pair.element.symbol)
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 42, height: 42)
                                .background(pair.element.artwork.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pair.element.title)
                                    .font(.system(size: 16, weight: .bold))
                                    .lineLimit(1)
                                Text(pair.element.timeText)
                                    .font(.system(size: 13, weight: .medium))
                                    .monospacedDigit()
                                    .opacity(0.75)
                            }
                            Spacer(minLength: 0)
                            if pair.element.isDone() {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !todayTasks.isEmpty {
                Text("המטלות של היום")
                    .font(.system(size: 18, weight: .heavy))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                ForEach(todayTasks.prefix(5)) { task in
                    Button {
                        withAnimation(.snappy) { TaskRules.setDone(task, true, in: context) }
                        Feedback.done()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle")
                                .font(.system(size: 24))
                                .frame(width: 42, height: 42)
                            Text(task.title)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("סימון כבוצע")
                }
            }
        }
        .padding(.top, 6)
    }

    private func step(_ change: Int, list: [ScheduleItem], index: Int?) {
        guard !list.isEmpty else { return }
        let next = min(max((index ?? 0) + change, 0), list.count - 1)
        withAnimation(.snappy) { picked = next }
        Feedback.tap()
    }

    /// Moves this part of the day, and everything after it today, later.
    private func push(_ item: ScheduleItem, by minutes: Int) {
        for other in NowStatus.today(allItems) where other.startMinute >= item.startMinute {
            other.startMinute += minutes
            other.updatedAt = .now
        }
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        Feedback.tap()
    }
}
