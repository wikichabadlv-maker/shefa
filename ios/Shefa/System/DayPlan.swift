import Foundation
import SwiftData

/// A stretch of the day, in minutes from midnight.
struct DaySpan: Hashable {
    var start: Int
    var end: Int

    var length: Int { max(end - start, 0) }
}

/// A fixed part of a day, for drawing the day as a strip.
struct DayBlock: Identifiable {
    let id: String
    let span: DaySpan
    let title: String
    let artwork: Artwork
    let isDone: Bool
    /// Time that is the family's own to fill, such as working hours: tasks
    /// are placed inside it.
    var isOpen = false
}

/// One of the day's tasks with the place the day has for it.
struct PlannedTask: Identifiable {
    let task: ListItem
    /// How long it is taken to need: the family's own figure, or the usual
    /// length of a task when none was given.
    let minutes: Int
    /// Where it falls when the tasks are done in order, if the day still
    /// has room for it.
    let span: DaySpan?

    var id: String { task.id }
}

/// What the app has learned about how the family's days really go: how much
/// gets done in a day, and how estimates turn out. Kept on this phone and
/// in its backup.
enum DayJournal {
    private static let logKey = "coach.planByDay"
    private static let samplesKey = "coach.taskSamples"
    private static let plannedKey = "coach.plannedDays"
    private static let closedKey = "coach.closedDays"
    private static let askedKey = "coach.closeAsked"
    private static let restKey = "coach.closeRest"
    private static let moodKey = "coach.moodByDay"
    private static let lateKey = "coach.lateDay"
    private static let intentionKey = "coach.intention"

    private static var store: UserDefaults { .standard }

    // MARK: What a day holds

    private static var log: [String: [String: Int]] {
        (store.dictionary(forKey: logKey) as? [String: [String: Int]]) ?? [:]
    }

    /// Writes down how much was planned for a day and how much of it was
    /// done, in the family's own estimates.
    static func note(planned: Int, done: Int, on day: Date = .now) {
        var all = log
        let key: String = DayKey.of(day)
        // The most that was ever on the day's plate is what was planned.
        let before: Int = all[key]?["p"] ?? 0
        all[key] = ["p": max(planned, before), "d": done]
        if all.count > 90 {
            for old in all.keys.sorted().dropLast(90) { all[old] = nil }
        }
        store.set(all, forKey: logKey)
    }

    /// What usually gets done in a day, in minutes of the family's own
    /// estimates: the middle one of the recent working days that had a
    /// plan. Nil until five such days were seen.
    static var usualMinutes: Int? {
        let today: String = DayKey.of()
        let all: [String: [String: Int]] = log
        var done: [Int] = []
        for key in all.keys.sorted() where key != today {
            guard let value = all[key], let planned = value["p"], planned > 0,
                  let date = DayKey.date(key), !JewishDay.of(date).isRest else { continue }
            done.append(value["d"] ?? 0)
        }
        // Only the last three weeks of such days speak for today.
        let recent: [Int] = Array(done.suffix(21))
        guard recent.count >= 5 else { return nil }
        let sorted: [Int] = recent.sorted()
        return sorted[sorted.count / 2]
    }

    /// What was planned for a day and what of it was done, in minutes; nil
    /// when nothing was written down for it.
    static func entry(on day: Date) -> (planned: Int, done: Int)? {
        guard let value = log[DayKey.of(day)], let planned = value["p"] else { return nil }
        return (planned, value["d"] ?? 0)
    }

    /// How many days were planned and how many of them ended with
    /// everything done, over the last two weeks.
    static var recentDays: (planned: Int, full: Int) {
        var planned = 0
        var full = 0
        let calendar = Calendar.current
        for back in 1...14 {
            guard let date = calendar.date(byAdding: .day, value: -back, to: .now),
                  let value = log[DayKey.of(date)], let goal = value["p"], goal > 0 else { continue }
            planned += 1
            if (value["d"] ?? 0) >= goal { full += 1 }
        }
        return (planned, full)
    }

    // MARK: How estimates turn out

    private static var samples: [[Int]] {
        (store.array(forKey: samplesKey) as? [[Int]]) ?? []
    }

    /// A task whose real length is known, next to what was expected; the
    /// estimate is 0 when none was given.
    static func addSample(estimate: Int, actual: Int) {
        guard actual > 0 else { return }
        var all = samples
        all.append([estimate, actual])
        store.set(Array(all.suffix(40)), forKey: samplesKey)
    }

    /// By how much a task usually outgrows its estimate. A quarter more,
    /// until the family's own tasks say otherwise.
    static var factor: Double {
        let ratios: [Double] = samples.compactMap { pair in
            guard pair.count == 2, pair[0] > 0 else { return nil }
            return Double(pair[1]) / Double(pair[0])
        }
        guard ratios.count >= 4 else { return 1.25 }
        let sorted: [Double] = ratios.sorted()
        return min(max(sorted[sorted.count / 2], 0.8), 2.5)
    }

    /// Whether the factor comes from the family's own tasks.
    static var hasLearnedFactor: Bool {
        samples.filter { $0.count == 2 && $0[0] > 0 }.count >= 4
    }

    /// What a task of this estimate usually takes, once the family's own
    /// tasks have shown it; nil while the answer would be the estimate itself.
    static func likely(for estimate: Int) -> Int? {
        guard estimate > 0, hasLearnedFactor else { return nil }
        let real: Int = Int((Double(estimate) * factor / 5).rounded()) * 5
        return real >= estimate + 5 ? real : nil
    }

    /// The length taken for a task that was given none.
    static var typicalMinutes: Int {
        let lengths: [Int] = samples.compactMap { $0.count == 2 ? $0[1] : nil }.sorted()
        guard lengths.count >= 4 else { return 30 }
        return min(max((lengths[lengths.count / 2] / 5) * 5, 10), 90)
    }

    static func estimate(_ task: ListItem) -> Int {
        task.minutes > 0 ? task.minutes : typicalMinutes
    }

    // MARK: The day's two moments

    private static func days(_ key: String) -> Set<String> {
        DayKey.split(store.string(forKey: key) ?? "")
    }

    private static func addToday(_ key: String) {
        var all: Set<String> = days(key)
        all.insert(DayKey.of())
        store.set(DayKey.join(all, keep: 60), forKey: key)
    }

    static var isPlannedToday: Bool { days(plannedKey).contains(DayKey.of()) }
    static func markPlanned() { addToday(plannedKey) }

    static var isClosedToday: Bool { days(closedKey).contains(DayKey.of()) }
    static func markClosed() { addToday(closedKey) }

    /// Writes down the evenings on which the reminder to close the day goes out.
    static func noteEveningAsked(_ evenings: [Date]) {
        let today: String = DayKey.of()
        // The days still ahead are written again by every rebuild.
        var all: Set<String> = days(askedKey).filter { $0 < today }
        for day in evenings { all.insert(DayKey.of(day)) }
        store.set(DayKey.join(all, keep: 30), forKey: askedKey)
    }

    /// The reminder to close the day rests for a week after three evenings
    /// in a row on which it went out and the day was left open. Then it
    /// tries again.
    static func eveningRests(now: Date = .now) -> Bool {
        let today: String = DayKey.of(now)
        let until: String = store.string(forKey: restKey) ?? ""
        if !until.isEmpty && today <= until { return true }
        let closed: Set<String> = days(closedKey)
        let asked: [String] = days(askedKey).filter { $0 < today && $0 > until }.sorted()
        let last: [String] = Array(asked.suffix(3))
        guard last.count == 3, !last.contains(where: { closed.contains($0) }) else { return false }
        let end: Date = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        store.set(DayKey.of(end), forKey: restKey)
        return true
    }

    /// The family accepted that today ends late, so the day stays open
    /// until half past eleven.
    static var acceptsLateToday: Bool { store.string(forKey: lateKey) == DayKey.of() }
    static func acceptLate() { store.set(DayKey.of(), forKey: lateKey) }

    // MARK: The first step

    /// Where and when the family said it will begin: "at 9:45, by the desk,
    /// I start with the call". Said in advance, it is far likelier to happen.
    struct Intention: Codable, Equatable {
        var day: String
        var taskID: String
        var minute: Int
        var place: String
    }

    /// Today's first step, when one was set.
    static var intention: Intention? {
        guard let text = store.string(forKey: intentionKey), let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Intention.self, from: data),
              value.day == DayKey.of() else { return nil }
        return value
    }

    static func setIntention(_ value: Intention?) {
        guard let value, let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            store.removeObject(forKey: intentionKey)
            return
        }
        store.set(text, forKey: intentionKey)
    }

    /// How the day felt, from 1 (heavy) to 3 (good).
    static func mood(on day: Date = .now) -> Int? {
        (store.dictionary(forKey: moodKey) as? [String: Int])?[DayKey.of(day)]
    }

    static func setMood(_ value: Int, on day: Date = .now) {
        var all = (store.dictionary(forKey: moodKey) as? [String: Int]) ?? [:]
        all[DayKey.of(day)] = value
        if all.count > 120 {
            for old in all.keys.sorted().dropLast(120) { all[old] = nil }
        }
        store.set(all, forKey: moodKey)
    }
}

/// The honest picture of one day: how much room it really has between its
/// fixed parts, and what was planned into that room.
struct DayPlan {
    enum Load {
        /// Shabbat or a festival: nothing is planned.
        case rest
        /// The working day is over.
        case closed
        case empty, light, full, over
    }

    let day: Date
    let kind: JewishDay
    let isToday: Bool
    /// No work on this day, or at this hour of it: Shabbat or a festival,
    /// from candle lighting on its eve until it is out. The evening after
    /// it is a working evening again.
    let isHoly: Bool
    /// The minute the working day closes: the evening hour the family
    /// chose, or an hour before candle lighting.
    let closing: Int
    /// The free stretches left until the closing.
    let free: [DaySpan]
    let freeMinutes: Int
    /// What fits, counted in the family's own estimates: the free time
    /// brought down by how estimates turn out.
    let roomMinutes: Int
    /// What a usual day of theirs holds, once enough days were seen.
    let usualMinutes: Int?
    let tasks: [PlannedTask]
    /// The day's fixed parts and timed events, for the strip.
    let blocks: [DayBlock]
    /// The estimates of the open tasks, added up.
    let plannedMinutes: Int
    /// The estimates of what was already done today.
    let doneMinutes: Int
    /// The family closed the day in the evening sitting.
    var isClosed = false

    var unplaced: [PlannedTask] { tasks.filter { $0.span == nil } }

    var share: Double {
        guard roomMinutes > 0 else { return plannedMinutes > 0 ? 1.5 : 0 }
        return Double(plannedMinutes) / Double(roomMinutes)
    }

    var load: Load {
        if isHoly { return .rest }
        if plannedMinutes == 0 { return isToday && (freeMinutes < 10 || isClosed) ? .closed : .empty }
        if freeMinutes < 10 { return .over }
        if share > 1.12 || !unplaced.isEmpty { return .over }
        return share >= 0.85 ? .full : .light
    }

    /// When the last task ends, if they all fit.
    var finish: Int? {
        guard unplaced.isEmpty else { return nil }
        return tasks.compactMap { $0.span?.end }.max()
    }

    /// The first open task in the order of the day.
    var first: PlannedTask? { tasks.first }

    // MARK: Building

    /// When a day that has not begun yet is taken to open.
    static let opening = 8 * 60

    static func closing(day: Date, kind: JewishDay, isOut: Bool = false) -> Int {
        // A day of rest has no working hours, until it is out.
        if kind.isRest && !isOut { return 0 }
        var limit: Int = Coach.eveningMinute ?? (21 * 60 + 30)
        if Calendar.current.isDateInToday(day), DayJournal.acceptsLateToday { limit = 23 * 60 + 30 }
        if kind.hasCandles, let candles = Zmanim(day: day).list.first(where: { $0.id == "candles" }) {
            limit = min(limit, ScheduleItem.minute(of: candles.date) - 60)
        }
        return max(limit, 0)
    }

    /// The first day after the given one that is not Shabbat or a festival.
    static func nextWorkDay(after day: Date = .now) -> Date {
        let calendar = Calendar.current
        var next: Date = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        var guardCount = 0
        while JewishDay.of(next).isRest, guardCount < 6 {
            next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
            guardCount += 1
        }
        return next
    }

    /// How a coming day is called from today: "מחר", or the name of its day.
    static func name(ofComing day: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let ahead: Int = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                 to: calendar.startOfDay(for: day)).day ?? 1
        if ahead <= 0 { return "היום" }
        return ahead == 1 ? "מחר" : HebrewDate.weekday(day)
    }

    /// What is left of the stretch between two minutes once the busy parts
    /// are taken out. Scraps shorter than ten minutes are not counted.
    static func free(from opening: Int, to closing: Int, busy: [DaySpan]) -> [DaySpan] {
        guard closing > opening else { return [] }
        var result: [DaySpan] = []
        var cursor: Int = opening
        for span in busy.sorted(by: { $0.start < $1.start }) {
            if span.end <= cursor { continue }
            if span.start >= closing { break }
            if span.start > cursor { result.append(DaySpan(start: cursor, end: min(span.start, closing))) }
            // The next stretch begins on a round five minutes: a fixed part
            // may end at a minute of its own, such as one tied to sunset.
            cursor = max(cursor, ((span.end + 4) / 5) * 5)
            if cursor >= closing { break }
        }
        if cursor < closing { result.append(DaySpan(start: cursor, end: closing)) }
        return result.filter { $0.length >= 10 }
    }

    /// The order in which the day's tasks are taken: what is late first,
    /// then what matters, then what is due sooner.
    static func ordered(_ tasks: [ListItem]) -> [ListItem] {
        tasks.sorted { first, second in
            let one: Int = (first.isOverdue ? 0 : 2) - first.priority
            let two: Int = (second.isOverdue ? 0 : 2) - second.priority
            if one != two { return one < two }
            let early: Date = first.due ?? .distantFuture
            let late: Date = second.due ?? .distantFuture
            if early != late { return early < late }
            return first.createdAt < second.createdAt
        }
    }

    /// The tasks that belong to a day: today's own, or, for a coming day,
    /// the ones due on it or already chosen for it.
    static func belonging(_ tasks: [ListItem], to day: Date, now: Date = .now) -> [ListItem] {
        let calendar = Calendar.current
        let open: [ListItem] = tasks.filter { !$0.isDone && !$0.removed && $0.kind == ListItem.task }
        if calendar.isDate(day, inSameDayAs: now) { return open.filter(\.isForToday) }
        let key: String = DayKey.of(day)
        return open.filter { item in
            if item.todayDay == key { return true }
            guard let due = item.due else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }
    }

    /// `chosen` replaces the day's own tasks, for trying a plan before it is
    /// written. The task of the first step is placed at the minute set for it.
    static func make(day: Date = .now, tasks: [ListItem], schedule: [ScheduleItem], events: [DayEvent] = [],
                     now: Date = .now, chosen: [ListItem]? = nil,
                     intention: DayJournal.Intention? = DayJournal.intention) -> DayPlan {
        let calendar = Calendar.current
        let isToday: Bool = calendar.isDate(day, inSameDayAs: now)
        let kind: JewishDay = JewishDay.of(day)
        let isHoly: Bool = isToday ? Notifier.isHolyTime(now) : kind.isRest
        let closing: Int = DayPlan.closing(day: day, kind: kind, isOut: !isHoly)
        let opening: Int = isToday ? ((ScheduleItem.minute(of: now) + 4) / 5) * 5 : DayPlan.opening

        var busy: [DaySpan] = []
        var blocks: [DayBlock] = []
        for item in NowStatus.today(schedule, on: day) {
            let span = DaySpan(start: item.start(on: day), end: item.end(on: day))
            let isDone: Bool = item.isDone(on: day)
            // A part that was finished early gives its time back, and time
            // that is theirs to fill was never taken.
            if !isDone, !item.holdsTasks { busy.append(span) }
            blocks.append(DayBlock(id: item.id, span: span, title: item.title, artwork: item.artwork,
                                   isDone: isDone, isOpen: item.holdsTasks))
        }
        for event in events where !event.isAllDay && !event.isBirthday {
            let start: Int = calendar.isDate(event.start, inSameDayAs: day) ? ScheduleItem.minute(of: event.start) : 0
            let end: Int = calendar.isDate(event.end, inSameDayAs: day) ? ScheduleItem.minute(of: event.end) : 24 * 60
            guard end > start else { continue }
            let span = DaySpan(start: start, end: end)
            busy.append(span)
            blocks.append(DayBlock(id: event.id, span: span, title: event.title,
                                   artwork: Artwork(0x64748B, 0x334155), isDone: false))
        }
        let free: [DaySpan] = isHoly ? [] : DayPlan.free(from: opening, to: closing, busy: busy)
        let freeMinutes: Int = free.reduce(0) { $0 + $1.length }

        let factor: Double = DayJournal.factor
        let room: Int = Int((Double(freeMinutes) / factor).rounded(.down))
        let usual: Int? = DayJournal.usualMinutes

        var order: [ListItem] = DayPlan.ordered(chosen ?? DayPlan.belonging(tasks, to: day, now: now))
        // The task the family said it will begin with leads the day.
        let cue: DayJournal.Intention? = isToday ? intention : nil
        if let cue, let index = order.firstIndex(where: { $0.id == cue.taskID }) {
            order.insert(order.remove(at: index), at: 0)
        }

        var windows: [DaySpan] = free
        var placed: [PlannedTask] = []
        var planned = 0
        for task in order {
            let minutes: Int = DayJournal.estimate(task)
            planned += minutes
            let onClock: Int = max(Int((Double(minutes) * factor / 5).rounded(.up)) * 5, 5)
            var from: Int = (cue?.taskID == task.id ? cue?.minute : nil) ?? 0
            var index: Int? = windows.firstIndex(where: { $0.end - max($0.start, from) >= onClock })
            if index == nil, from > 0 {
                // The minute that was set has no room any more: the next one that has.
                from = 0
                index = windows.firstIndex(where: { $0.length >= onClock })
            }
            var span: DaySpan?
            if let index {
                let whole: DaySpan = windows[index]
                let start: Int = max(whole.start, from)
                span = DaySpan(start: start, end: start + onClock)
                var rest: [DaySpan] = []
                if start - whole.start >= 10 { rest.append(DaySpan(start: whole.start, end: start)) }
                if whole.end - (start + onClock) >= 5 { rest.append(DaySpan(start: start + onClock, end: whole.end)) }
                windows.replaceSubrange(index...index, with: rest)
            }
            placed.append(PlannedTask(task: task, minutes: minutes, span: span))
        }

        var done = 0
        if isToday {
            for task in tasks where task.isDone && !task.removed && task.kind == ListItem.task {
                guard let date = task.doneAt, calendar.isDate(date, inSameDayAs: now) else { continue }
                done += DayJournal.estimate(task)
            }
        }

        return DayPlan(day: day, kind: kind, isToday: isToday, isHoly: isHoly, closing: closing, free: free,
                       freeMinutes: freeMinutes, roomMinutes: room, usualMinutes: usual,
                       tasks: placed, blocks: blocks.sorted { $0.span.start < $1.span.start },
                       plannedMinutes: planned, doneMinutes: done,
                       isClosed: isToday && DayJournal.isClosedToday)
    }

    // MARK: The day's two sittings

    /// Whether the morning sitting is worth offering at this minute: a
    /// working day that was not built yet, with something to build it from.
    func offersPlanning(minute: Int, hasOpen: Bool) -> Bool {
        !isHoly && load != .closed && !DayJournal.isPlannedToday && hasOpen
            && (minute < 13 * 60 || tasks.isEmpty)
    }

    /// Whether the evening sitting is worth offering at this minute: from an
    /// hour and a half before the day closes, when there is something to look back on.
    func offersClosing(minute: Int, hasDone: Bool) -> Bool {
        !isHoly && !DayJournal.isClosedToday && (minute >= closing - 90 || load == .closed)
            && (hasDone || !tasks.isEmpty)
    }

    // MARK: In words

    /// One sentence that says how the day stands.
    var sentence: String {
        let planned: String = NowStatus.duration(plannedMinutes)
        // Said in round numbers: the room is an estimate.
        let room: String = NowStatus.duration((roomMinutes / 5) * 5)
        switch load {
        case .rest:
            // The rest that is on, and the last day of it: work waits for that one to be out.
            let rest: JewishDay = kind.isRest ? kind : kind.next
            var last: JewishDay = rest
            for _ in 0..<3 where last.next.isRest { last = last.next }
            let after: String = last.outName
            if kind.isRest { return "\(rest.restName) היום. המטלות מחכות ל\(after)." }
            return (rest.isShabbat ? "שבת נכנסה." : "החג נכנס.") + " המטלות מחכות ל\(after)."
        case .closed:
            return "יום העבודה נסגר. מה שנשאר עובר למחר."
        case .empty:
            if freeMinutes < 10 { return "אין ביום הזה זמן פנוי למטלות." }
            let when: String = isToday ? "היום עוד" : "ביום הזה"
            return "יש \(when) מקום לכ־\(room) של מטלות."
        case .light, .full:
            if let finish {
                return "\(planned) של מטלות, ויש להן מקום. הסיום ב־\(ScheduleItem.clock(finish)) בערך."
            }
            return "\(planned) של מטלות, ויש להן מקום."
        case .over:
            if freeMinutes < 10 { return "תוכננו \(planned), ולא נשאר היום זמן פנוי." }
            return "תוכננו \(planned), ויש מקום לכ־\(room)."
        }
    }

    /// The view from outside: what a usual day of theirs holds, said only
    /// when today asks for clearly more than that.
    var habitNote: String? {
        guard let usual = usualMinutes, usual >= 20 else { return nil }
        let asked: Int = plannedMinutes + doneMinutes
        guard Double(asked) > Double(usual) * 1.3 else { return nil }
        return "ביום רגיל אתם מסיימים כ־\(NowStatus.duration(usual)) של מטלות. להיום תוכננו \(NowStatus.duration(asked))."
    }

    /// The name next to "today": the day's own, and once a day of rest is
    /// out, that of the evening after it.
    var dayName: String? {
        guard kind.isRest, !isHoly else { return kind.title }
        return kind.outName
    }

    /// The name of the rest that is on: the day's own, or, from candle
    /// lighting on its eve, that of the day that has come in.
    var restTitle: String {
        (kind.isRest ? kind : kind.next).title ?? "שבת קודש"
    }

    /// What closes the working day, when it is not simply the evening.
    var closingNote: String? {
        guard kind.hasCandles, !kind.isRest else { return nil }
        return "היום נסגר ב־\(ScheduleItem.clock(closing)), שעה לפני הדלקת הנרות."
    }
}

extension TaskRules {
    /// Brings the day's journal up to date with what is planned and done.
    static func noteDay(in context: ModelContext) {
        let all: [ListItem] = (try? context.fetch(FetchDescriptor<ListItem>(
            predicate: #Predicate<ListItem> { $0.kind == "task" && !$0.removed }))) ?? []
        let calendar = Calendar.current
        var planned = 0
        var done = 0
        for task in all {
            if task.isDone {
                guard let date = task.doneAt, calendar.isDateInToday(date) else { continue }
                done += DayJournal.estimate(task)
                planned += DayJournal.estimate(task)
            } else if task.isForToday {
                planned += DayJournal.estimate(task)
            }
        }
        DayJournal.note(planned: planned, done: done)
    }

    /// Once a day: every open task that was meant for an earlier day and
    /// was not done is counted as put off once more. A task chosen for a
    /// day that has passed keeps a mark of it, so the morning can ask again.
    static func carryOver(in context: ModelContext, now: Date = .now) {
        // A day of rest is not a day that was missed.
        guard !JewishDay.of(now).isRest else { return }
        let today: String = DayKey.of(now)
        let start: Date = Calendar.current.startOfDay(for: now)
        let open: [ListItem] = (try? context.fetch(FetchDescriptor<ListItem>(
            predicate: #Predicate<ListItem> { $0.kind == "task" && !$0.removed && !$0.isDone }))) ?? []
        var changed = false
        for task in open where task.pushedDay != today {
            let pick: String = task.todayDay
            let wasPicked: Bool = !pick.isEmpty && !pick.hasPrefix(ListItem.leftMark) && pick < today
            let isLate: Bool = (task.due ?? .distantFuture) < start
            guard wasPicked || isLate else { continue }
            task.pushed += 1
            task.pushedDay = today
            if wasPicked { task.todayDay = ListItem.leftMark + pick }
            task.updatedAt = now
            changed = true
        }
        guard changed else { return }
        try? context.save()
        SharedSync.shared.changed(in: context)
    }

    /// Moves a task by the family's own choice: to the next working day, or
    /// back to the list with no day. Leaving today counts as putting off.
    static func putOff(_ task: ListItem, toTomorrow: Bool, in context: ModelContext, now: Date = .now) {
        let today: String = DayKey.of(now)
        if task.isForToday || task.isLeftOver, task.pushedDay != today {
            task.pushed += 1
            task.pushedDay = today
        }
        task.todayDay = ""
        if toTomorrow {
            task.due = DayPlan.nextWorkDay(after: now)
        } else if let due = task.due, due < Calendar.current.startOfDay(for: now).addingTimeInterval(86_400) {
            // A day that has come is taken off; a day still ahead stays.
            task.due = nil
        }
        task.updatedAt = now
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        noteDay(in: context)
    }

    /// Chooses a task for a day, or takes the choice back.
    static func pick(_ task: ListItem, for day: Date = .now, _ isOn: Bool = true, in context: ModelContext) {
        task.todayDay = isOn ? DayKey.of(day) : ""
        task.updatedAt = .now
        try? context.save()
        SharedSync.shared.changed(in: context)
        noteDay(in: context)
    }

    /// A task that keeps being put off is too big as it stands: its first
    /// small step becomes a task of its own for today, and the rest waits.
    static func breakDown(_ task: ListItem, firstStep: String, in context: ModelContext) {
        let name: String = firstStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let step = ListItem(kind: ListItem.task, title: name)
        step.todayDay = DayKey.of()
        step.minutes = 10
        step.note = "צעד ראשון של: " + task.title
        context.insert(step)
        task.todayDay = ""
        task.due = nil
        task.pushed = 0
        task.updatedAt = .now
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        noteDay(in: context)
    }

    /// Gives a task a shorter length, when the day is too full for all of it.
    static func trim(_ task: ListItem, to minutes: Int, in context: ModelContext) {
        task.minutes = minutes
        task.updatedAt = .now
        try? context.save()
        SharedSync.shared.changed(in: context)
        noteDay(in: context)
    }

    /// Starts working on a task: it goes up on the floating bar, the timer
    /// runs for its length, and the full screen opens.
    static func start(_ task: ListItem) {
        Deck.setPin(kind: "task", id: task.id)
        FocusTimer.shared.start(title: task.title, minutes: DayJournal.estimate(task), taskID: task.id)
        Task { _ = await Notifier.shared.askPermission() }
        AppRouter.shared.isNowPlaying = true
        Feedback.tap()
    }

    /// Keeps the task for today in a smaller form.
    static func shorten(_ task: ListItem, to minutes: Int, in context: ModelContext) {
        task.minutes = minutes
        task.pushed = 0
        task.todayDay = DayKey.of()
        task.updatedAt = .now
        try? context.save()
        SharedSync.shared.changed(in: context)
        noteDay(in: context)
    }

    /// Lets a task go for good, in peace.
    static func release(_ task: ListItem, in context: ModelContext) {
        task.removed = true
        task.updatedAt = .now
        try? context.save()
        SharedSync.shared.changed(in: context)
        Notifier.shared.refresh(in: context)
        noteDay(in: context)
    }
}
