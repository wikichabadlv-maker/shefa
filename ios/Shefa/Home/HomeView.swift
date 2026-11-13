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

    @State private var backend = Backend.shared
    @State private var router = AppRouter.shared
    @State private var viewing: LedgerEntry?

    private var counted: [LedgerEntry] { Ledger.effective(entries) }
    private var month: MonthSummary { Ledger.summary(counted) }
    private var question: LedgerEntry? { counted.first { $0.needsAnswer } }
    private var recent: [LedgerEntry] { Array(entries.prefix(4)) }

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
                    .buttonStyle(.plain)

                    if let question {
                        QuestionCard(entry: question)
                            .id(question.id)
                            .transition(.opacity)
                    }

                    TodayCard(selection: $selection)
                        .id("today")

                    insights

                    if !tasks.isEmpty {
                        tasksPreview
                    }

                    goalsSection

                    if !recent.isEmpty {
                        recentSection
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
            .background(Theme.ground)
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
        }
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
                    Text("כדי לקבל את תנועות הבנק והאשראי ולשתף הכול בין שני הטלפונים")
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
        .buttonStyle(.plain)
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
            SectionHeader(title: "מטלות פתוחות") { selection = .tasks }
            VStack(spacing: 0) {
                ForEach(tasks.prefix(3)) { item in
                    Button {
                        withAnimation(.snappy) {
                            item.isDone = true
                            item.doneAt = .now
                            item.updatedAt = .now
                        }
                        try? context.save()
                        SharedSync.shared.changed(in: context)
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
                    .buttonStyle(.plain)
                    .accessibilityHint("סימון כבוצע")
                    if item.id != tasks.prefix(3).last?.id {
                        Divider().padding(.leading, 34)
                    }
                }
            }
            .padding(.horizontal, 14)
            .cardSurface()
            if tasks.count > 3 {
                Text("ועוד \(tasks.count - 3) מטלות")
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
                .buttonStyle(.plain)
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
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
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
                    .buttonStyle(.plain)
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

/// Today in one card: what is on now and the next times of the day.
struct TodayCard: View {
    @Binding var selection: AppTab
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }, sort: \ScheduleItem.startMinute)
    private var items: [ScheduleItem]
    @AppStorage(City.storageKey) private var cityID = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let zmanim = Zmanim(city: City.find(cityID), day: now)
            let status = NowStatus.make(items: items, now: now)
            let upcoming = Array(zmanim.list.filter { $0.isMain && $0.date > now }.prefix(3))
            Button {
                selection = .schedule
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ArtworkIcon(artwork: status.artwork, symbol: status.symbol)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(status.title)
                                .font(.system(size: 17, weight: .heavy))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(status.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.secondary)
                    }
                    if !upcoming.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(upcoming) { zman in
                                VStack(spacing: 2) {
                                    Text(zmanim.clock(zman.date))
                                        .font(.system(size: 16, weight: .heavy))
                                        .monospacedDigit()
                                    Text(zman.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(Theme.amberInk)
                                .background(Theme.amberGround, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
                .padding(14)
                .cardSurface()
            }
            .buttonStyle(.plain)
        }
    }
}

/// The vivid emerald card with what is left to live on this month.
struct MonthHeroCard: View {
    let month: MonthSummary

    private var isOver: Bool { month.remaining < 0 }

    private var subtitle: String {
        if month.daysLeft <= 0 { return "סיכום החודש" }
        if isOver { return "עוד \(month.daysLeft) ימים עד סוף החודש" }
        return "כ־\(Money.text(month.perWeek)) לשבוע · עוד \(month.daysLeft) ימים"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isOver ? "חריגה מהתקציב לחיים החודש" : "נשאר לחיות ממנו החודש")
                .font(.system(size: 15, weight: .semibold))
                .opacity(0.9)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("₪")
                    .font(.system(size: 28, weight: .bold))
                Text(Money.digits(month.remaining))
                    .font(.system(size: 56, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Money.digits(month.remaining)) שקלים")

            ProgressView(value: month.spentShare)
                .tint(.white)
                .padding(.top, 2)

            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.9)
                .padding(.top, 2)

            HStack(spacing: 0) {
                stat(month.incomeIsEstimate ? "הכנסות (צפי)" : "הכנסות", Money.text(month.income))
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
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x047857), Color(hex: 0x065F46), Color(hex: 0x0F766E)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color(hex: 0x34D399).opacity(0.55))
                    .frame(width: 200, height: 200)
                    .blur(radius: 50)
                    .offset(x: 120, y: -90)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color(hex: 0x047857).opacity(0.45), radius: 22, y: 14)
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
        .buttonStyle(.plain)
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
            ProgressView(value: goal.share)
                .tint(.white)
            Text("\(Money.text(goal.saved)) מתוך \(Money.text(goal.target))")
                .font(.system(size: 12, weight: .medium))
                .opacity(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 164, height: 150, alignment: .leading)
        .background(goal.artwork.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
