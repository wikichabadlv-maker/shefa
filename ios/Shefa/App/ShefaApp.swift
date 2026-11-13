import SwiftData
import SwiftUI
import UserNotifications

@main
struct ShefaApp: App {
    /// Opens the on-device store. If a new version cannot read an old store,
    /// it starts a fresh one: everything important is restored by the next sync.
    static let container: ModelContainer = {
        let schema = Schema([
            LedgerEntry.self, MerchantRule.self, BudgetLine.self, SavingsGoal.self, ListItem.self,
            CustomSub.self, ScheduleItem.self, Habit.self, Book.self,
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            let store = URL.applicationSupportDirectory.appending(path: "default.store").path
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: store + suffix)
            }
            do {
                return try ModelContainer(for: schema)
            } catch {
                fatalError("Could not open the data store: \(error)")
            }
        }
    }()

    @AppStorage("appearance") private var appearance = "system"

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    private var scheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .tint(Theme.accent)
                .preferredColorScheme(scheme)
        }
        .modelContainer(Self.container)
    }
}
