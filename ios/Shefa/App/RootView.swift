import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case home, schedule, finance, tasks, more
}

/// The app shell: a native glass tab bar, a separate round button for search
/// and the remaining areas, and the current schedule task floating above it.
struct RootView: View {
    @State private var selection: AppTab = .home
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView(selection: $selection) {
            Tab("בית", systemImage: "house.fill", value: AppTab.home) {
                HomeView(selection: $selection)
            }
            Tab("לו״ז", systemImage: "clock.fill", value: AppTab.schedule) {
                ComingSoonView(title: "לו״ז", symbol: "clock.fill",
                               text: "לוח יום חי עם זמני היום ותכנון חכם.")
            }
            Tab("פיננסים", systemImage: "creditcard.fill", value: AppTab.finance) {
                FinanceView()
            }
            Tab("מטלות", systemImage: "checklist", value: AppTab.tasks) {
                ComingSoonView(title: "מטלות", symbol: "checklist",
                               text: "מטלות אישיות ומשותפות לשניכם.")
            }
            Tab(value: AppTab.more, role: .search) {
                MoreView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NowTaskBar(task: SampleData.currentTask)
        }
        .task {
            Ledger.seedIfNeeded(in: context)
            Ledger.seedPlanningIfNeeded(in: context)
        }
    }
}

#Preview {
    RootView()
        .environment(\.layoutDirection, .rightToLeft)
        .modelContainer(for: [LedgerEntry.self, MerchantRule.self, BudgetLine.self, SavingsGoal.self], inMemory: true)
}
