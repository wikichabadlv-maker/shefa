import SwiftData
import SwiftUI

/// How much of one lesson was learned on one day.
struct StudyMark: Equatable {
    /// Whole parts learned: 0...3 chapters of Rambam, 0 or 1 for the others.
    var parts = 0
    /// Stopped in the middle of the next part.
    var partial = false
    /// For Rambam: the halacha reached in the chapter that was not finished; 0 when not noted.
    var halacha = 0

    var isEmpty: Bool { parts == 0 && !partial }
}

/// What was learned on which day, kept on this phone.
enum StudyLog {
    private static let key = "studyMarksByDay"
    private static let oldKey = "studyDoneByDay"
    private static let trackedKey = "studyTracked"
    private static let startKey = "studyStartDay"

    static let all = [DailyStudy.chumash, DailyStudy.tehillim, DailyStudy.tanya, DailyStudy.rambam]

    static func total(_ id: String) -> Int { id == DailyStudy.rambam ? 3 : 1 }

    /// The lessons this person follows; all four unless changed.
    static var tracked: [String] {
        get {
            guard let saved = UserDefaults.standard.stringArray(forKey: trackedKey) else { return all }
            return all.filter { saved.contains($0) }
        }
        set { UserDefaults.standard.set(newValue, forKey: trackedKey) }
    }

    private static var store: [String: [String: String]] {
        if let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] { return saved }
        // Marks from the first version: a plain list of finished lessons per day.
        let old = (UserDefaults.standard.dictionary(forKey: oldKey) as? [String: [String]]) ?? [:]
        return old.mapValues { ids in
            Dictionary(uniqueKeysWithValues: ids.map { ($0, "\(total($0)),0,0") })
        }
    }

    static func mark(_ id: String, on date: Date = .now) -> StudyMark {
        guard let text = store[DayKey.of(date)]?[id] else { return StudyMark() }
        let numbers = text.split(separator: ",").compactMap { Int($0) }
        guard numbers.count == 3 else { return StudyMark() }
        return StudyMark(parts: numbers[0], partial: numbers[1] == 1, halacha: numbers[2])
    }

    static func set(_ id: String, _ mark: StudyMark, on date: Date = .now) {
        var everything = store
        var day = everything[DayKey.of(date)] ?? [:]
        var clean = mark
        clean.parts = min(max(clean.parts, 0), total(id))
        if clean.parts == total(id) {
            clean.partial = false
            clean.halacha = 0
        }
        day[id] = clean.isEmpty ? nil : "\(clean.parts),\(clean.partial ? 1 : 0),\(clean.halacha)"
        everything[DayKey.of(date)] = day.isEmpty ? nil : day
        if everything.count > 500 {
            for old in everything.keys.sorted().prefix(everything.count - 500) { everything[old] = nil }
        }
        UserDefaults.standard.set(everything, forKey: key)
        if UserDefaults.standard.string(forKey: startKey) == nil {
            UserDefaults.standard.set(DayKey.of(), forKey: startKey)
        }
    }

    static func isDone(_ id: String, on date: Date = .now) -> Bool {
        mark(id, on: date).parts >= total(id)
    }

    static func setDone(_ id: String, _ done: Bool, on date: Date = .now) {
        set(id, StudyMark(parts: done ? total(id) : 0), on: date)
    }

    /// The share of the day's followed lessons that was learned, 0...1.
    static func share(on date: Date = .now) -> Double {
        let ids = tracked
        let whole = ids.reduce(0) { $0 + total($1) }
        guard whole > 0 else { return 0 }
        let learned = ids.reduce(0.0) { sum, id in
            let mark = mark(id, on: date)
            return sum + Double(mark.parts) + (mark.partial ? 0.5 : 0)
        }
        return min(learned / Double(whole), 1)
    }

    static func isFull(on date: Date = .now) -> Bool {
        !tracked.isEmpty && tracked.allSatisfy { isDone($0, on: date) }
    }

    /// The first day that counts; earlier days are never shown as missed.
    static var startDay: String {
        UserDefaults.standard.string(forKey: startKey) ?? DayKey.of()
    }

    /// Days in a row in which everything followed was learned. A day marked
    /// later, such as Shabbat, counts like any other.
    static var fullStreak: Int {
        let ids = tracked
        guard !ids.isEmpty else { return 0 }
        let days = store.filter { _, marks in
            ids.allSatisfy { id in (Int(marks[id]?.split(separator: ",").first ?? "") ?? 0) >= total(id) }
        }
        return DayKey.streak(Set(days.keys))
    }

    struct Gap: Identifiable {
        let date: Date
        let lesson: String
        let mark: StudyMark

        var id: String { DayKey.of(date) + lesson }
        var missingParts: Int { StudyLog.total(lesson) - mark.parts }
    }

    /// Lessons of the last weeks that were not finished, newest first.
    static func gaps(days: Int = 45) -> [Gap] {
        let calendar = Calendar.current
        var result: [Gap] = []
        for offset in 1...days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now),
                  DayKey.of(date) >= startDay else { break }
            for id in tracked where !isDone(id, on: date) {
                result.append(Gap(date: date, lesson: id, mark: mark(id, on: date)))
            }
        }
        return result
    }

    /// Made-up marks for simulator screenshots only.
    static func fillDemo() {
        let calendar = Calendar.current
        UserDefaults.standard.set(DayKey.of(calendar.date(byAdding: .day, value: -12, to: .now) ?? .now), forKey: startKey)
        for offset in 1...12 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            for id in all { setDone(id, true, on: date) }
        }
        if let date = calendar.date(byAdding: .day, value: -2, to: .now) {
            set(DailyStudy.rambam, StudyMark(parts: 1, partial: true, halacha: 4), on: date)
        }
        if let date = calendar.date(byAdding: .day, value: -4, to: .now) {
            set(DailyStudy.tanya, StudyMark(), on: date)
            set(DailyStudy.rambam, StudyMark(parts: 2), on: date)
        }
        setDone(DailyStudy.chumash, true)
        UserDefaults.standard.set(DayKey.of(calendar.date(byAdding: .day, value: -12, to: .now) ?? .now), forKey: startKey)
    }

    /// Chapters of Rambam still owed from earlier days.
    static var rambamDebt: Int {
        gaps().filter { $0.lesson == DailyStudy.rambam }.reduce(0) { $0 + $1.missingParts }
    }
}

extension StudyLog {
    /// The color of the daily lessons everywhere in the app.
    static let artwork = Artwork(0x4F46E5, 0x312E81)

    /// Call after a lesson was just marked as learned. When that closed
    /// today's lessons, or the last lesson that was waiting to be made up,
    /// the celebration plays; returns true when it did. `wasFull` is how
    /// that day stood before the mark.
    @MainActor @discardableResult
    static func celebrate(on date: Date, wasFull: Bool, after delay: Double = 0) -> Bool {
        guard !wasFull, isFull(on: date) else { return false }
        if Calendar.current.isDateInToday(date) {
            guard tracked.count > 1 else { return false }
            let streak: Int = fullStreak
            return Moments.shared.play(
                "study", symbol: "book.fill", title: "הלימוד היומי הושלם",
                text: streak > 1 ? "כל שיעורי היום נלמדו. \(streak) ימים ברצף." : "כל שיעורי היום נלמדו.",
                artwork: artwork, after: delay)
        }
        guard gaps().isEmpty else { return false }
        return Moments.shared.play(
            "study.gaps", symbol: "checkmark.seal.fill", title: "הכול הושלם",
            text: "אין עוד שיעורים שמחכים להשלמה.", artwork: artwork, after: delay)
    }
}

/// Today's lessons on the home screen: one tap marks a lesson learned, and a
/// tap on its name opens the finer choices.
struct DailyStudyCard: View {
    var date: Date = .now
    var opensTracker: (() -> Void)?
    /// Changes when the screen around the card learned of a change.
    var refresh = 0
    /// Tells the screen around the card that a lesson was marked.
    var onChange: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { $0.id == "habit-chitas" && !$0.removed }) private var chitasHabit: [Habit]
    @State private var version = 0
    @State private var detail: StudyPortion?
    /// Rises by one for a lesson each time it is marked, to throw its sparks.
    @State private var sparks: [String: Int] = [:]

    private var portions: [StudyPortion] {
        DailyStudy.portions(on: date).filter { StudyLog.tracked.contains($0.id) }
    }

    var body: some View {
        // The marks live outside SwiftUI; reading the counter redraws the card.
        let _ = version
        let list = portions
        let doneCount = list.filter { StudyLog.isDone($0.id, on: date) }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("חת״ת ורמב״ם")
                    .font(.system(size: 20, weight: .heavy))
                Text("\(doneCount)/\(list.count)")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
                if StudyLog.fullStreak > 1 {
                    Label("\(StudyLog.fullStreak) ימים", systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.amberInk)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Theme.amberGround, in: Capsule())
                }
                if let opensTracker {
                    Button("מעקב", action: opensTracker)
                        .font(.system(size: 14, weight: .bold))
                        .buttonStyle(.pressable)
                        .foregroundStyle(Theme.accent)
                }
            }

            VStack(spacing: 0) {
                ForEach(list) { portion in
                    row(portion)
                    if portion.id != list.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }

            if opensTracker != nil, !StudyLog.gaps().isEmpty {
                let debt = StudyLog.gaps().count
                Button {
                    opensTracker?()
                } label: {
                    Label(debt == 1 ? "שיעור אחד מחכה להשלמה" : "\(debt) שיעורים מחכים להשלמה",
                          systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.amberInk)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Theme.amberGround, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(16)
        .cardSurface()
        .sheet(item: $detail, onDismiss: { changed() }) { portion in
            StudyMarkSheet(portion: portion, date: date)
        }
    }

    private func row(_ portion: StudyPortion) -> some View {
        let mark = StudyLog.mark(portion.id, on: date)
        let isDone = mark.parts >= StudyLog.total(portion.id)
        return HStack(spacing: 4) {
            Button {
                detail = portion
            } label: {
                HStack(spacing: 12) {
                    ArtworkIcon(artwork: portion.artwork, symbol: portion.symbol, size: 40)
                        .saturation(isDone ? 0.3 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(portion.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isDone ? Color.secondary : Color.primary)
                            .strikethrough(isDone)
                        Text(portion.detail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        if !isDone, !mark.isEmpty {
                            Text(StudyText.progress(portion.id, mark, on: date))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.amberInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("פירוט: כמה למדתי")

            Button {
                let wasFull: Bool = StudyLog.isFull(on: date)
                StudyLog.setDone(portion.id, !isDone, on: date)
                changed()
                if isDone {
                    Feedback.tap()
                } else {
                    sparks[portion.id, default: 0] += 1
                    if !StudyLog.celebrate(on: date, wasFull: wasFull) { Feedback.done() }
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : (mark.isEmpty ? "circle" : "circle.lefthalf.filled"))
                    .font(.system(size: 27))
                    .foregroundStyle(isDone ? Theme.accent : (mark.isEmpty ? Color.secondary : Theme.amberInk))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 46, height: 50)
                    .background { SparkBurst(trigger: sparks[portion.id] ?? 0) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(isDone ? "ביטול הסימון" : "למדתי הכול")
        }
    }

    /// Call after a mark changed: redraws, and keeps the rest of the app in step.
    private func changed() {
        withAnimation(.section) { version += 1 }
        let chitas = [DailyStudy.chumash, DailyStudy.tehillim, DailyStudy.tanya]
        let chitasDone = chitas.allSatisfy { StudyLog.isDone($0, on: date) }
        if let habit = chitasHabit.first, chitasDone != habit.isDone(on: date) {
            // The "Chitas" pillar follows the three lessons.
            habit.toggle(on: date)
            try? context.save()
        }
        Notifier.shared.refresh(in: context)
        onChange?()
    }
}

/// Words for a lesson that was learned in part.
enum StudyText {
    static func progress(_ id: String, _ mark: StudyMark, on date: Date) -> String {
        guard id == DailyStudy.rambam else { return "למדתי חלק" }
        let chapters = DailyStudy.rambamChapters(on: date)
        var text = mark.parts == 0 ? "עוד לא סיימתי פרק" : (mark.parts == 1 ? "למדתי פרק אחד" : "למדתי שני פרקים")
        if mark.partial, mark.parts < chapters.count {
            text += " · עצרתי ב\(chapters[mark.parts])"
            if mark.halacha > 0 { text += ", הלכה \(DailyStudy.letters(mark.halacha))" }
        }
        return text
    }

    /// What is left to make up.
    static func missing(_ gap: StudyLog.Gap) -> String {
        guard gap.lesson == DailyStudy.rambam else {
            return gap.mark.partial ? "נשאר לסיים" : "לא נלמד"
        }
        let chapters = DailyStudy.rambamChapters(on: gap.date)
        let rest = chapters.dropFirst(gap.mark.parts)
        var text = "נשאר: " + rest.joined(separator: ", ")
        if gap.mark.partial, gap.mark.halacha > 0 {
            text += " (מהלכה \(DailyStudy.letters(gap.mark.halacha)))"
        }
        return text
    }

    static func name(_ id: String) -> String {
        switch id {
        case DailyStudy.chumash: return "חומש"
        case DailyStudy.tehillim: return "תהילים"
        case DailyStudy.tanya: return "תניא"
        default: return "רמב״ם"
        }
    }
}

/// The finer choices for one lesson on one day: all of it, part of it, and
/// for Rambam which chapters and where the learning stopped.
struct StudyMarkSheet: View {
    let portion: StudyPortion
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @State private var mark = StudyMark()

    private var isRambam: Bool { portion.id == DailyStudy.rambam }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ArtworkIcon(artwork: portion.artwork, symbol: portion.symbol, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(portion.title).font(.system(size: 20, weight: .heavy))
                        Text(portion.detail).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }

                if isRambam {
                    rambam
                } else {
                    HStack(spacing: 8) {
                        choice("למדתי הכול", isOn: mark.parts == 1) { mark = StudyMark(parts: 1) }
                        choice("למדתי חלק", isOn: mark.parts == 0 && mark.partial) { mark = StudyMark(partial: true) }
                        choice("לא למדתי", isOn: mark.isEmpty) { mark = StudyMark() }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(Calendar.current.isDateInToday(date) ? "היום" : HebrewDate.weekday(date) + ", " + HebrewDate.text(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") {
                        let wasFull: Bool = StudyLog.isFull(on: date)
                        StudyLog.set(portion.id, mark, on: date)
                        dismiss()
                        if mark.parts < StudyLog.total(portion.id) {
                            Feedback.tap()
                        } else if !StudyLog.celebrate(on: date, wasFull: wasFull, after: 0.5) {
                            // The celebration waits for the sheet to close; without one, the usual chime.
                            Feedback.done()
                        }
                    }
                }
            }
            .onAppear { mark = StudyLog.mark(portion.id, on: date) }
            .animation(.section, value: mark)
        }
        .presentationDetents([.height(isRambam ? 430 : 260)])
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var rambam: some View {
        let chapters = DailyStudy.rambamChapters(on: date)
        return VStack(alignment: .leading, spacing: 14) {
            Text("אילו פרקים סיימתי?")
                .font(.system(size: 15, weight: .bold))
            HStack(spacing: 8) {
                ForEach(chapters.indices, id: \.self) { index in
                    let isOn = index < mark.parts
                    Button {
                        // Tapping a chapter means "learned up to here"; tapping the last learned one takes it back.
                        mark.parts = mark.parts == index + 1 ? index : index + 1
                        if mark.parts == 3 { mark.partial = false }
                        mark.halacha = 0
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                            Text(chapters[index])
                                .font(.system(size: 13, weight: .bold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .padding(.horizontal, 4)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(isOn ? AnyShapeStyle(Theme.blue.gradient) : AnyShapeStyle(Theme.chip),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                }
            }

            if mark.parts < 3 {
                Toggle(isOn: $mark.partial) {
                    Text("עצרתי באמצע: \(chapters[mark.parts])")
                        .font(.system(size: 15, weight: .semibold))
                }
                if mark.partial {
                    Stepper(value: $mark.halacha, in: 0...60) {
                        Text(mark.halacha == 0 ? "באיזו הלכה? (לא חובה)" : "הגעתי עד הלכה \(DailyStudy.letters(mark.halacha))")
                            .font(.system(size: 15))
                            .contentTransition(.numericText())
                    }
                }
            } else {
                Label("כל שלושת הפרקים נלמדו", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func choice(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .foregroundStyle(isOn ? Theme.ground : Color.primary)
                .background(isOn ? Color.primary : Theme.chip, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The tracker for the daily lessons: today, what is waiting to be made up,
/// and the last five weeks at a glance.
struct StudyView: View {
    @Environment(\.modelContext) private var context
    @State private var version = 0
    @State private var day: Date?
    @State private var detail: StudyLog.Gap?
    @State private var showsChoice = false

    var body: some View {
        let gaps = StudyLog.gaps()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(gaps)
                    .cascade(0)
                DailyStudyCard(refresh: version, onChange: { withAnimation(.section) { version += 1 } })
                    .cascade(1)
                if !gaps.isEmpty {
                    makeUps(gaps)
                        .cascade(2)
                }
                month
                    .cascade(3)
            }
            .padding(16)
            .animation(.section, value: version)
        }
        .background { AmbientGround(artwork: StudyLog.artwork) }
        .navigationTitle("חת״ת ורמב״ם")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("אילו שיעורים", systemImage: "slider.horizontal.3") { showsChoice = true }
            }
        }
        .arrives()
        .sheet(item: $detail, onDismiss: { version += 1 }) { gap in
            if let portion = DailyStudy.portions(on: gap.date).first(where: { $0.id == gap.lesson }) {
                StudyMarkSheet(portion: portion, date: gap.date)
            }
        }
        .sheet(isPresented: dayBinding, onDismiss: { version += 1 }) {
            if let day { StudyDaySheet(date: day) }
        }
        .sheet(isPresented: $showsChoice, onDismiss: { version += 1 }) {
            StudyChoiceSheet()
        }
    }

    private var dayBinding: Binding<Bool> {
        Binding(get: { day != nil }, set: { if !$0 { day = nil } })
    }

    private func hero(_ gaps: [StudyLog.Gap]) -> some View {
        let streak = StudyLog.fullStreak
        let debt = StudyLog.rambamDebt
        let headline: String
        if StudyLog.isFull() {
            headline = "היום הושלם"
        } else if gaps.isEmpty {
            headline = "הכול מעודכן"
        } else {
            headline = gaps.count == 1 ? "שיעור אחד להשלמה" : "\(gaps.count) שיעורים להשלמה"
        }
        let line: String
        if debt > 0 {
            line = "חסרים \(debt) פרקי רמב״ם. פרק נוסף אחד ביום, ותוך \(debt) ימים אתם מעודכנים."
        } else if streak > 1 {
            line = "\(streak) ימים ברצף של לימוד מלא."
        } else {
            line = "גם שיעור שנלמד באיחור נספר. מסמנים, ומשלימים בקצב שלכם."
        }
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(HebrewDate.weekday() + " · " + HebrewDate.text())
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.9)
                Text(headline)
                    .font(.system(size: 28, weight: .heavy))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(line)
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.92)
            }
            Spacer(minLength: 0)
            ProgressRing(share: StudyLog.share(), lineWidth: 10)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: StudyLog.isFull() ? "checkmark" : "book.fill")
                        .font(.system(size: 24, weight: .heavy))
                }
        }
        .foregroundStyle(.white)
        .padding(20)
        .livingCard(StudyLog.artwork, seed: 0.5)
        .accessibilityElement(children: .combine)
    }

    private func makeUps(_ gaps: [StudyLog.Gap]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("השלמות")
                    .font(.system(size: 22, weight: .heavy))
                Text("\(gaps.count)")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(gaps.prefix(12)) { gap in
                    gapRow(gap)
                    if gap.id != gaps.prefix(12).last?.id { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
            if gaps.count > 12 {
                Text("ועוד \(gaps.count - 12) מוקדמים יותר. הם יופיעו כשתשלימו את אלה.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    private func gapRow(_ gap: StudyLog.Gap) -> some View {
        let portion = DailyStudy.portions(on: gap.date).first { $0.id == gap.lesson }
        return HStack(spacing: 8) {
            Button {
                detail = gap
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(StudyText.name(gap.lesson)) · \(HebrewDate.weekday(gap.date)), \(HebrewDate.text(gap.date))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text(portion?.detail ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if gap.lesson == DailyStudy.rambam || gap.mark.partial {
                        Text(StudyText.missing(gap))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.amberInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            Button {
                let wasFull: Bool = StudyLog.isFull(on: gap.date)
                StudyLog.setDone(gap.lesson, true, on: gap.date)
                if !StudyLog.celebrate(on: gap.date, wasFull: wasFull) { Feedback.done() }
                withAnimation(.section) { version += 1 }
                Notifier.shared.refresh(in: context)
            } label: {
                Text("השלמתי")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
    }

    /// Five weeks, a ring for each day; a tap opens that day.
    private var month: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        let end = calendar.date(byAdding: .day, value: 7 - weekday, to: today) ?? today
        let days = (0..<35).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("חמשת השבועות האחרונים")
                    .font(.system(size: 20, weight: .heavy))
                Text("טבעת מלאה: כל השיעורים נלמדו. הקישו על יום כדי לעדכן אותו.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            HStack {
                ForEach(["א", "ב", "ג", "ד", "ה", "ו", "ש"], id: \.self) { letter in
                    Text(letter + "׳")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(days, id: \.self) { date in
                    let isFuture = date > today
                    let counts = DayKey.of(date) >= StudyLog.startDay
                    let share = StudyLog.share(on: date)
                    Button {
                        day = date
                    } label: {
                        ZStack {
                            ProgressRing(share: isFuture ? 0 : share, lineWidth: 4, track: Theme.chip,
                                         fill: share >= 1 ? Theme.accent : Color(hex: 0x4F46E5))
                            Text("\(calendar.component(.day, from: date))")
                                .font(.system(size: 13, weight: calendar.isDateInToday(date) ? .heavy : .medium))
                                .monospacedDigit()
                                .foregroundStyle(calendar.isDateInToday(date) ? Color.primary : Color.secondary)
                        }
                        .frame(height: 40)
                        .opacity(isFuture || !counts && share == 0 ? 0.35 : 1)
                    }
                    .buttonStyle(.pressable)
                    .disabled(isFuture)
                    .accessibilityLabel("\(HebrewDate.text(date)), \(Int(share * 100)) אחוז")
                }
            }
        }
        .padding(16)
        .cardSurface()
    }
}

/// All the lessons of one earlier day, to fill in or correct.
struct StudyDaySheet: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DailyStudyCard(date: date)
                    .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle(HebrewDate.weekday(date) + ", " + HebrewDate.text(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
        }
        .momentHost()
        .presentationDetents([.medium, .large])
        .environment(\.layoutDirection, .rightToLeft)
    }
}

/// Which of the four lessons to follow.
struct StudyChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tracked = Set(StudyLog.tracked)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(StudyLog.all, id: \.self) { id in
                        Toggle(StudyText.name(id), isOn: Binding(
                            get: { tracked.contains(id) },
                            set: { isOn in
                                if isOn { tracked.insert(id) } else { tracked.remove(id) }
                                StudyLog.tracked = StudyLog.all.filter { tracked.contains($0) }
                            }))
                    }
                } footer: {
                    Text("רק השיעורים שנבחרו יופיעו בדף הבית, ברצף ובהשלמות.")
                }
            }
            .navigationTitle("אילו שיעורים עוקבים")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .environment(\.layoutDirection, .rightToLeft)
    }
}
