import SwiftData
import SwiftUI

/// The one thing that is "playing" now: a part of the schedule, a daily
/// pillar such as Shacharit, or a task. Chosen by the app, or by the user.
struct OnDeck {
    enum Target {
        case schedule(ScheduleItem)
        case habit(Habit)
        case task(ListItem)
        case none
    }

    let target: Target
    let title: String
    let detail: String
    let symbol: String
    let artwork: Artwork
    var progress: Double?
    /// A sensible length for a focus session on it.
    var minutes = 25
    var isPinned = false

    var canComplete: Bool {
        if case .none = target { return false }
        return true
    }
}

@MainActor
enum Deck {
    private static let key = "deck.pin"

    /// "kind|id|day": what the user chose to put on the bar today.
    private static var pin: (kind: String, id: String)? {
        let parts = AppRouter.shared.deckPin.split(separator: "|").map(String.init)
        guard parts.count == 3, parts[2] == DayKey.of() else { return nil }
        return (parts[0], parts[1])
    }

    static func setPin(kind: String, id: String) {
        AppRouter.shared.deckPin = "\(kind)|\(id)|\(DayKey.of())"
        UserDefaults.standard.set(AppRouter.shared.deckPin, forKey: key)
    }

    static func clearPin() {
        AppRouter.shared.deckPin = ""
        UserDefaults.standard.removeObject(forKey: key)
    }

    static var savedPin: String { UserDefaults.standard.string(forKey: key) ?? "" }

    static func current(items: [ScheduleItem], habits: [Habit], tasks: [ListItem], now: Date = .now) -> OnDeck {
        let minute = ScheduleItem.minute(of: now)
        let list = NowStatus.today(items, on: now)
        let openHabits = habits.filter { !$0.removed && !$0.isDone(on: now) }.sorted { $0.order < $1.order }
        // Shabbat and the festivals have no tasks to offer.
        let isRest: Bool = JewishDay.of(now).isRest
        let cue: DayJournal.Intention? = isRest ? nil : DayJournal.intention
        var todays: [ListItem] = isRest ? [] : DayPlan.ordered(tasks.filter { !$0.isDone && !$0.removed && $0.isForToday })
        if let cue, let index = todays.firstIndex(where: { $0.id == cue.taskID }) {
            todays.insert(todays.remove(at: index), at: 0)
        }

        if let pin {
            switch pin.kind {
            case "schedule":
                if let item = list.first(where: { $0.id == pin.id && !$0.isDone(on: now) }) {
                    var deck = schedule(item, minute: minute)
                    deck.isPinned = true
                    return deck
                }
            case "habit":
                if let habit = openHabits.first(where: { $0.id == pin.id }) {
                    return OnDeck(target: .habit(habit), title: habit.title, detail: "בחרתם · מקביעות היום",
                                  symbol: habit.symbol, artwork: habit.artwork, minutes: 20, isPinned: true)
                }
            default:
                if let task = tasks.first(where: { $0.id == pin.id && !$0.isDone && !$0.removed }) {
                    return OnDeck(target: .task(task), title: task.title, detail: "בחרתם · מטלה",
                                  symbol: "checklist", artwork: Theme.emerald,
                                  minutes: DayJournal.estimate(task), isPinned: true)
                }
            }
        }

        // The first step the family set for today comes up at its minute.
        if let cue, minute >= cue.minute - 2, minute <= cue.minute + 90, let task = todays.first, task.id == cue.taskID {
            let spot: String = cue.place.isEmpty ? "" : " · " + cue.place
            return OnDeck(target: .task(task), title: task.title, detail: "הזמן שקבעתם" + spot,
                          symbol: "figure.walk", artwork: Theme.violet, minutes: DayJournal.estimate(task))
        }

        if let current = list.first(where: { $0.startMinute <= minute && minute < $0.endMinute && !$0.isDone(on: now) }) {
            // Time that is theirs to fill shows the task that fills it.
            if current.holdsTasks, let task = todays.first {
                return OnDeck(target: .task(task), title: task.title, detail: "בזמן \(current.title) · המטלה הבאה",
                              symbol: "checklist", artwork: Theme.emerald, minutes: DayJournal.estimate(task))
            }
            return schedule(current, minute: minute)
        }
        let next = list.first { $0.startMinute > minute && !$0.isDone(on: now) }
        if let next, next.startMinute - minute <= 30 {
            return schedule(next, minute: minute)
        }
        if let task = todays.first {
            let more = todays.count - 1
            return OnDeck(target: .task(task), title: task.title,
                          detail: more > 0 ? "המטלה הבאה · ועוד \(more) להיום" : "המטלה הבאה שלך",
                          symbol: "checklist", artwork: Theme.emerald, minutes: DayJournal.estimate(task))
        }
        if let habit = openHabits.first, minute < 23 * 60 {
            return OnDeck(target: .habit(habit), title: habit.title,
                          detail: openHabits.count == 1 ? "האחרון מקביעות היום" : "מקביעות היום · נשארו \(openHabits.count)",
                          symbol: habit.symbol, artwork: habit.artwork, minutes: 20)
        }
        if let next {
            return schedule(next, minute: minute)
        }
        if list.isEmpty && habits.isEmpty {
            return OnDeck(target: .none, title: "היום פנוי", detail: "הקישו כדי לבנות את היום",
                          symbol: "sparkles", artwork: Theme.emerald)
        }
        return OnDeck(target: .none, title: "היום הושלם", detail: "כל הכבוד. מחר ממשיכים.",
                      symbol: "moon.stars.fill", artwork: Theme.violet)
    }

    private static func schedule(_ item: ScheduleItem, minute: Int) -> OnDeck {
        if item.startMinute <= minute && minute < item.endMinute {
            let share = Double(minute - item.startMinute) / Double(max(item.durationMinutes, 1))
            return OnDeck(target: .schedule(item), title: item.title,
                          detail: "עכשיו · נשארו \(NowStatus.duration(item.endMinute - minute))",
                          symbol: item.symbol, artwork: item.artwork, progress: share,
                          minutes: max(item.endMinute - minute, 1))
        }
        if item.startMinute > minute {
            return OnDeck(target: .schedule(item), title: item.title,
                          detail: "בעוד \(NowStatus.duration(item.startMinute - minute)) · \(ScheduleItem.clock(item.startMinute))",
                          symbol: item.symbol, artwork: item.artwork, minutes: item.durationMinutes)
        }
        return OnDeck(target: .schedule(item), title: item.title, detail: "הסתיים ב־\(ScheduleItem.clock(item.endMinute)) · לסמן?",
                      symbol: item.symbol, artwork: item.artwork, minutes: item.durationMinutes)
    }

    /// Marks what is on the bar as done and lets the next thing come up.
    static func complete(_ deck: OnDeck, in context: ModelContext) {
        // A celebration brings its own sound; otherwise the usual chime.
        var celebrated = false
        switch deck.target {
        case .schedule(let item):
            item.setDone(true)
            try? context.save()
            SharedSync.shared.changed(in: context)
            celebrated = ScheduleItem.celebrateIfDayDone(in: context)
        case .habit(let habit):
            if !habit.isDone() { habit.toggle() }
            try? context.save()
            celebrated = Habit.celebrateIfDayFull(in: context)
        case .task(let task):
            celebrated = TaskRules.setDone(task, true, in: context)
        case .none:
            return
        }
        if deck.isPinned { clearPin() }
        if FocusTimer.shared.isActive, FocusTimer.shared.title == deck.title { FocusTimer.shared.stop() }
        if !celebrated { Feedback.done() }
    }
}
