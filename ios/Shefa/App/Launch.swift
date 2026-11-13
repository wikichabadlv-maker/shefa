import Foundation
import Observation

/// Lets a test run open the app straight on a given screen, for example
/// `-screen finance-overview`. Normal launches ignore all of this.
enum Launch {
    static let screen = UserDefaults.standard.string(forKey: "screen") ?? ""

    static var tab: AppTab {
        if screen.hasPrefix("finance") { return .finance }
        switch screen {
        case "schedule", "routine", "routine-edit", "routine-over", "routine-end", "routines", "erev",
             "erev-new": return .schedule
        case "tasks", "task-stuck", "plan-day", "plan-day-pick", "plan-day-first",
             "close-day", "close-day-left", "close-day-next", "week-new", "week-pick": return .tasks
        case "notes", "achievements", "settings", "zmanim", "books", "study": return .more
        case "task", "shopping": return .tasks
        case "more": return .more
        default: return .home
        }
    }

    static var financeSection: FinanceSection {
        switch screen {
        case "finance-budget", "finance-budget-edit": return .budget
        case "finance-maaser", "finance-rules": return .maaser
        case "finance-savings", "finance-goal", "finance-fund": return .savings
        case "finance-transactions", "finance-entry", "finance-review": return .transactions
        default: return .overview
        }
    }

    /// A screen inside the finance tab to open right away.
    static var financeRoute: FinanceRoute? {
        switch screen {
        case "finance-horizon", "finance-planned", "finance-balance": return .horizon
        case "finance-salary": return .salary
        case "finance-status": return .status
        default: return nil
        }
    }

    /// Paints the month card in one of its moods, for a test run: "watch" or "over".
    static var mood: MonthSummary.Mood? {
        switch UserDefaults.standard.string(forKey: "mood") ?? "" {
        case "watch": return .watch
        case "over": return .over
        case "calm": return .calm
        default: return nil
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
        case "books": return ["books"]
        case "study": return ["study"]
        default: return []
        }
    }

    /// The step a day's sitting opens on, for a test run.
    static var flowStep: Int {
        switch screen {
        case "plan-day-pick", "close-day-left": return 1
        case "plan-day-first", "close-day-next": return 2
        default: return 0
        }
    }

    /// Scroll position for long screens: "top" or a named anchor.
    static let anchor = UserDefaults.standard.string(forKey: "anchor") ?? ""

    /// How long the opening curtain stays before it lifts. A test run has none.
    static let curtain: Double = screen.isEmpty ? 0.75 : 0
}

/// Lets one screen send the user to a specific place in another.
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var financeSection: FinanceSection = Launch.financeSection
    var tasksSection: TasksSection = Launch.screen == "shopping" ? .shopping : .tasks
    /// What the user chose to keep on the floating bar today.
    var deckPin = UserDefaults.standard.string(forKey: "deck.pin") ?? ""
    /// The area open inside "More".
    var morePath: [String] = Launch.morePath
    var isQuickAdding = false
    var isNowPlaying = false
    /// A screen pushed inside the finance tab.
    var financeRoute: FinanceRoute? = Launch.financeRoute
    /// The quick sorting of lines that wait for an answer.
    var isReviewing = Launch.screen == "finance-review"
    /// The morning sitting that builds the day, and the evening one that closes it.
    var isPlanningDay = false
    var isClosingDay = false
    /// The full screen of a routine that is being played.
    var isRoutinePlaying = false
    /// A place in the schedule screen to travel to, such as "routines".
    var scheduleAnchor = ""
    /// The choosing of the week's three things.
    var isPickingWeek = false
    /// Counts up when the week's three changed, so what shows them reads them again.
    var weekTurn = 0

    /// Where a tapped reminder leads.
    func open(_ place: String) {
        let routine = "routine:"
        if place.hasPrefix(routine) {
            // The reminder said it is time to begin: a tap begins.
            let id: String = String(place.dropFirst(routine.count))
            if RoutineRun.shared.routine?.id != id, let found = Routines.shared.all.first(where: { $0.id == id }) {
                RoutineRun.shared.start(found.remaining())
            }
            isRoutinePlaying = RoutineRun.shared.isActive
            return
        }
        switch place {
        case "plan": isPlanningDay = true
        case "week": isPickingWeek = true
        case "close": isClosingDay = true
        case "now": isNowPlaying = true
        case "routine": isRoutinePlaying = RoutineRun.shared.isActive
        default: break
        }
    }
}
