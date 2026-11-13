import SwiftData
import SwiftUI

/// A daily practice to keep, such as morning prayers or a fixed study time.
/// Personal to this phone: it is not shared with the other phone.
@Model
final class Habit {
    @Attribute(.unique) var id: String
    var title: String
    var symbol: String
    var palette: Int
    var order: Int
    /// The days it was kept, as `DayKey`s joined by commas.
    var doneDays: String = ""
    var createdAt: Date
    var removed: Bool = false

    init(id: String = UUID().uuidString, title: String, symbol: String, palette: Int, order: Int) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.palette = palette
        self.order = order
        self.createdAt = .now
    }

    var artwork: Artwork {
        SavingsGoal.palettes[abs(palette) % SavingsGoal.palettes.count]
    }

    var days: Set<String> { DayKey.split(doneDays) }

    func isDone(on date: Date = .now) -> Bool { days.contains(DayKey.of(date)) }

    func toggle(on date: Date = .now) {
        var all = days
        let key = DayKey.of(date)
        if all.contains(key) { all.remove(key) } else { all.insert(key) }
        doneDays = DayKey.join(all, keep: 400)
    }

    var streak: Int { DayKey.streak(days, skipShabbat: true) }

    /// The six daily pillars the family asked for, added once and fully editable.
    static func addDefaultsIfNeeded(in context: ModelContext) {
        let key = "addedDefaultHabits"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let defaults: [(String, String, String, Int)] = [
            ("shacharit", "שחרית", "sunrise.fill", 4),
            ("torah", "קביעות לתורה", "book.fill", 0),
            ("chitas", "חת״ת ותהילים", "text.book.closed.fill", 1),
            ("mincha", "מנחה", "sun.max.fill", 6),
            ("tzedakah", "צדקה יומית", "heart.fill", 2),
            ("arvit", "ערבית וק״ש", "moon.stars.fill", 7),
        ]
        for (index, item) in defaults.enumerated() {
            context.insert(Habit(id: "habit-" + item.0, title: item.1, symbol: item.2, palette: item.3, order: index))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Days in a row on which every habit was kept.
    static func fullStreak(_ habits: [Habit]) -> Int {
        guard var common = habits.first?.days else { return 0 }
        for habit in habits.dropFirst() { common.formIntersection(habit.days) }
        return DayKey.streak(common, skipShabbat: true)
    }
}

/// Today's practices as round buttons, with the count and the streak.
struct HabitsCard: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.removed }, sort: \Habit.order) private var habits: [Habit]
    @State private var isEditing = false
    @State private var celebrates = false

    private var done: Int { habits.filter { $0.isDone() }.count }

    private var line: String {
        let left = habits.count - done
        if habits.isEmpty { return "" }
        if left == 0 { return "יום מלא. כל הכבוד!" }
        if left == 1 { return "עוד אחת והיום שלם" }
        if done == 0 {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
            let missedYesterday = !habits.contains { $0.isDone(on: yesterday) }
            return missedYesterday ? "מתחילים מחדש. צעד אחד קטן מספיק" : "מתחילים עם הראשונה"
        }
        return "\(done) מתוך \(habits.count) כבר מאחוריכם"
    }

    var body: some View {
        let streak = Habit.fullStreak(habits)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("קביעות היום")
                    .font(.system(size: 20, weight: .heavy))
                Text("\(done)/\(habits.count)")
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(done == habits.count && !habits.isEmpty ? Theme.accent : Color.secondary)
                Spacer()
                if streak > 1 {
                    Label("\(streak) ימים ברצף", systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0xEA580C))
                }
                Button("עריכה") { isEditing = true }
                    .font(.system(size: 14, weight: .bold))
            }

            if habits.isEmpty {
                Text("הוסיפו את הדברים שחשוב לכם לשמור עליהם כל יום.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 12) {
                    ForEach(habits) { habit in
                        button(habit)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.chip)
                        Capsule().fill(Theme.emerald.gradient)
                            .frame(width: max(proxy.size.width * CGFloat(done) / CGFloat(max(habits.count, 1)), done > 0 ? 8 : 0))
                    }
                }
                .frame(height: 6)
                Text(line)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .overlay {
            if celebrates { ConfettiView().allowsHitTesting(false) }
        }
        .sheet(isPresented: $isEditing) {
            HabitsSheet()
        }
    }

    private func button(_ habit: Habit) -> some View {
        let isDone = habit.isDone()
        return Button {
            withAnimation(.spring(duration: 0.35, bounce: 0.45)) { habit.toggle() }
            try? context.save()
            if !isDone {
                let allDone = habits.allSatisfy { $0.isDone() }
                if allDone {
                    Feedback.celebrate()
                    celebrates = true
                    Task {
                        try? await Task.sleep(for: .seconds(2.2))
                        celebrates = false
                    }
                } else {
                    Feedback.done()
                }
            } else {
                Feedback.tap()
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isDone ? AnyShapeStyle(habit.artwork.gradient) : AnyShapeStyle(Theme.chip))
                        .frame(width: 54, height: 54)
                    Image(systemName: isDone ? "checkmark" : habit.symbol)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(isDone ? Color.white : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .scaleEffect(isDone ? 1.0 : 0.94)
                Text(habit.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDone ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(habit.title)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}

/// The list of practices: the last week at a glance, add, rename and delete.
struct HabitsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Habit> { !$0.removed }, sort: \Habit.order) private var habits: [Habit]
    @State private var newTitle = ""
    @State private var renaming: Habit?
    @State private var renameText = ""

    private var week: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(habits) { habit in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                ArtworkIcon(artwork: habit.artwork, symbol: habit.symbol, size: 34)
                                Text(habit.title)
                                    .font(.system(size: 16, weight: .bold))
                                Spacer()
                                if habit.streak > 0 {
                                    Label("\(habit.streak)", systemImage: "flame.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color(hex: 0xEA580C))
                                }
                            }
                            HStack(spacing: 6) {
                                ForEach(week, id: \.self) { day in
                                    let isDone = habit.isDone(on: day)
                                    let index = Calendar.current.component(.weekday, from: day) - 1
                                    Button {
                                        habit.toggle(on: day)
                                        try? context.save()
                                    } label: {
                                        Text(ScheduleItem.dayLetters[index])
                                            .font(.system(size: 13, weight: .bold))
                                            .frame(maxWidth: .infinity, minHeight: 32)
                                            .foregroundStyle(isDone ? Color.white : Color.secondary)
                                            .background(isDone ? AnyShapeStyle(habit.artwork.gradient) : AnyShapeStyle(Theme.chip),
                                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    }
                                    .buttonStyle(.pressable)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions {
                            Button("מחיקה", systemImage: "trash", role: .destructive) {
                                habit.removed = true
                                try? context.save()
                            }
                            Button("שם", systemImage: "pencil") {
                                renameText = habit.title
                                renaming = habit
                            }
                        }
                    }
                } footer: {
                    Text("אפשר לסמן גם ימים קודמים בשבוע האחרון. שבת לא שוברת רצף. החלקה על שורה מאפשרת לשנות שם או למחוק.")
                }

                Section("קביעות חדשה") {
                    HStack {
                        TextField("למשל: רמב״ם יומי", text: $newTitle)
                            .onSubmit { add() }
                        Button("הוספה") { add() }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("הקביעויות שלי")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
            .alert("שינוי שם", isPresented: isRenaming) {
                TextField("שם", text: $renameText)
                Button("שמירה") {
                    let text = renameText.trimmingCharacters(in: .whitespaces)
                    if let habit = renaming, !text.isEmpty {
                        habit.title = text
                        try? context.save()
                    }
                    renaming = nil
                }
                Button("ביטול", role: .cancel) {}
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func add() {
        let text = newTitle.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let symbols = ["star.fill", "book.fill", "heart.fill", "figure.walk", "leaf.fill", "drop.fill"]
        context.insert(Habit(title: text, symbol: symbols[habits.count % symbols.count],
                             palette: habits.count, order: (habits.map(\.order).max() ?? -1) + 1))
        try? context.save()
        newTitle = ""
        Feedback.added()
    }
}

/// A short burst of colorful dots for a finished day.
struct ConfettiView: View {
    @State private var isFalling = false

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat
        let size: CGFloat
        let delay: Double
        let color: Color
        let drift: CGFloat
    }

    private let pieces: [Piece] = {
        let colors: [UInt32] = [0x10B981, 0xF59E0B, 0xDB2777, 0x2563EB, 0x7C3AED, 0xEA580C]
        return (0..<36).map { index in
            Piece(id: index, x: CGFloat.random(in: 0...1), size: CGFloat.random(in: 6...11),
                  delay: Double.random(in: 0...0.35), color: Color(hex: colors[index % colors.count]),
                  drift: CGFloat.random(in: -40...40))
        }
    }()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size * 1.6)
                        .rotationEffect(.degrees(isFalling ? Double(piece.drift) * 9 : 0))
                        .position(x: proxy.size.width * piece.x + (isFalling ? piece.drift : 0),
                                  y: isFalling ? proxy.size.height + 30 : -20)
                        .opacity(isFalling ? 0 : 1)
                        .animation(.easeIn(duration: 1.7).delay(piece.delay), value: isFalling)
                }
            }
        }
        .clipped()
        .onAppear { isFalling = true }
        .accessibilityHidden(true)
    }
}
