import SwiftData
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
            }
            Tab("לו״ז", systemImage: "clock.fill", value: AppTab.schedule) {
                ScheduleView()
            }
            Tab("פיננסים", systemImage: "creditcard.fill", value: AppTab.finance) {
                FinanceView()
            }
            Tab("מטלות", systemImage: "checklist", value: AppTab.tasks) {
                NavigationStack {
                    CheckListView(kind: ListItem.task, title: "מטלות", placeholder: "מטלה חדשה",
                                  emptyText: "כתבו מטלה ולחצו על סיום במקלדת כדי להוסיף אותה.")
                }
            }
            Tab(value: AppTab.more, role: .search) {
                MoreView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NowTaskBar(selection: $selection)
        }
        .sheet(isPresented: $router.isQuickAdding) {
            QuickAddSheet()
        }
        .task {
            ExcelImport.importIfNeeded(in: context)
            Ledger.removeExampleGoals(in: context)
            if Launch.demo { DemoData.fill(context) }
            await Backend.shared.sync(into: context)
        }
    }
}

#Preview {
    RootView()
        .environment(\.layoutDirection, .rightToLeft)
        .modelContainer(for: [LedgerEntry.self, MerchantRule.self, BudgetLine.self, SavingsGoal.self, ListItem.self, CustomSub.self, ScheduleItem.self], inMemory: true)
}
