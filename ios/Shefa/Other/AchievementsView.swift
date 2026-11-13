import SwiftData
import SwiftUI

struct Achievement: Identifiable {
    let id: String
    let title: String
    let text: String
    let symbol: String
    let artwork: Artwork
    /// From 0 to 1, toward the next step.
    let progress: Double
    let isEarned: Bool

    init(id: String, title: String, text: String, symbol: String, artwork: Artwork,
         progress: Double, isEarned: Bool? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.symbol = symbol
        self.artwork = artwork
        self.progress = progress
        self.isEarned = isEarned ?? (progress >= 1)
    }
}

/// Real milestones, counted from what the family actually did in the app.
enum Achievements {
    static func build(entries: [LedgerEntry], goals: [SavingsGoal], items: [ListItem],
                      budget: [BudgetLine], schedule: [ScheduleItem]) -> [Achievement] {
        let calendar = Calendar.current
        var months: [Date: [LedgerEntry]] = [:]
        for entry in entries {
            if let start = calendar.dateInterval(of: .month, for: entry.date)?.start {
                months[start, default: []].append(entry)
            }
        }
        var positive = 0
        var maaserMonths = 0
        for (month, _) in months {
            let flow = Ledger.flow(entries, month)
            if flow.income > 0 && flow.income >= flow.spent { positive += 1 }
            let summary = Ledger.summary(entries, now: month)
            if summary.incomeSoFar > 0 && summary.maaserGiven >= summary.incomeSoFar / 10 { maaserMonths += 1 }
        }
        let doneTasks = items.filter { $0.kind == ListItem.task && $0.isDone }.count
        let open = entries.filter(\.needsAnswer).count
        let reached = goals.filter { $0.target > 0 && $0.saved >= $0.target }.count
        let savedTotal = goals.reduce(Decimal(0)) { $0 + $1.saved }.double

        func step(_ value: Int, _ steps: [Int]) -> (goal: Int, progress: Double) {
            let goal = steps.first { value < $0 } ?? (steps.last ?? 1)
            return (goal, min(Double(value) / Double(goal), 1))
        }

        let tracked = step(months.count, [1, 3, 6, 12, 24])
        let plus = step(positive, [1, 3, 6, 12])
        let maaser = step(maaserMonths, [1, 3, 6, 12])
        let tasks = step(doneTasks, [1, 10, 50, 100, 500])

        return [
            Achievement(id: "tracked", title: "\(months.count) חודשים במעקב",
                        text: "היעד הבא: \(tracked.goal) חודשים", symbol: "calendar",
                        artwork: Theme.blue, progress: tracked.progress, isEarned: !months.isEmpty),
            Achievement(id: "positive", title: "\(positive) חודשים חיוביים",
                        text: "חודש שבו ההכנסות עלו על ההוצאות", symbol: "arrow.up.right",
                        artwork: Theme.green, progress: plus.progress, isEarned: positive > 0),
            Achievement(id: "maaser", title: "\(maaserMonths) חודשי מעשר מלא",
                        text: "חודש שבו ניתן מעשר מכל ההכנסות", symbol: "heart.fill",
                        artwork: Theme.amber, progress: maaser.progress, isEarned: maaserMonths > 0),
            Achievement(id: "sorted", title: open == 0 ? "הכול מסווג" : "\(open) תנועות לבירור",
                        text: "כל תנועה יודעת לאן היא שייכת", symbol: "checkmark.seal.fill",
                        artwork: Theme.violet, progress: entries.isEmpty ? 0 : (open == 0 ? 1 : 0.5)),
            Achievement(id: "budget", title: "תקציב חודשי",
                        text: "קבעתם תקציב לקטגוריות", symbol: "chart.pie.fill",
                        artwork: Artwork(0x4F46E5, 0x312E81), progress: budget.contains { $0.limit > 0 } ? 1 : 0),
            Achievement(id: "goal", title: "יעד ראשון",
                        text: "הגדרתם על מה חוסכים", symbol: "target",
                        artwork: Theme.emerald, progress: goals.isEmpty ? 0 : 1),
            Achievement(id: "saved", title: "10,000 ₪ בצד",
                        text: "סך החיסכון בכל היעדים", symbol: "banknote.fill",
                        artwork: Artwork(0x0891B2, 0x155E75), progress: min(savedTotal / 10_000, 1)),
            Achievement(id: "reached", title: "יעד שהושג",
                        text: "הגעתם לסכום של יעד אחד לפחות", symbol: "flag.checkered",
                        artwork: Theme.pink, progress: reached > 0 ? 1 : 0),
            Achievement(id: "tasks", title: "\(doneTasks) מטלות בוצעו",
                        text: "היעד הבא: \(tasks.goal)", symbol: "checklist",
                        artwork: Artwork(0xEA580C, 0x9A3412), progress: tasks.progress, isEarned: doneTasks > 0),
            Achievement(id: "schedule", title: "סדר יום",
                        text: "בניתם לו״ז קבוע עם שלושה חלקים", symbol: "clock.fill",
                        artwork: Artwork(0xC026D3, 0x86198F), progress: min(Double(schedule.count) / 3, 1)),
        ]
    }
}

struct AchievementsView: View {
    @Query(filter: #Predicate<LedgerEntry> { !$0.removed }) private var entries: [LedgerEntry]
    @Query(filter: #Predicate<SavingsGoal> { !$0.removed }) private var goals: [SavingsGoal]
    @Query(filter: #Predicate<ListItem> { !$0.removed }) private var items: [ListItem]
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }) private var schedule: [ScheduleItem]
    @Query private var budget: [BudgetLine]
    @Query(filter: #Predicate<Habit> { !$0.removed }) private var habits: [Habit]

    var body: some View {
        let list = Achievements.build(entries: Ledger.effective(entries), goals: goals, items: items,
                                      budget: budget, schedule: schedule)
        let earned = list.filter(\.isEarned).count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("הישגים")
                            .font(.system(size: 15, weight: .semibold))
                            .opacity(0.9)
                        Text("\(earned) מתוך \(list.count)")
                            .font(.system(size: 40, weight: .heavy))
                            .monospacedDigit()
                        Text("נספרים מהפעילות האמיתית שלכם באפליקציה")
                            .font(.system(size: 13, weight: .medium))
                            .opacity(0.9)
                    }
                    Spacer(minLength: 0)
                    ProgressRing(share: Double(earned) / Double(max(list.count, 1)), lineWidth: 10)
                        .frame(width: 86, height: 86)
                        .overlay {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 26, weight: .bold))
                        }
                }
                .foregroundStyle(.white)
                .padding(20)
                .background(Theme.violet.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color(hex: 0x4C1D95).opacity(0.4), radius: 20, y: 12)
                .accessibilityElement(children: .combine)

                WeekCard(habits: habits)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(list) { item in
                        tile(item)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle("הישגים")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ item: Achievement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ArtworkIcon(artwork: item.isEarned ? item.artwork : Artwork(0x94A3B8, 0x64748B),
                            symbol: item.symbol, size: 40)
                Spacer()
                if item.isEarned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                }
            }
            Text(item.title)
                .font(.system(size: 16, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(item.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            ProgressView(value: item.progress)
                .tint(item.isEarned ? Theme.accent : item.artwork.start)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// The last seven days at a glance: how much of the daily pillars was kept
/// each day, and how many tasks were closed.
struct WeekCard: View {
    let habits: [Habit]
    @State private var isShown = false

    private var days: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }
    }

    private func share(_ day: Date) -> Double {
        guard !habits.isEmpty else { return 0 }
        return Double(habits.filter { $0.isDone(on: day) }.count) / Double(habits.count)
    }

    var body: some View {
        let done = Stats.doneByDay
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("השבוע שלי")
                    .font(.system(size: 20, weight: .heavy))
                Text("גובה העמודה: כמה מעמודי היום נשמרו. המספר: מטלות שנסגרו.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let value = share(day)
                    let count = done[DayKey.of(day)] ?? 0
                    let isToday = Calendar.current.isDateInToday(day)
                    VStack(spacing: 6) {
                        Text(count > 0 ? "\(count)" : " ")
                            .font(.system(size: 13, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Theme.chip)
                            Capsule()
                                .fill(value >= 1 ? Theme.green.gradient : Theme.blue.gradient)
                                .frame(height: isShown ? max(96 * value, value > 0 ? 14 : 0) : 0)
                        }
                        .frame(height: 96)
                        Text(["א", "ב", "ג", "ד", "ה", "ו", "ש"][Calendar.current.component(.weekday, from: day) - 1] + "׳")
                            .font(.system(size: 13, weight: isToday ? .heavy : .medium))
                            .foregroundStyle(isToday ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(HebrewDate.weekday(day)): \(Int(value * 100)) אחוז מעמודי היום, \(count) מטלות")
                }
            }
        }
        .padding(16)
        .cardSurface()
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.25).delay(0.15)) { isShown = true }
        }
    }
}
