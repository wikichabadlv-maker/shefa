import Foundation
import Observation

/// Lets a test run open the app straight on a given screen, for example
/// `-screen finance-overview`. Normal launches ignore all of this.
enum Launch {
    static let screen = UserDefaults.standard.string(forKey: "screen") ?? ""

    static var tab: AppTab {
        if screen.hasPrefix("finance") { return .finance }
        switch screen {
        case "schedule": return .schedule
        case "tasks": return .tasks
        case "notes", "achievements", "settings", "zmanim": return .more
        case "task": return .tasks
        case "more": return .more
        default: return .home
        }
    }

    static var financeSection: FinanceSection {
        switch screen {
        case "finance-overview": return .overview
        case "finance-budget": return .budget
        case "finance-savings", "finance-goal": return .savings
        case "finance-entry": return .transactions
        default: return screen == "finance-transactions" ? .transactions : .overview
        }
    }

    /// The month the finance screens open on, for example `-month 2026-10`.
    static var month: Date {
        let text = UserDefaults.standard.string(forKey: "month") ?? ""
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: 15, hour: 12))
        else { return .now }
        return date
    }

    /// A sheet to open right away: "quick", "goal" or "entry".
    static let sheet = UserDefaults.standard.string(forKey: "sheet") ?? ""

    /// Fills the simulator with a few lines so every screen has something to show.
    static let demo = UserDefaults.standard.bool(forKey: "demo")

    /// The area inside "More" to open right away.
    static var morePath: [String] {
        switch screen {
        case "notes": return ["notes"]
        case "achievements": return ["achievements"]
        case "settings": return ["settings"]
        case "zmanim": return ["zmanim"]
        default: return []
        }
    }

    /// Scroll position for long screens: "top" or a named anchor.
    static let anchor = UserDefaults.standard.string(forKey: "anchor") ?? ""
}

/// Lets one screen send the user to a specific place in another.
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var financeSection: FinanceSection = Launch.financeSection
    var isQuickAdding = false
    var isNowPlaying = false
}
