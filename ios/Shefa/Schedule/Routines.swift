import Foundation
import Observation

/// A fixed run of short steps, played one after another like a playlist:
/// a morning, an evening, the hours before Shabbat.
struct Routine: Codable, Identifiable, Equatable, Hashable {
    struct Step: Codable, Identifiable, Equatable, Hashable {
        var id: String = UUID().uuidString
        var title: String
        var minutes: Int
    }

    var id: String = UUID().uuidString
    var title: String
    var symbol: String = "play.fill"
    var palette: Int = 0
    var steps: [Step] = []
    /// The minute of the day by which it should be over, when there is one.
    var goalMinute: Int?
    /// It leads up to candle lighting, on the days that have one.
    var isForCandles: Bool = false
    /// The days of the week it is meant for: bit 0 is Sunday. Shabbat and
    /// the festivals never count.
    var weekdays: Int = ScheduleItem.weekdaysMask
    /// Says when it is time to begin, so as to be done in time.
    var reminds: Bool = false
    /// While it is played, a short signal says when a step's time is up.
    /// Not for a routine with a prayer in it.
    var rings: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, symbol, palette, steps, goalMinute, isForCandles, weekdays, reminds, rings
    }

    var minutes: Int {
        var sum = 0
        for step in steps { sum += step.minutes }
        return sum
    }

    var artwork: Artwork {
        SavingsGoal.palettes[abs(palette) % SavingsGoal.palettes.count]
    }

    /// The latest minute to begin and still be done by the goal.
    var latestStart: Int? {
        guard let goalMinute else { return nil }
        return max(goalMinute - minutes, 0)
    }

    /// Whether it is meant for a given day. Never on Shabbat or a festival,
    /// and the one that leads up to the candles on their eves alone.
    func isOn(_ day: Date) -> Bool {
        let kind: JewishDay = JewishDay.of(day)
        if kind.isRest { return false }
        // The eve of Yom Kippur has an order of its own.
        if isForCandles { return kind.isEve && kind.next.fast == nil }
        return weekdays & (1 << (kind.weekday - 1)) != 0
    }

    /// Minutes of what is still to be done on a given day.
    func left(on day: Date = .now) -> Int {
        guard isForCandles else { return minutes }
        let finished: Set<String> = ErevBoard.done(on: day)
        var sum = 0
        for step in steps where !finished.contains(step.id) { sum += step.minutes }
        return sum
    }

    /// The latest minute to begin on a given day and still be done in time:
    /// by the candles for the one that leads up to them, by the goal for
    /// the others. Nil on a day it is not meant for, or with nothing to do.
    func startBy(on day: Date) -> Int? {
        guard isOn(day) else { return nil }
        if isForCandles {
            let open: Int = left(on: day)
            guard open > 0, let candles = Zmanim(day: day).list.first(where: { $0.id == "candles" }) else { return nil }
            return max(ScheduleItem.minute(of: candles.date) - open, 0)
        }
        guard let goalMinute, minutes > 0 else { return nil }
        return max(goalMinute - minutes, 0)
    }

    /// For example "ימים א׳ עד ו׳".
    var daysText: String {
        let mask: Int = weekdays & ScheduleItem.weekdaysMask
        if mask == ScheduleItem.weekdaysMask { return "ימים א׳ עד ו׳" }
        if mask == 0b0011111 { return "ימים א׳ עד ה׳" }
        let letters: [String] = (0..<6).filter { mask & (1 << $0) != 0 }.map { ScheduleItem.dayLetters[$0] + "׳" }
        return letters.isEmpty ? "בלי ימים" : "ימי " + letters.joined(separator: ", ")
    }

    /// What is still to be played today: for the hours before candle
    /// lighting, the steps that were not marked as done yet.
    func remaining(on day: Date = .now) -> Routine {
        guard isForCandles else { return self }
        let finished: Set<String> = ErevBoard.done(on: day)
        let open: [Step] = steps.filter { !finished.contains($0.id) }
        guard !open.isEmpty else { return self }
        var copy: Routine = self
        copy.steps = open
        return copy
    }

    /// For example "4 צעדים · 1:45 שעות".
    var summary: String {
        let count: String = steps.count == 1 ? "צעד אחד" : "\(steps.count) צעדים"
        return "\(count) · \(NowStatus.duration(minutes))"
    }
}

extension Routine {
    /// Reads a saved routine. Anything a later version added may be missing
    /// from what an earlier one wrote, and then keeps its usual value.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(title: try box.decodeIfPresent(String.self, forKey: .title) ?? "")
        if let value = try box.decodeIfPresent(String.self, forKey: .id) { id = value }
        if let value = try box.decodeIfPresent(String.self, forKey: .symbol) { symbol = value }
        if let value = try box.decodeIfPresent(Int.self, forKey: .palette) { palette = value }
        if let value = try box.decodeIfPresent([Step].self, forKey: .steps) { steps = value }
        goalMinute = try box.decodeIfPresent(Int.self, forKey: .goalMinute)
        if let value = try box.decodeIfPresent(Bool.self, forKey: .isForCandles) { isForCandles = value }
        if let value = try box.decodeIfPresent(Int.self, forKey: .weekdays) { weekdays = value }
        if let value = try box.decodeIfPresent(Bool.self, forKey: .reminds) { reminds = value }
        if let value = try box.decodeIfPresent(Bool.self, forKey: .rings) { rings = value }
    }
}

/// The family's routines, kept on this phone and carried in its backup.
@Observable
final class Routines {
    static let shared = Routines()
    private static let key = "coach.routines"

    private(set) var all: [Routine] = []
    /// Rises when a step of the eve's board is marked, so that every screen
    /// that shows the board counts it again.
    private(set) var turn = 0

    private init() { load() }

    func noteBoardChanged() { turn += 1 }

    func load() {
        guard let text = UserDefaults.standard.string(forKey: Self.key), let data = text.data(using: .utf8),
              let saved = try? JSONDecoder().decode([Routine].self, from: data) else {
            all = []
            return
        }
        all = saved
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: Self.key)
    }

    func put(_ routine: Routine) {
        if let index = all.firstIndex(where: { $0.id == routine.id }) {
            all[index] = routine
        } else {
            all.append(routine)
        }
        save()
    }

    func remove(_ id: String) {
        all.removeAll { $0.id == id }
        save()
    }

    /// The one that leads up to candle lighting.
    var forCandles: Routine? { all.first { $0.isForCandles } }

    /// Ready-made beginnings, each fully editable once added.
    static let templates: [Routine] = [
        Routine(id: "template-morning", title: "בוקר", symbol: "sunrise.fill", palette: 4, steps: [
            Routine.Step(title: "מקווה", minutes: 20),
            Routine.Step(title: "שחרית", minutes: 50),
            Routine.Step(title: "חת״ת", minutes: 20),
            Routine.Step(title: "ארוחת בוקר", minutes: 15),
        ]),
        Routine(id: "template-out", title: "יציאה מהבית", symbol: "figure.walk", palette: 0, steps: [
            Routine.Step(title: "להעיר ולהלביש", minutes: 20),
            Routine.Step(title: "ארוחת בוקר", minutes: 15),
            Routine.Step(title: "תיקים ואוכל", minutes: 10),
            Routine.Step(title: "נעליים ויוצאים", minutes: 5),
        ], goalMinute: 7 * 60 + 45, rings: true),
        Routine(id: "template-evening", title: "ערב", symbol: "moon.stars.fill", palette: 7, steps: [
            Routine.Step(title: "לסדר את הבית", minutes: 10),
            Routine.Step(title: "להכין את מחר: בגדים ותיקים", minutes: 10),
            Routine.Step(title: "לסגור את היום", minutes: 2),
            Routine.Step(title: "קריאת שמע שעל המיטה", minutes: 10),
        ]),
        Routine(id: "template-erev", title: "ערב שבת", symbol: "flame.fill", palette: 6, steps: [
            Routine.Step(title: "קניות אחרונות", minutes: 30),
            Routine.Step(title: "בישולים", minutes: 90),
            Routine.Step(title: "לסדר ולנקות את הבית", minutes: 45),
            Routine.Step(title: "פלטה, מיחם ושעון שבת", minutes: 10),
            Routine.Step(title: "מקלחות ובגדי שבת", minutes: 40),
            Routine.Step(title: "לערוך את השולחן ולהכין את הנרות", minutes: 10),
            Routine.Step(title: "צדקה לפני הדלקת הנרות", minutes: 2),
        ], isForCandles: true, reminds: true, rings: true),
    ]

    /// A copy of a template that is the family's own from now on.
    func add(template: Routine) -> Routine {
        var copy: Routine = template
        copy.id = UUID().uuidString
        var steps: [Routine.Step] = []
        for step in template.steps { steps.append(Routine.Step(title: step.title, minutes: step.minutes)) }
        copy.steps = steps
        put(copy)
        return copy
    }
}

/// A routine that is being played now: which step, and since when.
@Observable
final class RoutineRun {
    static let shared = RoutineRun()
    private static let key = "routine.run"

    private struct Saved: Codable {
        var routine: Routine
        var index: Int
        var startedAt: Date
        var stepStartedAt: Date
    }

    private(set) var routine: Routine?
    private(set) var index = 0
    private(set) var startedAt: Date = .now
    private(set) var stepStartedAt: Date = .now

    private static let playedKey = "routine.played"

    /// The routines that were begun today, so that none is offered again.
    static func played(on day: Date = .now) -> Set<String> {
        let parts: [String] = (UserDefaults.standard.string(forKey: playedKey) ?? "").components(separatedBy: "|")
        guard parts.count == 2, parts[0] == DayKey.of(day) else { return [] }
        return Set(parts[1].split(separator: ",").map(String.init))
    }

    private static func notePlayed(_ id: String, on day: Date) {
        var all: Set<String> = played(on: day)
        all.insert(id)
        UserDefaults.standard.set(DayKey.of(day) + "|" + all.sorted().joined(separator: ","), forKey: playedKey)
    }

    private init() {
        // A run that was cut short by the app closing goes on, within reason.
        guard let text = UserDefaults.standard.string(forKey: Self.key), let data = text.data(using: .utf8),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.routine.steps.indices.contains(saved.index) else { return }
        routine = saved.routine
        index = saved.index
        startedAt = saved.startedAt
        stepStartedAt = saved.stepStartedAt
        dropIfStale()
    }

    /// A run that was left behind long ago is let go: two hours after the
    /// time of its step was up, nobody is in the middle of it any more.
    func dropIfStale(now: Date = .now) {
        guard let step else { return }
        if now.timeIntervalSince(stepStartedAt) > Double(step.minutes * 60) + 2 * 3600 { stop() }
    }

    private func keep() {
        signal()
        guard let routine else {
            UserDefaults.standard.removeObject(forKey: Self.key)
            return
        }
        let saved = Saved(routine: routine, index: index, startedAt: startedAt, stepStartedAt: stepStartedAt)
        guard let data = try? JSONEncoder().encode(saved), let text = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(text, forKey: Self.key)
    }

    /// Sets the signal for the end of the step that is on, when the routine
    /// asks for one, and takes away the one that was set before.
    private func signal() {
        guard let routine, let step, routine.rings else {
            Notifier.cancelStepEnd()
            return
        }
        let end: Date = stepStartedAt.addingTimeInterval(Double(step.minutes * 60))
        var body: String = "זה הצעד האחרון של \(routine.title)."
        if let following { body = "אחר כך: \(following.title) · \(NowStatus.duration(following.minutes))." }
        if routine.isForCandles, JewishDay.of(end).isEve,
           let candles = Zmanim(day: end).list.first(where: { $0.id == "candles" }) {
            let left: Int = Int(candles.date.timeIntervalSince(end) / 60)
            if left > 0 { body += " נשארו \(NowStatus.duration(left)) עד הדלקת הנרות." }
        }
        Notifier.scheduleStepEnd(at: end, title: step.title + " · הזמן עבר", body: body)
    }

    /// A little more time for the step that is on, counted from now.
    func extend(minutes: Int, now: Date = .now) {
        guard var changed = routine, changed.steps.indices.contains(index) else { return }
        let spent: Int = Int((now.timeIntervalSince(stepStartedAt) / 60).rounded(.up))
        changed.steps[index].minutes = max(changed.steps[index].minutes, spent) + minutes
        routine = changed
        keep()
    }

    /// "12:05", and "1:30:00" from an hour up.
    static func clock(_ seconds: Int) -> String {
        let whole: Int = abs(seconds)
        if whole >= 3600 { return String(format: "%d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60) }
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    var isActive: Bool { routine != nil }

    var step: Routine.Step? {
        guard let routine, routine.steps.indices.contains(index) else { return nil }
        return routine.steps[index]
    }

    /// The step after the current one.
    var following: Routine.Step? {
        guard let routine, routine.steps.indices.contains(index + 1) else { return nil }
        return routine.steps[index + 1]
    }

    func start(_ routine: Routine, now: Date = .now) {
        guard !routine.steps.isEmpty else { return }
        self.routine = routine
        index = 0
        startedAt = now
        stepStartedAt = now
        keep()
        RoutineRun.notePlayed(routine.id, on: now)
    }

    /// Ends the current step, done or skipped, and moves on; returns true
    /// when that was the last one and the routine is over.
    func finish(done: Bool, now: Date = .now) -> Bool {
        if done, let routine, let step, routine.isForCandles {
            // The board of the hours before Shabbat hears of it too.
            ErevBoard.setDone(step.id, true, on: now)
        }
        return next(now: now)
    }

    private func next(now: Date = .now) -> Bool {
        guard let routine else { return true }
        if index + 1 >= routine.steps.count {
            stop()
            return true
        }
        index += 1
        stepStartedAt = now
        keep()
        return false
    }

    func back(now: Date = .now) {
        guard routine != nil, index > 0 else { return }
        index -= 1
        stepStartedAt = now
        keep()
    }

    func stop() {
        routine = nil
        index = 0
        keep()
    }

    /// Seconds left of the current step; below zero once it ran over.
    func remaining(at now: Date = .now) -> Int {
        guard let step else { return 0 }
        return step.minutes * 60 - Int(now.timeIntervalSince(stepStartedAt))
    }

    /// From 0 to 1 through the current step.
    func progress(at now: Date = .now) -> Double {
        guard let step, step.minutes > 0 else { return 0 }
        return min(max(now.timeIntervalSince(stepStartedAt) / Double(step.minutes * 60), 0), 1)
    }

    /// When the whole routine ends if every step that is left takes its time.
    func end(at now: Date = .now) -> Date {
        guard let routine else { return now }
        var seconds: Int = max(remaining(at: now), 0)
        for step in routine.steps.dropFirst(index + 1) { seconds += step.minutes * 60 }
        return now.addingTimeInterval(Double(seconds))
    }

    /// Minutes since the routine began.
    func elapsed(at now: Date = .now) -> Int {
        max(Int(now.timeIntervalSince(startedAt) / 60), 0)
    }
}

/// The hours before candle lighting, seen honestly: what is still to be
/// done, by when each thing has to begin, and whether it all fits.
struct ErevBoard {
    struct Line: Identifiable {
        let id: String
        let title: String
        let minutes: Int
        /// The latest minute of the day to begin it; nil once it is done.
        let latest: Int?
        var isDone: Bool { latest == nil }
    }

    let day: Date
    let candles: Date
    let lines: [Line]
    /// Minutes of what is still to be done.
    let left: Int
    /// Minutes from now until the candles; below zero once they were lit.
    let untilCandles: Int
    /// The Chanukah light that comes before the Shabbat candles today.
    let chanukahCandle: Int?
    /// What is wished once the candles are lit.
    let greeting: String

    /// Room to spare when above zero; what is missing when below.
    var slack: Int { untilCandles - left }

    var candlesMinute: Int { ScheduleItem.minute(of: candles) }

    private static let doneKey = "coach.erevDone"

    /// The steps marked as done today.
    static func done(on day: Date = .now) -> Set<String> {
        let parts: [String] = (UserDefaults.standard.string(forKey: doneKey) ?? "").components(separatedBy: "|")
        guard parts.count == 2, parts[0] == DayKey.of(day) else { return [] }
        return Set(parts[1].split(separator: ",").map(String.init))
    }

    static func setDone(_ id: String, _ isDone: Bool, on day: Date = .now) {
        var all: Set<String> = done(on: day)
        if isDone { all.insert(id) } else { all.remove(id) }
        UserDefaults.standard.set(DayKey.of(day) + "|" + all.sorted().joined(separator: ","), forKey: doneKey)
        Routines.shared.noteBoardChanged()
    }

    /// The board for a working day that ends in candle lighting; nil on any
    /// other day. Without a routine of the family's own it shows the candles alone.
    static func make(now: Date = .now, routine: Routine? = Routines.shared.forCandles) -> ErevBoard? {
        let kind: JewishDay = JewishDay.of(now)
        guard kind.isEve, let zman = Zmanim(day: now).list.first(where: { $0.id == "candles" }) else { return nil }
        let finished: Set<String> = done(on: now)
        // The eve of Yom Kippur has an order of its own.
        let steps: [Routine.Step] = kind.next.fast != nil ? [] : (routine?.steps ?? [])
        // Counted back from the candles: the last thing ends as they are lit.
        var deadline: Int = ScheduleItem.minute(of: zman.date)
        var latest: [String: Int] = [:]
        var left = 0
        for step in steps.reversed() where !finished.contains(step.id) {
            deadline -= step.minutes
            latest[step.id] = max(deadline, 0)
            left += step.minutes
        }
        var lines: [Line] = []
        for step in steps {
            lines.append(Line(id: step.id, title: step.title, minutes: step.minutes, latest: latest[step.id]))
        }
        let until: Int = Int((zman.date.timeIntervalSince(now) / 60).rounded(.down))
        // On Chanukah the Chanukah light is kindled before the Shabbat candles.
        let chanukah: Int? = kind.next.isShabbat ? kind.chanukahCandle : nil
        return ErevBoard(day: now, candles: zman.date, lines: lines, left: left, untilCandles: until,
                         chanukahCandle: chanukah, greeting: kind.next.greeting)
    }

    /// The eve as it is called: "ערב שבת קודש", "ערב חג הפסח".
    var eveName: String {
        let coming: JewishDay = JewishDay.of(day).next
        guard let yomTov = coming.yomTov else { return "ערב שבת קודש" }
        return coming.isShabbat ? "ערב שבת ו" + yomTov : "ערב " + yomTov
    }

    /// What the day is turned to: "לקראת שבת", "לקראת החג".
    var towards: String {
        let coming: JewishDay = JewishDay.of(day).next
        guard let yomTov = coming.yomTov else { return "לקראת שבת" }
        if coming.fast != nil || yomTov == "ראש השנה" { return "לקראת " + yomTov }
        return coming.isShabbat ? "לקראת שבת וחג" : "לקראת החג"
    }

    /// One honest line about how the time stands; empty when the family
    /// has no list of its own to measure the time against.
    var verdict: String {
        if untilCandles <= 0 { return greeting + "." }
        if lines.isEmpty { return "" }
        if left == 0 { return "הכול מוכן. נשארו \(NowStatus.duration(untilCandles)) של שקט." }
        let work: String = NowStatus.duration(left)
        if slack >= 15 { return "נשארו \(work) של הכנות, ויש להן מקום: מרווח של \(NowStatus.duration((slack / 5) * 5))." }
        if slack >= 0 { return "נשארו \(work) של הכנות, בדיוק במידה. כדאי להתחיל עכשיו." }
        return "נשארו \(work) של הכנות, וחסרות \(NowStatus.duration(((-slack + 4) / 5) * 5)). מה אפשר לקצר, לחלק או לוותר עליו?"
    }

    /// Whether the time is short, said without alarm.
    var isTight: Bool { untilCandles > 0 && left > 0 && slack < 0 }
}
