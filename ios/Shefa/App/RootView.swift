import SwiftData
import Combine
import SwiftUI

enum AppTab: Hashable {
    case home, schedule, finance, tasks, more
}

/// The app shell: a native glass tab bar, a separate round button for search
/// and the remaining areas, and the current schedule task floating above it.
struct RootView: View {
    @State private var selection: AppTab = Launch.tab
    @State private var router = AppRouter.shared
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var ticks = 0
    /// The opening curtain; a test run goes straight to its screen.
    @State private var showsSplash = Launch.screen.isEmpty

    var body: some View {
        TabView(selection: $selection) {
            Tab("בית", systemImage: "house.fill", value: AppTab.home) {
                HomeView(selection: $selection)
                    .tabEntrance(selection == .home)
            }
            Tab("לו״ז", systemImage: "clock.fill", value: AppTab.schedule) {
                ScheduleView()
                    .tabEntrance(selection == .schedule)
            }
            Tab("פיננסים", systemImage: "creditcard.fill", value: AppTab.finance) {
                FinanceView()
                    .tabEntrance(selection == .finance)
            }
            Tab("מטלות", systemImage: "checklist", value: AppTab.tasks) {
                TasksView()
                    .tabEntrance(selection == .tasks)
            }
            Tab("עוד", systemImage: "square.grid.2x2.fill", value: AppTab.more) {
                MoreView()
                    .tabEntrance(selection == .more)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NowTaskBar()
        }
        .momentHost()
        .overlay {
            ZStack {
                if showsSplash {
                    Splash()
                        .transition(.opacity.combined(with: .scale(scale: 1.08)))
                }
            }
        }
        .task {
            guard showsSplash else { return }
            try? await Task.sleep(for: .seconds(Launch.curtain))
            withAnimation(.easeIn(duration: 0.4)) { showsSplash = false }
        }
        .sheet(isPresented: $router.isQuickAdding) {
            QuickAddSheet()
        }
        .sheet(isPresented: $router.isNowPlaying) {
            NowPlayingView()
        }
        .fullScreenCover(isPresented: $router.isPlanningDay) {
            PlanDayFlow()
        }
        .fullScreenCover(isPresented: $router.isClosingDay) {
            CloseDayFlow()
        }
        .fullScreenCover(isPresented: $router.isRoutinePlaying) {
            RoutinePlayer()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            FocusTimer.shared.tick(now: now)
            // Anything changed on this phone reaches the cloud within a minute.
            ticks += 1
            if ticks % 60 == 0 { Task { await Backup.shared.sync(in: context) } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                try? context.save()
                Task { await SharedSync.shared.run(in: context) }
            } else {
                // The app may have slept through midnight.
                startDay()
                RoutineRun.shared.dropIfStale()
            }
        }
        .task {
            // A demo run shows made-up lines only, never the family's own.
            if !Launch.demo { ExcelImport.importIfNeeded(in: context) }
            Ledger.removeExampleGoals(in: context)
            Habit.addDefaultsIfNeeded(in: context)
            if Launch.demo { DemoData.fill(context) }
            startDay()
            if Launch.screen.hasPrefix("plan-day") { router.isPlanningDay = true }
            if Launch.screen.hasPrefix("close-day") { router.isClosingDay = true }
            if Launch.screen == "quick" { router.isQuickAdding = true }
            if Launch.screen == "now" { router.isNowPlaying = true }
            if ["routine", "routine-over", "routine-end"].contains(Launch.screen),
               let first = Routines.shared.all.first {
                // A test run opens in the middle of the second step, or past
                // the time of the first, or on the last step just before the end.
                RoutineRun.shared.start(first, now: Date.now.addingTimeInterval(-26 * 60))
                if Launch.screen == "routine" {
                    _ = RoutineRun.shared.finish(done: true, now: Date.now.addingTimeInterval(-9 * 60))
                }
                if Launch.screen == "routine-end" {
                    for _ in 1..<max(first.steps.count, 1) {
                        _ = RoutineRun.shared.finish(done: true, now: Date.now.addingTimeInterval(-60))
                    }
                }
                router.isRoutinePlaying = true
            }
            if Launch.screen == "moment" {
                Moments.shared.show(symbol: "checkmark", title: "היום הושלם",
                                    text: "כל מה שתוכנן להיום נעשה. 4 ימים ברצף.", artwork: Theme.blue)
            }
            if UserDefaults.standard.string(forKey: City.storageKey) == City.deviceID {
                LocationFinder.shared.refresh()
            }
            Notifier.shared.refresh(in: context)
            await Backend.shared.sync(into: context)
            await SharedSync.shared.run(in: context)
        }
    }

    /// What a new day asks for, done once a day: tasks that were left behind
    /// are counted, and the parts of the day that follow the sun move to
    /// today's times.
    private func startDay() {
        let key = "dayStarted"
        let today: String = DayKey.of()
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)
        TaskRules.carryOver(in: context)
        ScheduleItem.followAnchors(in: context)
        Notifier.shared.refresh(in: context)
    }
}

#Preview {
    RootView()
        .environment(\.layoutDirection, .rightToLeft)
        .modelContainer(for: [LedgerEntry.self, MerchantRule.self, BudgetLine.self, SavingsGoal.self, ListItem.self, CustomSub.self, ScheduleItem.self, Habit.self, Book.self], inMemory: true)
}
