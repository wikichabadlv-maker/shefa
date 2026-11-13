import SwiftData
import SwiftUI

struct HomeView: View {
    @Binding var selection: AppTab
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<LedgerEntry> { !$0.removed }, sort: \LedgerEntry.date, order: .reverse)
    private var entries: [LedgerEntry]
    @Query(filter: #Predicate<SavingsGoal> { !$0.removed }, sort: \SavingsGoal.createdAt)
    private var goals: [SavingsGoal]
    @Query(filter: #Predicate<ListItem> { !$0.removed && !$0.isDone && $0.kind == "task" },
           sort: \ListItem.createdAt, order: .reverse)
    private var tasks: [ListItem]
    @Query(filter: #Predicate<ListItem> { !$0.removed && !$0.isDone && $0.kind == "shopping" },
           sort: \ListItem.createdAt, order: .reverse)
    private var shopping: [ListItem]

    @State private var backend = Backend.shared
    @State private var router = AppRouter.shared
    @State private var viewing: LedgerEntry?
    @State private var showsStudy = false

    private var counted: [LedgerEntry] { Ledger.effective(entries) }
    private var month: MonthSummary { Ledger.summary(counted) }
    private var question: LedgerEntry? { counted.first { $0.needsAnswer } }
    private var recent: [LedgerEntry] { Array(entries.prefix(4)) }
    /// Today's tasks first; when none were picked, the newest open ones.
    private var todayTasks: [ListItem] {
        let picked = tasks.filter(\.isForToday)
        return picked.isEmpty ? tasks : picked
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(Self.dateLine)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 4)
                        .padding(.bottom, -14)
                        .cascade(0)

                    shortcuts
                        .cascade(1)

                    RenewBanner()
                    BackupBanner()

                    if !backend.isSignedIn {
                        signInBanner
                    }
                    if backend.isSignedIn, let problem = backend.lastError {
                        syncProblem(problem)
                    }

                    Button {
                        router.financeSection = .overview
                        selection = .finance
                    } label: {
                        MonthHeroCard(month: month)
                    }
                    .buttonStyle(.pressable)
                    .cascade(2)

                    if let question {
                        QuestionCard(entry: question)
                            .id(question.id)
                            .transition(.opacity)
                    }

                    ZmanimCard()
                        .cascade(3)
                        .id("today")

                    CalendarCard()
                        .cascade(4)

                    CoachCard()
                        .cascade(4)

                    HabitsCard()
                        .cascade(5)

                    DailyStudyCard(opensTracker: { showsStudy = true })
                        .cascade(6)

                    insights
                        .cascade(7)

                    if !tasks.isEmpty {
                        tasksPreview
                            .cascade(8)
                    }

                    ShoppingCard(open: shopping) {
                        router.tasksSection = .shopping
                        selection = .tasks
                    }
                    .cascade(8)

                    goalsSection
                        .cascade(9)

                    if !recent.isEmpty {
                        recentSection
                            .cascade(9)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .task {
                guard !Launch.anchor.isEmpty else { return }
                try? await Task.sleep(for: .seconds(1.5))
                proxy.scrollTo(Launch.anchor, anchor: .top)
            }
            }
            .background { AmbientGround(artwork: Theme.emerald) }
            .refreshable { await Backend.shared.sync(into: context) }
            .navigationTitle("בית")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("הוספה מהירה", systemImage: "bolt.fill") { router.isQuickAdding = true }
                }
            }
            .sheet(item: $viewing) { entry in
                EntryDetailSheet(entry: entry)
            }
            .navigationDestination(isPresented: $showsStudy) {
                StudyView()
            }
        }
    }

    private struct Shortcut: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let artwork: Artwork
    }

    /// Every area of the app, one tap away.
    private var shortcuts: some View {
        let areas = [
            Shortcut(id: "zmanim", title: "זמני היום", symbol: "sun.horizon.fill", artwork: Artwork(0x0EA5E9, 0x4F46E5)),
            Shortcut(id: "study", title: "חת״ת ורמב״ם", symbol: "book.fill", artwork: Artwork(0x4F46E5, 0x312E81)),
            Shortcut(id: "shopping", title: "קניות", symbol: "cart.fill", artwork: Theme.green),
            Shortcut(id: "books", title: "ספרים", symbol: "books.vertical.fill", artwork: Artwork(0x0891B2, 0x155E75)),
            Shortcut(id: "notes", title: "לזכור", symbol: "lightbulb.fill", artwork: Theme.amber),
            Shortcut(id: "learning", title: "חידושים", symbol: "sparkles", artwork: Theme.blue),
            Shortcut(id: "achievements", title: "הישגים", symbol: "trophy.fill", artwork: Theme.violet),
            Shortcut(id: "settings", title: "הגדרות", symbol: "gearshape.fill", artwork: Artwork(0x64748B, 0x334155)),
        ]
        return ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(areas) { area in
                    Button {
                        if area.id == "shopping" {
                            router.tasksSection = .shopping
                            selection = .tasks
                        } else {
                            router.morePath = [area.id]
                            selection = .more
                        }
                        Feedback.tap()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: area.symbol)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(area.artwork.gradient, in: Circle())
                                .shadow(color: area.artwork.end.opacity(0.35), radius: 8, y: 5)
                            Text(area.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 64)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .padding(.horizontal, -16)
    }

    private var signInBanner: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: Theme.blue, symbol: "person.crop.circle.badge.checkmark")
                VStack(alignment: .leading, spacing: 1) {
                    Text("התחברות לחשבון המשפחתי")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text("בלי התחברות התוכן לא מגובה. אחריה מגיעות גם תנועות הבנק, והכול משותף לשני הטלפונים.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.secondary)
            }
            .padding(14)
            .cardSurface()
        }
        .buttonStyle(.pressable)
    }

    private func syncProblem(_ problem: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkIcon(artwork: Artwork(0xDC2626, 0x991B1B), symbol: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("הסנכרון לא הצליח")
                    .font(.system(size: 16, weight: .bold))
                Text(problem)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button("ניסיון נוסף") {
                    Task { await backend.sync(into: context) }
                }
                .font(.system(size: 14, weight: .bold))
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .cardSurface()
    }

    @ViewBuilder
    private var insights: some View {
        let list = Array(Insights.build(entries: counted, month: .now, summary: month).prefix(5))
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "שווה לדעת") {
                    router.financeSection = .overview
                    selection = .finance
                }
                InsightCarousel(insights: list, entries: counted, month: .now)
            }
        }
    }

    private var tasksPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "המטלות של היום") {
                router.tasksSection = .tasks
                selection = .tasks
            }
            VStack(spacing: 0) {
                ForEach(todayTasks.prefix(3)) { item in
                    Button {
                        var closedTheDay = false
                        withAnimation(.snappy) { closedTheDay = TaskRules.setDone(item, true, in: context) }
                        if !closedTheDay { Feedback.done() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(.secondary)
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("סימון כבוצע")
                    if item.id != todayTasks.prefix(3).last?.id {
                        Divider().padding(.leading, 34)
                    }
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
            if tasks.count > todayTasks.prefix(3).count {
                Text("ועוד \(tasks.count - todayTasks.prefix(3).count) מטלות פתוחות")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "יעדי חיסכון") {
                router.financeSection = .savings
                selection = .finance
            }
            if goals.isEmpty {
                Button {
                    router.financeSection = .savings
                    selection = .finance
                } label: {
                    HStack(spacing: 12) {
                        ArtworkIcon(artwork: Theme.emerald, symbol: "target")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("היעד הראשון שלכם")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.primary)
                            Text("קרן חירום, דירה, חופשה. קובעים סכום ותאריך ורואים את ההתקדמות.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(14)
                    .cardSurface()
                }
                .buttonStyle(.pressable)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(goals) { goal in
                            Button {
                                router.financeSection = .savings
                                selection = .finance
                            } label: {
                                GoalTile(goal: goal)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .padding(.horizontal, -16)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "תנועות אחרונות") {
                router.financeSection = .transactions
                selection = .finance
            }
            VStack(spacing: 0) {
                ForEach(recent) { item in
                    Button {
                        viewing = item
                    } label: {
                        TransactionRow(entry: item).contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    if item.id != recent.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
        }
    }

    /// For example "יום חמישי · ב׳ בכסלו · 12 בנובמבר".
    private static var dateLine: String {
        let day = Date.now.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide))
        return "\(HebrewDate.weekday()) · \(HebrewDate.text()) · \(day)"
    }
}

/// The app's main card: what is left to live on this month. Its color
/// follows the month: emerald when all is well, amber when the money goes
/// faster than the days, deep rose when the month went over. Never an alarm.
struct MonthHeroCard: View {
    let month: MonthSummary

    private var mood: MonthSummary.Mood { Launch.mood ?? month.mood }

    private var title: String {
        if month.daysLeft <= 0 { return month.remaining < 0 ? "החודש נסגר בחריגה של" : "נשאר בסוף החודש" }
        return mood == .over ? "חריגה מהמסגרת של החודש" : "נשאר לחיות ממנו החודש"
    }

    private var subtitle: String {
        if month.daysLeft <= 0 { return "סיכום החודש" }
        let days: String = Ledger.daysText(month.daysLeft)
        switch mood {
        case .over: return "עוד \(days) עד סוף החודש. שווה לדחות את מה שאפשר."
        case .watch: return "הכסף הולך מהר מהימים. כ־\(Money.text(month.perDay)) ליום עד סוף החודש."
        case .calm: return "כ־\(Money.text(month.perDay)) ליום · עוד \(days)"
        }
    }

    private var badge: (text: String, symbol: String) {
        switch mood {
        case .over: return ("חריגה", "exclamationmark.circle.fill")
        case .watch: return ("קצב מהיר", "hare.fill")
        case .calm: return ("בקצב טוב", "checkmark.circle.fill")
        }
    }

    private var incomeTitle: String {
        if month.salary > 0 { return "משכורת הבית" }
        return month.incomeIsEstimate ? "הכנסות (צפי)" : "הכנסות"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(0.9)
                Spacer(minLength: 8)
                if month.daysLeft > 0 {
                    Label(badge.text, systemImage: badge.symbol)
                        .font(.system(size: 12, weight: .heavy))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("₪")
                    .font(.system(size: 28, weight: .bold))
                CountUp(value: abs(month.remaining.double)) { Money.digits(Decimal($0.rounded())) }
                    .font(.system(size: 56, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Money.digits(month.remaining)) שקלים")

            GrowBar(share: month.spentShare, height: 8, track: .white.opacity(0.25), fill: Color.white)
                .padding(.top, 2)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.9)
                .padding(.top, 2)

            HStack(spacing: 0) {
                stat(incomeTitle, Money.text(month.income))
                Divider().overlay(.white.opacity(0.3)).frame(height: 28)
                stat("קבועות", Money.text(month.fixed))
                Divider().overlay(.white.opacity(0.3)).frame(height: 28)
                stat("מעשר", Money.text(month.maaserGiven), color: Color(hex: 0xFDE68A))
            }
            .padding(.vertical, 10)
            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(MonthHeroCard.artwork(mood))
        .animation(.smooth(duration: 0.5), value: mood)
        .accessibilityElement(children: .combine)
    }

    /// A livelier emerald than the theme's, for the app's main card.
    static let calm = Artwork(0x059669, 0x0F766E)

    static func artwork(_ mood: MonthSummary.Mood) -> Artwork {
        switch mood {
        case .calm: return calm
        case .watch: return Artwork(0xD97706, 0xB45309)
        case .over: return Artwork(0xBE185D, 0x831843)
        }
    }

    private func stat(_ title: String, _ value: String, color: Color = .white) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A purchase the app could not classify on its own and asks about.
struct QuestionCard: View {
    let entry: LedgerEntry
    @Environment(\.modelContext) private var context
    @State private var isChoosing = false

    private let suggestions = ["food", "home", "gift"].compactMap { SpendCategory.find($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: Theme.amber, symbol: "questionmark")
                VStack(alignment: .leading, spacing: 1) {
                    Text("מה קנינו ב\(entry.title)?")
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                    Text("\(entry.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide))) · \(entry.source) · \(Money.text(entry.amount, fractionDigits: 2))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(suggestions) { category in
                    chip(category.title) {
                        withAnimation(.snappy) { Ledger.answer(entry, with: category, in: context) }
                    }
                }
                chip("אחר…") { isChoosing = true }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .sheet(isPresented: $isChoosing) {
            CategoryPicker(entry: entry)
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Theme.amberGround, in: Capsule())
                .foregroundStyle(Theme.amberInk)
        }
        .buttonStyle(.pressable)
    }
}

/// A colorful tile for one savings goal.
struct GoalTile: View {
    let goal: SavingsGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: goal.symbol)
                .font(.system(size: 20, weight: .semibold))
            Spacer(minLength: 0)
            Text(goal.title)
                .font(.system(size: 16, weight: .heavy))
                .lineLimit(2)
            GrowBar(share: goal.share, height: 6, track: .white.opacity(0.25), delay: 0.3, fill: Color.white)
            Text("\(Money.text(goal.saved)) מתוך \(Money.text(goal.target))")
                .font(.system(size: 12, weight: .medium))
                .opacity(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 164, height: 150, alignment: .leading)
        .livingCard(goal.artwork, radius: 22, seed: Double(abs(goal.palette) % 8) * 0.21,
                    watermark: goal.symbol, isMoving: false)
        .accessibilityElement(children: .combine)
    }
}
