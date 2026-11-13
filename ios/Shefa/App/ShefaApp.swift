import SwiftData
import SwiftUI

@main
struct ShefaApp: App {
    /// Opens the on-device store. If a new version cannot read an old store,
    /// it starts a fresh one: everything important is restored by the next sync.
    static let container: ModelContainer = {
        let schema = Schema([
            LedgerEntry.self, MerchantRule.self, BudgetLine.self, SavingsGoal.self, ListItem.self,
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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .tint(Theme.accent)
        }
        .modelContainer(Self.container)
    }
}
