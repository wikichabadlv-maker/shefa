import SwiftData
import SwiftUI

@main
struct ShefaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .tint(Theme.accent)
        }
        .modelContainer(for: [LedgerEntry.self, MerchantRule.self])
    }
}
