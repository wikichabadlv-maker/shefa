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
            Tab(value: AppTab.more, role: .search) {
                MoreView()
                    .tabEntrance(selection == .more)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NowTaskBar()
        }
        .sheet(isPresented: $router.isQuickAdding) {
            QuickAddSheet()
        }
        .sheet(isPresented: $router.isNowPlaying) {
            NowPlayingView()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            FocusTimer.shared.tick(now: now)
        }
        .task {
            ExcelImport.importIfNeeded(in: context)
            Ledger.removeExampleGoals(in: context)
            Habit.addDefaultsIfNeeded(in: context)
            if Launch.demo { DemoData.fill(context) }
            if Launch.screen == "quick" { router.isQuickAdding = true }
            if Launch.screen == "now" { router.isNowPlaying = true }
            if UserDefaults.standard.string(forKey: City.storageKey) == City.deviceID {
                LocationFinder.shared.refresh()
            }
            Notifier.shared.refresh(in: context)
            await Backend.shared.sync(into: context)
        }
    }
}

#Preview {
    RootView()
        .environment(\.layoutDirection, .rightToLeft)
        .modelContainer(for: [LedgerEntry.self, MerchantRule.self, BudgetLine.self, SavingsGoal.self, ListItem.self, CustomSub.self, ScheduleItem.self, Habit.self, Book.self], inMemory: true)
}
