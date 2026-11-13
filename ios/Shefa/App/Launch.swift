import Foundation

/// Lets a test run open the app straight on a given screen, for example
/// `-screen finance-overview`. Normal launches ignore all of this.
enum Launch {
    static let screen = UserDefaults.standard.string(forKey: "screen") ?? ""

    static var tab: AppTab {
        if screen.hasPrefix("finance") { return .finance }
        switch screen {
        case "schedule": return .schedule
        case "tasks": return .tasks
        case "more": return .more
        default: return .home
        }
    }

    static var financeSection: FinanceSection {
        switch screen {
        case "finance-overview": return .overview
        case "finance-budget": return .budget
        case "finance-savings": return .savings
        default: return screen == "finance-transactions" ? .transactions : .overview
        }
    }

    /// Scroll position for long screens: "top" or a named anchor.
    static let anchor = UserDefaults.standard.string(forKey: "anchor") ?? ""
}
