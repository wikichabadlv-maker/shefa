import SwiftUI

/// An app installed with a free Apple account stops opening seven days after
/// it was signed. This reads when that happens, from the profile inside the app.
enum Signing {
    /// When the current signature runs out; nil when it cannot be read,
    /// for example in the simulator.
    static let expiry: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    /// Whole days left; nil when unknown or when the profile lasts for months.
    static var daysLeft: Int? {
        guard let expiry, expiry.timeIntervalSinceNow < 8 * 86_400 else { return nil }
        return max(Int((expiry.timeIntervalSinceNow / 86_400).rounded(.down)), 0)
    }

    static let steps = "מדליקים LocalDevVPN, פותחים את SideStore, ובלשונית My Apps לוחצים Refresh All."

    /// Two reminders: two days before the end (five days after signing) and
    /// on the last day. Neither falls on Shabbat.
    static func reminders(now: Date = .now) -> [(Date, String, String)] {
        guard let expiry, expiry.timeIntervalSince(now) < 8 * 86_400 else { return [] }
        let calendar = Calendar.current
        var result: [(Date, String, String)] = []
        for (daysBefore, title) in [(2, "הגיע הזמן לחדש את שפע"), (1, "מחר שפע תפסיק להיפתח")] {
            guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: expiry),
                  var date = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) else { continue }
            if calendar.component(.weekday, from: date) == 7 {
                // Shabbat: the first reminder moves to Friday, the last to the evening after.
                date = daysBefore == 2 ? date.addingTimeInterval(-86_400) : date.addingTimeInterval(11 * 3600)
            }
            if date > now, date < expiry {
                result.append((date, title, steps))
            }
        }
        return result
    }
}

/// Shown on the home screen when the signature is about to run out.
struct RenewBanner: View {
    var body: some View {
        if let days = Signing.daysLeft, days <= 2 {
            HStack(alignment: .top, spacing: 12) {
                ArtworkIcon(artwork: Theme.amber, symbol: "arrow.triangle.2.circlepath")
                VStack(alignment: .leading, spacing: 2) {
                    Text(days == 0 ? "היום האחרון לחדש את האפליקציה"
                         : (days == 1 ? "נשאר יום אחד לחדש את האפליקציה" : "הגיע הזמן לחדש את האפליקציה"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.amberInk)
                    Text(Signing.steps + " אחרת היא תפסיק להיפתח.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.amberInk.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.amberGround, in: Theme.cardShape)
            .accessibilityElement(children: .combine)
        }
    }
}
