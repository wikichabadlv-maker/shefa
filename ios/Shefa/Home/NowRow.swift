import SwiftData
import SwiftUI

/// What this moment asks for, at the top of the home screen: a routine that
/// is being played, one that has to begin soon, the day's first step, the
/// hours before the candles, the day's two sittings. At most three, each one
/// tap away from the thing itself, and nothing at all when the moment asks
/// for nothing.
struct NowRow: View {
    @Binding var selection: AppTab
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" && !$0.removed },
           sort: \ListItem.createdAt, order: .reverse)
    private var items: [ListItem]
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }) private var schedule: [ScheduleItem]
    @State private var router = AppRouter.shared
    @State private var run = RoutineRun.shared
    @State private var store = Routines.shared
    @State private var feed = CalendarFeed.shared

    private struct Tile: Identifiable {
        let id: String
        /// The small line above the title: what kind of moment this is.
        let kicker: String
        let title: String
        let detail: String
        let symbol: String
        let artwork: Artwork
        let action: () -> Void
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            // The board of the eve and a routine's steps change between ticks.
            let _ = store.turn
            let _ = run.index
            let _ = router.weekTurn
            let list: [Tile] = tiles(now: timeline.date)
            if !list.isEmpty {
                row(list)
                    .padding(.top, 22)
                    .transition(.sectionSwap)
            }
        }
    }

    // MARK: What is shown

    private func tiles(now: Date) -> [Tile] {
        var result: [Tile] = []
        let minute: Int = ScheduleItem.minute(of: now)
        // Shabbat and the festivals ask for nothing here, from candle
        // lighting until they are out.
        guard !Notifier.isHolyTime(now) else { return [] }
        let open: [ListItem] = items.filter { !$0.isDone }

        if let routine = run.routine, let step = run.step {
            let left: Int = run.remaining(at: now)
            var time: String = "מעבר לזמן, וזה בסדר"
            if left >= 60 {
                time = "נשארו \(NowStatus.duration(left / 60))"
            } else if left >= 0 {
                time = "עוד רגע מסתיים"
            }
            result.append(Tile(id: "run", kicker: "\(routine.title) · צעד \(run.index + 1) מתוך \(routine.steps.count)",
                               title: step.title, detail: time, symbol: routine.symbol, artwork: routine.artwork,
                               action: { router.isRoutinePlaying = true }))
        } else {
            // A routine that has to begin soon so as to end by its hour.
            let played: Set<String> = RoutineRun.played(on: now)
            for routine in store.all where !routine.isForCandles && !played.contains(routine.id) {
                guard let start = routine.startBy(on: now), let goal = routine.goalMinute,
                      minute >= start - 45, minute <= start + 20 else { continue }
                let when: String = minute >= start ? "להתחיל עכשיו" : "להתחיל עד \(ScheduleItem.clock(start))"
                result.append(Tile(id: "routine-" + routine.id, kicker: "כדי לסיים עד \(ScheduleItem.clock(goal))",
                                   title: "\(routine.title): \(when)", detail: routine.summary,
                                   symbol: routine.symbol, artwork: routine.artwork,
                                   action: { RoutineRun.play(routine, in: context) }))
                break
            }
        }

        // The first step, from half an hour before the minute the family set.
        if let cue = DayJournal.intention, minute >= cue.minute - 30, minute <= cue.minute + 90,
           let task = open.first(where: { $0.id == cue.taskID }) {
            let place: String = cue.place.isEmpty ? "" : " · " + cue.place
            let isEarly: Bool = minute < cue.minute - 2
            let when: String = minute < cue.minute ? "ב־\(ScheduleItem.clock(cue.minute))" : "זו השעה שקבעתם"
            let taskID: String = task.id
            result.append(Tile(id: "cue", kicker: "הצעד הראשון של היום", title: task.title, detail: when + place,
                               symbol: "figure.walk", artwork: Theme.violet,
                               action: {
                                   // Ahead of its minute the bar still shows something else.
                                   if isEarly { Deck.setPin(kind: "task", id: taskID) }
                                   router.isNowPlaying = true
                               }))
        }

        if let board = ErevBoard.make(now: now, routine: store.forCandles), board.untilCandles > 0 {
            var detail: String = "בעוד \(NowStatus.duration(board.untilCandles))"
            if board.left > 0 {
                detail += " · נשארו \(NowStatus.duration(board.left)) של הכנות"
            } else if !board.lines.isEmpty {
                detail += " · הכול מוכן"
            }
            result.append(Tile(id: "erev", kicker: board.towards,
                               title: "הדלקת נרות ב־\(ScheduleItem.clock(board.candlesMinute))", detail: detail,
                               symbol: "flame.fill", artwork: ErevCard.artwork,
                               action: { selection = .schedule }))
        }

        guard result.count < 3 else { return Array(result.prefix(3)) }

        // The two sittings, and what stands between them, go by the day's plan.
        let plan: DayPlan = DayPlan.make(day: now, tasks: items, schedule: schedule, events: feed.on(now), now: now)
        let hasDone: Bool = items.contains { item in
            guard item.isDone, let date = item.doneAt else { return false }
            return Calendar.current.isDate(date, inSameDayAs: now)
        }
        // A new week is asked about once, on its first day or the evening before it.
        let weekday: Int = Calendar.current.component(.weekday, from: now)
        if WeekFocus.offers(now: now), weekday == 1 || weekday == 7 {
            result.append(Tile(id: "week", kicker: weekday == 7 ? "שבוע חדש בפתח" : "שבוע חדש",
                               title: "שלושה דברים לשבוע",
                               detail: "בוחרים שלושה, ולא יותר: מה שאם ייעשה, זה יהיה שבוע טוב.",
                               symbol: "target", artwork: WeekCard.artwork,
                               action: { router.isPickingWeek = true }))
        }
        let canPlan: Bool = plan.offersPlanning(minute: minute, hasOpen: !open.isEmpty)
        if canPlan {
            // After a day of rest is out, what is left to build is its evening.
            let isOut: Bool = plan.kind.isRest
            var kicker: String = minute < 12 * 60 ? "בוקר טוב" : "היום עוד פתוח"
            if isOut { kicker = plan.kind.outName }
            result.append(Tile(id: "plan", kicker: kicker,
                               title: isOut ? "בונים את הערב" : "בונים את היום",
                               detail: isOut ? "דקה אחת: מה נכנס הערב, ומה הצעד הראשון."
                                   : "דקה אחת: מה נכנס היום, ומה הצעד הראשון.",
                               symbol: isOut ? "moon.stars.fill" : "sun.max.fill", artwork: Theme.blue,
                               action: { router.isPlanningDay = true }))
        }
        if plan.offersClosing(minute: minute, hasDone: hasDone) {
            // The evening sitting deals with whatever is left, so it stands alone.
            result.append(Tile(id: "close", kicker: minute >= 17 * 60 ? "ערב טוב" : "לפני שהיום נגמר",
                               title: "סוגרים את היום", detail: "דקה אחת: מה נעשה, ומה עובר למחר.",
                               symbol: "moon.stars.fill", artwork: Artwork(0x4F46E5, 0x312E81),
                               action: { router.isClosingDay = true }))
            return Array(result.prefix(3))
        }
        if plan.load == .over, !plan.tasks.isEmpty {
            let missing: Int = max(((plan.plannedMinutes - plan.roomMinutes + 4) / 5) * 5, 5)
            let title: String = plan.freeMinutes < 10 ? "לא נשאר היום זמן פנוי" : "חסרות כ־\(NowStatus.duration(missing))"
            result.append(Tile(id: "over", kicker: "היום גדוש", title: title,
                               detail: "אפשר להעביר מטלה הלאה, או לקצר אחת.",
                               symbol: "scalemass.fill", artwork: Artwork(0xD97706, 0xB45309),
                               action: { openTasks() }))
        }
        // The morning sitting asks about them itself.
        let leftovers: Int = open.filter { $0.isLeftOver && !$0.isForToday }.count
        if leftovers > 0, !canPlan {
            let title: String = leftovers == 1 ? "מטלה אחת נשארה פתוחה" : "\(leftovers) מטלות נשארו פתוחות"
            result.append(Tile(id: "left", kicker: "מיום קודם", title: title,
                               detail: "הן לא עברו להיום מעצמן. מה מהן באמת של היום?",
                               symbol: "arrow.uturn.backward", artwork: Artwork(0x0891B2, 0x155E75),
                               action: { openTasks() }))
        }
        return Array(result.prefix(3))
    }

    private func openTasks() {
        router.tasksSection = .tasks
        selection = .tasks
    }

    // MARK: How it looks

    @ViewBuilder
    private func row(_ list: [Tile]) -> some View {
        if list.count == 1, let only = list.first {
            card(only, isAlone: true)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(list) { tile in
                        card(tile, isAlone: false)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .padding(.horizontal, -16)
        }
    }

    private func card(_ tile: Tile, isAlone: Bool) -> some View {
        Button {
            Feedback.tap()
            tile.action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.kicker)
                        .font(.system(size: 12, weight: .heavy))
                        .opacity(0.88)
                        .lineLimit(1)
                    Text(tile.title)
                        .font(.system(size: 19, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(tile.detail)
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.92)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .heavy))
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(width: isAlone ? nil : 308, height: 104, alignment: .leading)
            .frame(maxWidth: isAlone ? .infinity : nil, alignment: .leading)
            .livingCard(tile.artwork, radius: 24, seed: Double(tile.id.count) * 0.17, isMoving: false)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }
}
