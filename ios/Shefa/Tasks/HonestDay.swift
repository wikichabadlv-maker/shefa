import SwiftData
import SwiftUI

/// Understands a task typed in one line, such as "להתקשר לביטוח מחר 20 דק׳ !".
/// Only the end of the line is read as instructions, so a word such as
/// "מחר" inside the task's own name stays there.
enum TaskParser {
    struct Result {
        var title = ""
        /// Days from today, when a day was named.
        var day: Int?
        var minutes: Int?
        var isImportant = false
    }

    private static let days = ["היום": 0, "מחר": 1, "מחרתיים": 2]
    private static let weekdays = ["ראשון": 1, "שני": 2, "שלישי": 3, "רביעי": 4, "חמישי": 5, "שישי": 6]
    private static let minuteWords: Set<String> = ["דק", "דק׳", "דק'", "דקות", "דקה"]
    /// After these words a day belongs to the task's name: "השיעור של מחר".
    private static let blockers: Set<String> = ["של", "על", "את", "לקראת", "אחרי", "לפני", "עם"]

    static func parse(_ text: String, now: Date = .now) -> Result {
        var words: [String] = text.split(separator: " ").map(String.init)
        var result = Result()
        var found = true
        while found, !words.isEmpty {
            found = false
            let last: String = words[words.count - 1]
            let before: String = words.count >= 2 ? words[words.count - 2] : ""
            if last == "!" {
                result.isImportant = true
                words.removeLast()
                found = true
            } else if last.count > 1, last.hasSuffix("!") {
                result.isImportant = true
                words[words.count - 1] = String(last.dropLast())
                found = true
            } else if result.minutes == nil, let length = minutes(before, last) {
                result.minutes = length.value
                words.removeLast(length.used)
                found = true
            } else if result.day == nil, let when = day(before, last, now: now) {
                result.day = when.value
                words.removeLast(when.used)
                found = true
            }
        }
        result.title = words.joined(separator: " ")
        return result
    }

    private static func minutes(_ before: String, _ last: String) -> (value: Int, used: Int)? {
        if minuteWords.contains(last), let number = Int(before), number > 0 { return (number, 2) }
        if last == "שעות" || last == "שעה", let number = Int(before), number > 0 { return (number * 60, 2) }
        if last == "שעה", before == "חצי" { return (30, 2) }
        if last == "שעה", before == "רבע" { return (15, 2) }
        if last == "וחצי", before == "שעה" { return (90, 2) }
        if last == "שעתיים" { return (120, 1) }
        return nil
    }

    private static func day(_ before: String, _ last: String, now: Date) -> (value: Int, used: Int)? {
        if let value = days[last] {
            if blockers.contains(before) { return nil }
            return (value, before == "עד" ? 2 : 1)
        }
        if let target = weekdays[last], before == "ביום" || before == "יום" {
            let today: Int = Calendar.current.component(.weekday, from: now)
            let ahead: Int = (target - today + 7) % 7
            return (ahead == 0 ? 7 : ahead, 2)
        }
        return nil
    }
}

/// What a row can do beyond being ticked and opened.
struct TaskActions {
    var start: () -> Void
    var tomorrow: () -> Void
    var later: () -> Void
    var flag: () -> Void
    var stuck: () -> Void
    var delete: () -> Void
}

/// The honest picture of today at the top of the tasks: a ring of what was
/// planned against the room the day really has, and when it all ends.
struct DayRingHero: View {
    let plan: DayPlan
    /// How many tasks were finished today.
    let doneCount: Int
    var now: Date = .now
    var start: ((ListItem) -> Void)?
    var planDay: (() -> Void)?
    var closeDay: (() -> Void)?

    private var openCount: Int { plan.tasks.count }

    private var artwork: Artwork {
        switch plan.load {
        case .rest, .closed: return Theme.violet
        case .over: return Theme.amber
        case .empty: return doneCount > 0 ? Theme.emerald : Theme.blue
        case .light, .full: return Theme.blue
        }
    }

    private var headline: String {
        switch plan.load {
        case .rest: return plan.kind.title ?? "שבת קודש"
        case .closed: return doneCount > 0 ? "היום הושלם" : "היום נסגר"
        case .empty: return doneCount > 0 ? "היום הושלם" : "מה חשוב היום?"
        case .over: return "לא הכול נכנס"
        case .light, .full:
            if let finish = plan.finish { return "סיום ב־\(ScheduleItem.clock(finish))" }
            return openCount == 1 ? "מטלה אחת להיום" : "\(openCount) מטלות להיום"
        }
    }

    private var line: String {
        switch plan.load {
        case .empty where doneCount > 0, .closed where doneCount > 0:
            return "כל מה שתוכנן להיום נעשה. מחר ממשיכים."
        case .empty where plan.freeMinutes >= 10:
            return plan.sentence + " בחרו מעט, והתחילו מהקטנה ביותר."
        case .light, .full:
            let planned: String = NowStatus.duration(plan.plannedMinutes)
            let spare: Int = ((plan.roomMinutes - plan.plannedMinutes) / 5) * 5
            if spare >= 20 { return "\(planned) של מטלות. נשאר מקום לעוד כ־\(NowStatus.duration(spare))." }
            return "\(planned) של מטלות, במידה של היום."
        default:
            return plan.sentence
        }
    }

    var body: some View {
        let showsMap: Bool = plan.load != .rest && !(plan.blocks.isEmpty && plan.tasks.isEmpty)
        let note: String? = plan.load == .rest ? nil : (plan.closingNote ?? plan.habitNote)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("היום")
                            .font(.system(size: 15, weight: .semibold))
                            .opacity(0.9)
                        if let title = plan.kind.title, plan.load != .rest {
                            badge(title, symbol: nil)
                        }
                        if doneCount > 0, openCount > 0 {
                            badge("\(doneCount)", symbol: "checkmark")
                        }
                    }
                    Text(headline)
                        .font(.system(size: 30, weight: .heavy))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(line)
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.92)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                ring
            }
            if showsMap {
                DayMap(plan: plan, now: now, isOnColor: true)
            }
            if let note {
                Label(note, systemImage: "info.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .foregroundStyle(.white)
        .padding(20)
        .livingCard(artwork, seed: 0.4)
        .animation(.smooth(duration: 0.5), value: artwork)
        .animation(.smooth(duration: 0.4), value: plan.plannedMinutes)
    }

    private func badge(_ text: String, symbol: String?) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .heavy))
            }
            Text(text)
                .font(.system(size: 12, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.white.opacity(0.2), in: Capsule())
    }

    private var ring: some View {
        let share: Double = plan.load == .rest ? 0 : plan.share
        return ZStack {
            ProgressRing(share: min(share, 1), lineWidth: 10)
            if share > 1 {
                // What does not fit goes around a second time, in gold.
                ProgressRing(share: min(share - 1, 1), lineWidth: 10, track: .clear, fill: Color(hex: 0xFDE68A))
            }
            center
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var center: some View {
        switch plan.load {
        case .rest:
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 28, weight: .heavy))
        case .closed, .empty:
            Image(systemName: doneCount > 0 ? "checkmark" : "sun.max.fill")
                .font(.system(size: 28, weight: .heavy))
        case .light, .full, .over:
            VStack(spacing: -2) {
                Text(DayRingHero.short(plan.plannedMinutes))
                    .font(.system(size: 22, weight: .heavy))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("מתוך " + DayRingHero.short(plan.roomMinutes))
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .opacity(0.85)
            }
        }
    }

    /// A length short enough for the middle of a ring: "45׳" or "1:30".
    static func short(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(minutes, 0))׳" }
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    @ViewBuilder
    private var actions: some View {
        let first: ListItem? = plan.load == .rest || plan.load == .closed ? nil : plan.first?.task
        let canStart: Bool = first != nil && start != nil
        if canStart || planDay != nil || closeDay != nil {
            HStack(spacing: 8) {
                if let first, let start {
                    pill("התחלה: " + first.title, symbol: "play.fill", isMain: true, isWide: true) { start(first) }
                }
                if let planDay {
                    pill("בונים את היום", symbol: "sun.max.fill", isMain: !canStart, isWide: !canStart, action: planDay)
                }
                if let closeDay {
                    pill("סוגרים את היום", symbol: "moon.stars.fill", isMain: !canStart, isWide: !canStart,
                         action: closeDay)
                }
            }
        }
    }

    private func pill(_ title: String, symbol: String, isMain: Bool, isWide: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .heavy))
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(isMain ? artwork.end : Color.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: isWide ? .infinity : nil)
            .frame(height: 40)
            .background(isMain ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.2)), in: Capsule())
        }
        .buttonStyle(.pressable)
        // The long one gives way; the short ones keep their words.
        .layoutPriority(isWide ? 0 : 1)
    }
}

/// The day as a strip, from its first hour to its last: the fixed parts in
/// their own colors, the tasks where they fall, and the minute it is now.
struct DayMap: View {
    let plan: DayPlan
    var now: Date = .now
    var height: CGFloat = 22
    /// On a colorful ground the strip is drawn in white.
    var isOnColor = false
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var range: DaySpan {
        let starts: [Int] = plan.blocks.map(\.span.start) + plan.tasks.compactMap { $0.span?.start }
        let ends: [Int] = plan.blocks.map(\.span.end) + [plan.closing]
        let from: Int = min(starts.min() ?? 8 * 60, 8 * 60)
        let to: Int = max(ends.max() ?? 21 * 60, from + 180)
        return DaySpan(start: (from / 60) * 60, end: min(((to + 59) / 60) * 60, 24 * 60))
    }

    var body: some View {
        let whole: DaySpan = range
        let total: CGFloat = CGFloat(max(whole.length, 1))
        let isOpen: Bool = arrived || reduceMotion
        let ink: Color = isOnColor ? Color.white : Color.primary
        let middle: Int = ((whole.start + whole.end) / 2 / 30) * 30
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width: CGFloat = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(isOnColor ? Color.white.opacity(0.16) : Theme.chip)
                    ForEach(Array(plan.blocks.enumerated()), id: \.element.id) { index, block in
                        let fill: AnyShapeStyle = isOnColor
                            ? AnyShapeStyle(Color.white.opacity(block.isDone ? 0.3 : 0.55))
                            : AnyShapeStyle(block.artwork.gradient.opacity(block.isDone ? 0.4 : 1))
                        piece(block.span, range: whole, total: total, width: width, fill: fill)
                            .scaleEffect(x: isOpen ? 1 : 0.001, y: 1, anchor: .leading)
                            .animation(.smooth(duration: 0.5).delay(0.15 + 0.05 * Double(min(index, 8))), value: arrived)
                    }
                    ForEach(Array(plan.tasks.enumerated()), id: \.element.id) { index, task in
                        if let span = task.span {
                            let fill: AnyShapeStyle = isOnColor
                                ? AnyShapeStyle(Color(hex: 0xFDE68A)) : AnyShapeStyle(Theme.accent)
                            piece(span, range: whole, total: total, width: width, fill: fill)
                                .scaleEffect(x: isOpen ? 1 : 0.001, y: 1, anchor: .leading)
                                .animation(.smooth(duration: 0.5).delay(0.4 + 0.05 * Double(min(index, 8))), value: arrived)
                        }
                    }
                    if plan.isToday {
                        let minute: Int = ScheduleItem.minute(of: now)
                        if minute > whole.start, minute < whole.end {
                            Capsule()
                                .fill(ink)
                                .frame(width: 2.5, height: height)
                                .offset(x: width * CGFloat(minute - whole.start) / total - 1.25)
                        }
                    }
                }
            }
            .frame(height: height)
            HStack {
                Text(ScheduleItem.clock(whole.start))
                Spacer()
                Text(ScheduleItem.clock(middle))
                Spacer()
                Text(ScheduleItem.clock(whole.end))
            }
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(ink.opacity(0.7))
        }
        // Time runs left to right, as on a clock's own strip.
        .environment(\.layoutDirection, .leftToRight)
        .animation(.smooth(duration: 0.4), value: plan.plannedMinutes)
        .accessibilityHidden(true)
    }

    private func piece(_ span: DaySpan, range: DaySpan, total: CGFloat, width: CGFloat,
                       fill: AnyShapeStyle) -> some View {
        let from: Int = min(max(span.start, range.start), range.end)
        let to: Int = min(max(span.end, range.start), range.end)
        let length: CGFloat = max(width * CGFloat(to - from) / total - 2, 3)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .frame(width: length, height: height - 8)
            .offset(x: width * CGFloat(from - range.start) / total + 1)
    }
}

/// Shown when the day holds more than fits. There are three ways out, and
/// nothing moves until one of them is chosen.
struct OverloadCard: View {
    let plan: DayPlan
    let moveToTomorrow: (ListItem) -> Void
    let trim: (ListItem, Int) -> Void
    /// Missing when the day cannot be stretched, as on a Friday.
    let acceptLate: (() -> Void)?

    /// The task that would hurt least to move: the last in the day's order
    /// that is not late already.
    private var movable: ListItem? {
        plan.tasks.last(where: { !$0.task.isOverdue && $0.task.priority == 0 })?.task ?? plan.tasks.last?.task
    }

    /// The longest task gains the most from a smaller version.
    private var longest: PlannedTask? {
        plan.tasks.filter { $0.minutes >= 20 }.max { $0.minutes < $1.minutes }
    }

    var body: some View {
        let missing: Int = max(((plan.plannedMinutes - plan.roomMinutes + 4) / 5) * 5, 5)
        let tomorrow: String = DayPlan.name(ofComing: DayPlan.nextWorkDay())
        let text: String = plan.freeMinutes < 10
            ? "לא נשאר היום זמן פנוי. אפשר להחליט עכשיו מה עובר הלאה."
            : "חסרות כ־\(NowStatus.duration(missing)). עדיף להחליט עכשיו מאשר לגלות בערב."
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: Theme.amber, symbol: "scalemass.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("היום גדוש")
                        .font(.system(size: 17, weight: .heavy))
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 8) {
                if let movable {
                    option("ל\(tomorrow): " + movable.title, symbol: "sunrise.fill") { moveToTomorrow(movable) }
                }
                if let longest {
                    let half: Int = max((longest.minutes / 2 / 5) * 5, 10)
                    option("לקצר ל־\(NowStatus.duration(half)): " + longest.task.title, symbol: "scissors") {
                        trim(longest.task, half)
                    }
                }
                if let acceptLate {
                    option("לקבל סיום מאוחר היום", symbol: "moon.fill", action: acceptLate)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func option(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.amberInk)
                    .frame(width: 30)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(Theme.amberGround, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

/// Tasks that were chosen for a day that has passed. They did not move to
/// today by themselves; the family is asked once which of them belong to it.
struct LeftoverCard: View {
    let tasks: [ListItem]
    let toToday: (ListItem) -> Void
    let later: (ListItem) -> Void
    let untangle: (ListItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("נשארו מיום קודם")
                    .font(.system(size: 22, weight: .heavy))
                Text("\(tasks.count)")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            Text("הן לא עברו להיום מעצמן. מה מהן באמת של היום?")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(2)
                            if task.isStuck {
                                Button {
                                    untangle(task)
                                } label: {
                                    Label("נדחתה \(task.pushed) פעמים. מה תקוע?", systemImage: "hourglass")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Theme.amberInk)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        Spacer(minLength: 4)
                        small("אחר כך", isMain: false) { later(task) }
                        small("היום", isMain: true) { toToday(task) }
                    }
                    .frame(minHeight: 56)
                    if task.id != tasks.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
        }
    }

    private func small(_ title: String, isMain: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .foregroundStyle(isMain ? Theme.amberInk : Color.primary)
                .background(isMain ? Theme.amberGround : Theme.chip, in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// A task that was put off again and again gets three ways to move: break
/// it down, make it smaller, or let it go.
struct StuckSheet: View {
    let task: ListItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var step = ""
    @FocusState private var isTyping: Bool

    private static let stone = Artwork(0x57534E, 0x292524)

    var body: some View {
        let times: String = task.pushed == 1 ? "פעם אחת" : "\(task.pushed) פעמים"
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("נדחתה \(times)", systemImage: "hourglass")
                            .font(.system(size: 13, weight: .heavy))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(.white.opacity(0.2), in: Capsule())
                        Text(task.title)
                            .font(.system(size: 26, weight: .heavy))
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                            .padding(.top, 6)
                        Text("מטלה שלא זזה היא בדרך כלל גדולה מדי, או שכבר אינה נחוצה. יש שלוש דרכים להזיז אותה.")
                            .font(.system(size: 14, weight: .medium))
                            .opacity(0.92)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.white)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .livingCard(Theme.amber, seed: 0.3, watermark: "hourglass")
                    .cascade(0)

                    way("לפרק", "מה הצעד הראשון, של עשר דקות? רק הוא ייכנס להיום, והשאר יחכה.",
                        symbol: "square.split.2x1.fill", artwork: Theme.violet) {
                        HStack(spacing: 8) {
                            TextField("למשל: למצוא את מספר הטלפון", text: $step)
                                .focused($isTyping)
                                .submitLabel(.done)
                                .onSubmit { breakDown() }
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button {
                                breakDown()
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.violet.gradient, in: Circle())
                            }
                            .buttonStyle(.pressable)
                            .disabled(step.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityLabel("הוספת הצעד להיום")
                        }
                    }
                    .cascade(1)

                    way("לקצר", "גרסה קטנה שלה, עוד היום. חלק קטן שנעשה שווה יותר ממטלה שלמה שמחכה.",
                        symbol: "scissors", artwork: Theme.blue) {
                        HStack(spacing: 8) {
                            ForEach([10, 15, 20], id: \.self) { minutes in
                                Button {
                                    TaskRules.shorten(task, to: minutes, in: context)
                                    Feedback.done()
                                    dismiss()
                                } label: {
                                    Text(NowStatus.duration(minutes))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Color.primary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(Theme.chip, in: Capsule())
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                    }
                    .cascade(2)

                    way("לשחרר", "לוותר עליה, בלב שלם. רשימה קצרה ואמיתית עדיפה על רשימה ארוכה שמעיקה.",
                        symbol: "leaf.fill", artwork: StuckSheet.stone) {
                        Button {
                            withAnimation(.section) { TaskRules.release(task, in: context) }
                            Feedback.tap()
                            dismiss()
                        } label: {
                            Text("לשחרר את המטלה")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                    .cascade(3)
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("מטלה תקועה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("לא עכשיו") { dismiss() }
                }
            }
        }
        .arrives()
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func way<Content: View>(_ title: String, _ text: String, symbol: String, artwork: Artwork,
                                    @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: artwork, symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 18, weight: .heavy))
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func breakDown() {
        let name: String = step.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(.section) { TaskRules.breakDown(task, firstStep: name, in: context) }
        Feedback.added()
        dismiss()
    }
}
