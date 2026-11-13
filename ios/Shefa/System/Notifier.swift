import Foundation
import SwiftData
import UserNotifications

/// Local reminders: the start of each part of the day, tasks that are due,
/// and the halachic times the family chose to be reminded of.
@MainActor
final class Notifier {
    static let shared = Notifier()

    static let scheduleKey = "notifySchedule"
    static let tasksKey = "notifyTasks"
    static let shmaKey = "notifyShma"
    static let candlesKey = "notifyCandles"
    static let sunsetKey = "notifySunset"

    private var pending: Task<Void, Never>?

    private init() {}

    private func isOn(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    /// Asks for permission the first time. Returns whether reminders are allowed.
    func askPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Call after any change; rebuilds the reminders shortly afterwards.
    func refresh(in context: ModelContext) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.rebuild(in: context)
        }
    }

    private func rebuild(in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        center.removePendingNotificationRequests(withIdentifiers: (0..<60).map { "shefa-\($0)" })

        let calendar = Calendar.current
        let now = Date.now
        var requests: [(Date, String, String)] = []

        if isOn(Self.scheduleKey, default: true) {
            let items = ((try? context.fetch(FetchDescriptor<ScheduleItem>())) ?? []).filter { !$0.removed }
            for offset in 0..<5 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                for item in items where item.isOn(day) {
                    guard let start = calendar.date(bySettingHour: item.startMinute / 60, minute: item.startMinute % 60,
                                                    second: 0, of: day), start > now else { continue }
                    requests.append((start, item.title, "מתחיל עכשיו · \(NowStatus.duration(item.durationMinutes))"))
                }
            }
        }

        if isOn(Self.tasksKey, default: true) {
            let tasks = ((try? context.fetch(FetchDescriptor<ListItem>())) ?? [])
                .filter { !$0.removed && !$0.isDone && $0.kind == ListItem.task && $0.due != nil }
            let byDay = Dictionary(grouping: tasks) { calendar.startOfDay(for: $0.due ?? now) }
            for (day, list) in byDay {
                guard let time = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: day), time > now else { continue }
                let title = list.count == 1 ? "מטלה להיום" : "\(list.count) מטלות להיום"
                let body = list.prefix(3).map(\.title).joined(separator: " · ")
                requests.append((time, title, body))
            }
        }

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let zmanim = Zmanim(day: day)
            for zman in zmanim.list {
                let wanted = (zman.id == "shma" && isOn(Self.shmaKey, default: false))
                    || (zman.id == "candles" && isOn(Self.candlesKey, default: true))
                    || (zman.id == "shkia" && isOn(Self.sunsetKey, default: false))
                let lead: Double = zman.id == "candles" ? 40 : 30
                let time = zman.date.addingTimeInterval(-lead * 60)
                if wanted, time > now {
                    requests.append((time, "\(zman.title) בעוד \(Int(lead)) דקות",
                                     "בשעה \(zmanim.clock(zman.date)) · \(zmanim.city.name)"))
                }
            }
        }

        for (index, request) in requests.sorted(by: { $0.0 < $1.0 }).prefix(60).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = request.1
            content.body = request.2
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: request.0)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "shefa-\(index)", content: content, trigger: trigger))
        }
    }

    /// A single reminder for the end of a focus session.
    func scheduleFocusEnd(at date: Date, title: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["shefa-focus"])
        let content = UNMutableNotificationContent()
        content.title = "המיקוד הסתיים"
        content.body = title
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: "shefa-focus", content: content, trigger: trigger))
    }

    func cancelFocusEnd() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["shefa-focus"])
    }
}

/// Shows reminders also while the app is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
