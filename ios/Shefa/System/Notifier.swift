import Foundation
import SwiftData
import UserNotifications

/// Local reminders: the start of each part of the day, the first step the
/// family set for itself, the two sittings, a routine that has to begin
/// now to end in time, and the halachic times they chose to be reminded
/// of. Few, and none from candle lighting until Shabbat or a festival is out.
@MainActor
final class Notifier {
    static let shared = Notifier()

    /// One reminder on its way.
    private struct Planned {
        let date: Date
        let title: String
        let body: String
        /// Where a tap on it leads: "plan", "close", "now", "routine:" with
        /// the routine's id, or nowhere.
        var open: String = ""
    }

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

    /// Whether a moment falls inside Shabbat or a festival: from candle
    /// lighting until the day is out.
    nonisolated static func isHolyTime(_ date: Date) -> Bool {
        let kind: JewishDay = JewishDay.of(date)
        guard kind.isRest || kind.hasCandles else { return false }
        let times: [Zman] = Zmanim(day: date).list
        if kind.isRest {
            // When another holy day follows, the whole day is inside.
            guard let end = times.first(where: { $0.id == "shabbat-end" }) else { return true }
            return date < end.date
        }
        guard let candles = times.first(where: { $0.id == "candles" }) else { return false }
        return date >= candles.date
    }

    /// When the holy time that holds a moment is out; nil for an ordinary moment.
    nonisolated static func holyEnd(for date: Date) -> Date? {
        guard isHolyTime(date) else { return nil }
        for offset in 0..<4 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: date) else { break }
            if let end = Zmanim(day: day).list.first(where: { $0.id == "shabbat-end" }), end.date > date {
                return end.date
            }
        }
        return nil
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
        var planned: [Planned] = []
        let hasCoach: Bool = isOn(Coach.enabledKey, default: true)

        if isOn(Self.scheduleKey, default: true) {
            let items = ((try? context.fetch(FetchDescriptor<ScheduleItem>())) ?? []).filter { !$0.removed }
            for offset in 0..<5 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                for item in items where item.isOn(day) {
                    // A part that follows the sun starts elsewhere on each day.
                    let minute: Int = item.start(on: day)
                    guard let start = calendar.date(bySettingHour: minute / 60, minute: minute % 60,
                                                    second: 0, of: day), start > now else { continue }
                    planned.append(Planned(date: start, title: item.title,
                                           body: "מתחיל עכשיו · \(NowStatus.duration(item.durationMinutes))"))
                }
            }
        }

        // The morning brief already says what waits today; without it, a line of its own.
        if isOn(Self.tasksKey, default: true) && !(hasCoach && Coach.morningMinute != nil) {
            let tasks = ((try? context.fetch(FetchDescriptor<ListItem>())) ?? [])
                .filter { !$0.removed && !$0.isDone && $0.kind == ListItem.task && $0.due != nil }
            let byDay = Dictionary(grouping: tasks) { calendar.startOfDay(for: $0.due ?? now) }
            for (day, list) in byDay {
                guard let time = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: day), time > now else { continue }
                let title = list.count == 1 ? "מטלה להיום" : "\(list.count) מטלות להיום"
                let body = list.prefix(3).map(\.title).joined(separator: " · ")
                planned.append(Planned(date: time, title: title, body: body, open: "plan"))
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
                    planned.append(Planned(date: time, title: "\(zman.title) בעוד \(Int(lead)) דקות",
                                           body: "בשעה \(zmanim.clock(zman.date)) · \(zmanim.city.name)"))
                }
            }
        }

        planned += routineRequests(now: now)

        // What must not be lost waits for the holy day to be out.
        for item in Signing.reminders(now: now) + CalendarFeed.shared.reminders(now: now) {
            var date: Date = item.0
            if let end = Notifier.holyEnd(for: date) { date = end.addingTimeInterval(20 * 60) }
            planned.append(Planned(date: date, title: item.1, body: item.2))
        }

        if hasCoach {
            planned += coachRequests(in: context, now: now)
        }

        let ready: [Planned] = planned
            .filter { $0.date > now && !Notifier.isHolyTime($0.date) }
            .sorted { $0.date < $1.date }
        for (index, item) in ready.prefix(60).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            if !item.open.isEmpty {
                content.userInfo = ["open": item.open]
                // The buttons go by the kind of place, not by which one it is.
                content.categoryIdentifier = "shefa-" + String(item.open.prefix { $0 != ":" })
            }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "shefa-\(index)", content: content, trigger: trigger))
        }
    }

    /// A routine the family asked to be reminded of says when to begin so as
    /// to end in time: five minutes before the last minute that still works,
    /// on its own days, and not on a day it was already begun.
    private func routineRequests(now: Date) -> [Planned] {
        let calendar = Calendar.current
        var result: [Planned] = []
        for routine in Routines.shared.all where routine.reminds {
            for offset in 0..<5 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                      let start = routine.startBy(on: day) else { continue }
                if offset == 0, RoutineRun.played(on: day).contains(routine.id) { continue }
                let minute: Int = max(start - 5, 0)
                guard let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                      date > now else { continue }
                var body: String = "כדי לסיים עד \(ScheduleItem.clock(routine.goalMinute ?? 0)) מתחילים ב־\(ScheduleItem.clock(start)). \(routine.summary)."
                if routine.isForCandles {
                    body = "כדי להספיק עד הדלקת הנרות מתחילים ב־\(ScheduleItem.clock(start)). נשארו \(NowStatus.duration(routine.left(on: day))) של הכנות."
                }
                result.append(Planned(date: date, title: routine.title, body: body, open: "routine:" + routine.id))
            }
        }
        return result
    }

    /// The coach's own reminders: a morning brief, the first step of the
    /// day at the minute the family set, closing the day, and the shopping
    /// trip. A day of rest gets none of the working day's lines.
    private func coachRequests(in context: ModelContext, now: Date) -> [Planned] {
        let calendar = Calendar.current
        var result: [Planned] = []
        let lists = ((try? context.fetch(FetchDescriptor<ListItem>())) ?? [])
        let tasks = lists.filter { !$0.removed && !$0.isDone && $0.kind == ListItem.task }
        let shopping = lists.filter { $0.kind == ListItem.shopping }
        let book = ((try? context.fetch(FetchDescriptor<Book>())) ?? []).first { !$0.removed && !$0.isFinished }
        let cue: DayJournal.Intention? = DayJournal.intention
        let eveningRests: Bool = DayJournal.eveningRests(now: now)
        var evenings: [Date] = []

        func time(_ day: Date, _ minute: Int) -> Date? {
            guard let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day),
                  date > now else { return nil }
            return date
        }

        for offset in 0..<4 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let isToday = offset == 0
            let kind: JewishDay = JewishDay.of(day)
            let todays = tasks.filter { item in
                guard let due = item.due else { return isToday && item.isForToday }
                return calendar.isDate(due, inSameDayAs: day) || (isToday && item.isForToday)
            }

            if !kind.isRest, let minute = Coach.morningMinute, let date = time(day, minute) {
                var lines: [String] = []
                if let name = kind.title { lines.append(name) }
                if !todays.isEmpty { lines.append(todays.count == 1 ? "מטלה אחת להיום" : "\(todays.count) מטלות להיום") }
                if StudyLog.tracked.contains(DailyStudy.rambam) { lines.append("רמב״ם: " + DailyStudy.rambamText(on: day)) }
                if StudyLog.tracked.contains(DailyStudy.chumash) { lines.append("חומש: " + DailyStudy.chumashText(on: day)) }
                let waiting = StudyLog.gaps().count
                if isToday, waiting > 0 { lines.append("השלמות: \(waiting) שיעורים מחכים") }
                if calendar.component(.weekday, from: day) == 1 {
                    lines.append("שבוע חדש: מה שלושת הדברים שיעשו אותו טוב?")
                }
                let isPlanned: Bool = isToday && DayJournal.isPlannedToday
                result.append(Planned(date: date, title: "בוקר טוב · \(HebrewDate.text(day))",
                                      body: lines.joined(separator: "\n"), open: isPlanned ? "" : "plan"))
            }

            // The first step, at the minute and the place the family named.
            var hasCue = false
            if isToday, let cue, let date = time(day, cue.minute),
               let task = tasks.first(where: { $0.id == cue.taskID }) {
                let place: String = cue.place.isEmpty ? "" : " · " + cue.place
                result.append(Planned(date: date, title: "הצעד הראשון של היום",
                                      body: task.title + place + ". זו השעה שקבעתם.", open: "now"))
                hasCue = true
            }

            if !kind.isRest, !hasCue, !todays.isEmpty, let minute = Coach.peakMinute, let date = time(day, minute) {
                let top = todays.sorted { $0.priority > $1.priority }.first
                result.append(Planned(date: date, title: "השעה הצלולה שלכם",
                                      body: top.map { "זה הזמן ל״\($0.title)״. עשרים דקות בלי הפרעות." }
                                          ?? "זה הזמן למטלה הכי חשובה של היום. עשרים דקות בלי הפרעות.",
                                      open: "now"))
            }

            let isClosed: Bool = isToday && DayJournal.isClosedToday
            if !kind.isRest, !eveningRests, !isClosed, let minute = Coach.eveningMinute, let date = time(day, minute),
               !Notifier.isHolyTime(date) {
                var body = "דקה אחת: מה נעשה היום, ומה עובר למחר."
                if isToday && todays.isEmpty {
                    body = "הכול נעשה. מבט קצר על מחר, וסוגרים."
                } else if isToday {
                    let remaining: String = todays.count == 1 ? "נשארה מטלה אחת פתוחה." : "נשארו \(todays.count) מטלות פתוחות."
                    body = remaining + " דקה אחת: מה עובר למחר, ומה משתחרר."
                }
                if let book { body += " ועמוד אחד ב״\(book.title)״ לפני השינה." }
                let left = StudyLog.tracked.filter { !StudyLog.isDone($0, on: day) }.map { StudyText.name($0) }
                if isToday, !left.isEmpty { body = "נשאר ללמוד היום: " + left.joined(separator: ", ") + ". " + body }
                result.append(Planned(date: date, title: "סוגרים את היום", body: body, open: "close"))
                evenings.append(day)
            }

            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            if let weekday = Coach.shoppingWeekday, calendar.component(.weekday, from: tomorrow) == weekday,
               let date = time(day, 20 * 60) {
                let open = shopping.filter { !$0.removed && !$0.isDone }
                let due = ShoppingMemory.due(shopping, now: tomorrow).prefix(4).map(\.title)
                var body = open.isEmpty ? "הרשימה עוד ריקה." : "\(open.count) מוצרים ברשימה."
                if !due.isEmpty { body += " כנראה נגמרו גם: " + due.joined(separator: ", ") + "." }
                result.append(Planned(date: date, title: "מחר קניות", body: body))
            }

            // Without a morning brief, the new week gets a line of its own.
            if Coach.morningMinute == nil, calendar.component(.weekday, from: day) == 1,
               let date = time(day, 9 * 60 + 30), !isToday {
                result.append(Planned(date: date, title: "שבוע חדש",
                                      body: "מה שלושת הדברים שיעשו את השבוע הזה טוב? בחרו אותם עכשיו.", open: "plan"))
            }
        }
        DayJournal.noteEveningAsked(evenings)

        // Without a fixed shopping day: say so when things run out.
        if Coach.shoppingWeekday == nil {
            for offset in 0..<4 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                      let date = time(day, 17 * 60), !Notifier.isHolyTime(date) else { continue }
                let due = ShoppingMemory.due(shopping, now: day).prefix(4).map(\.title)
                if !due.isEmpty {
                    result.append(Planned(date: date, title: "כנראה נגמר בבית",
                                          body: due.joined(separator: ", ") + ". להוסיף לרשימת הקניות?"))
                    break
                }
            }
        }
        return result
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

    /// A single signal for the moment a routine's step runs out of its
    /// time, with a button that moves on to the next step. None inside
    /// Shabbat or a festival.
    nonisolated static func scheduleStepEnd(at date: Date, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["shefa-step"])
        guard date.timeIntervalSinceNow > 1, !isHolyTime(date) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["open": "routine"]
        content.categoryIdentifier = "shefa-step"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: "shefa-step", content: content, trigger: trigger))
    }

    nonisolated static func cancelStepEnd() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["shefa-step"])
    }
}

/// Shows reminders also while the app is open, and takes the user where a
/// tapped reminder leads.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    /// The buttons under a reminder: straight into the sitting it speaks of,
    /// ten more minutes before the first step, and, under the signal that a
    /// routine's step is over, on to the next step without opening the app.
    static func registerActions() {
        let plan = UNNotificationAction(identifier: "plan", title: "לבנות את היום", options: [.foreground])
        let close = UNNotificationAction(identifier: "close", title: "לסגור את היום", options: [.foreground])
        let start = UNNotificationAction(identifier: "now", title: "להתחיל עכשיו", options: [.foreground])
        let later = UNNotificationAction(identifier: "later", title: "בעוד עשר דקות", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "shefa-plan", actions: [plan], intentIdentifiers: []),
            UNNotificationCategory(identifier: "shefa-close", actions: [close], intentIdentifiers: []),
            UNNotificationCategory(identifier: "shefa-now", actions: [start, later], intentIdentifiers: []),
            UNNotificationCategory(identifier: "shefa-routine", actions: [start, later], intentIdentifiers: []),
            UNNotificationCategory(identifier: "shefa-step", actions: [
                UNNotificationAction(identifier: "step-done", title: "סיימתי, הלאה", options: []),
                UNNotificationAction(identifier: "step-more", title: "עוד חמש דקות", options: []),
            ], intentIdentifiers: []),
        ])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let place: String = content.userInfo["open"] as? String ?? ""
        if response.actionIdentifier == "step-done" || response.actionIdentifier == "step-more" {
            // Done here and now, before the app goes back to sleep.
            let isDone: Bool = response.actionIdentifier == "step-done"
            let work: () -> Void = {
                if isDone {
                    _ = RoutineRun.shared.finish(done: true)
                } else {
                    RoutineRun.shared.extend(minutes: 5)
                }
            }
            if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        } else if response.actionIdentifier == "later" {
            // The same reminder once more, ten minutes on; never into Shabbat or a festival.
            guard !Notifier.isHolyTime(Date.now.addingTimeInterval(600)) else {
                completionHandler()
                return
            }
            let again = UNMutableNotificationContent()
            again.title = content.title
            again.body = content.body
            again.sound = .default
            again.userInfo = ["open": place]
            again.categoryIdentifier = content.categoryIdentifier
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
            center.add(UNNotificationRequest(identifier: "shefa-again", content: again, trigger: trigger))
        } else if !place.isEmpty {
            DispatchQueue.main.async { AppRouter.shared.open(place) }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
