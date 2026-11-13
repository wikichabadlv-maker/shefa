import EventKit
import Observation
import SwiftUI

/// One event or birthday read from the iPhone's own calendar.
struct DayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isBirthday: Bool
    let tint: Color

    var symbol: String { isBirthday ? "gift.fill" : "calendar" }
}

/// Reads the coming two months from Apple Calendar. Nothing is written there
/// and nothing leaves the phone.
@MainActor
@Observable
final class CalendarFeed {
    static let shared = CalendarFeed()

    static let enabledKey = "calendarOn"
    static let remindKey = "notifyCalendar"
    static let inviteHiddenKey = "calendarInviteHidden"

    private let store = EKEventStore()
    private(set) var events: [DayEvent] = []
    private(set) var isOn = Launch.demo || UserDefaults.standard.bool(forKey: CalendarFeed.enabledKey)
    private(set) var isDenied = false

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
        load()
    }

    /// Asks the iPhone for permission and starts reading.
    func turnOn() async {
        if !Launch.demo {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            isDenied = !granted
            guard granted else {
                isOn = false
                UserDefaults.standard.set(false, forKey: Self.enabledKey)
                return
            }
        }
        isOn = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        load()
    }

    func turnOff() {
        isOn = false
        events = []
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
    }

    func load() {
        guard isOn else { return }
        if Launch.demo {
            events = Self.demoEvents
            return
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            isDenied = true
            events = []
            return
        }
        isDenied = false
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: .now)
        guard let to = calendar.date(byAdding: .day, value: 60, to: from) else { return }
        let found = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
        events = found
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                DayEvent(id: (event.eventIdentifier ?? event.title ?? "") + "|\(Int(event.startDate.timeIntervalSince1970))",
                         title: event.title ?? "אירוע", start: event.startDate, end: event.endDate,
                         isAllDay: event.isAllDay, isBirthday: event.calendar?.type == .birthday,
                         tint: event.calendar.map { Color(cgColor: $0.cgColor) } ?? Theme.accent)
            }
    }

    /// Everything that touches the given day, whole-day events first.
    func on(_ day: Date) -> [DayEvent] {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: day)
        guard let to = calendar.date(byAdding: .day, value: 1, to: from) else { return [] }
        return events
            .filter { $0.start < to && ($0.end > from || calendar.isDate($0.start, inSameDayAs: day)) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// What is worth knowing ahead of time: birthdays in the coming two
    /// months and other events in the coming two weeks.
    func upcoming(limit: Int = 4, now: Date = .now) -> [DayEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let soon = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        var seen = Set<String>()
        return events
            .filter { $0.isBirthday ? $0.start >= today : ($0.end > now && $0.start < soon) }
            .filter { seen.insert($0.title + "|\(calendar.startOfDay(for: $0.start))").inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// "היום", "מחר", or how many days are left with the weekday.
    static func when(_ event: DayEvent, now: Date = .now) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: event.start)).day ?? 0
        let clock = event.isAllDay ? "" : " · " + ScheduleItem.clock(ScheduleItem.minute(of: event.start))
        switch days {
        case ..<1: return "היום" + clock
        case 1: return "מחר" + clock
        case 2: return "מחרתיים" + clock
        default: return "בעוד \(days) ימים · \(HebrewDate.weekday(event.start))" + clock
        }
    }

    /// Morning reminders for birthdays and whole-day events, and an evening
    /// heads-up before a birthday. Timed events already ring from Apple Calendar.
    func reminders(now: Date) -> [(Date, String, String)] {
        guard isOn, UserDefaults.standard.object(forKey: Self.remindKey) as? Bool ?? true else { return [] }
        let calendar = Calendar.current
        var result: [(Date, String, String)] = []
        func time(_ day: Date, _ hour: Int) -> Date? {
            guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day), date > now else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            if weekday == 6 && hour >= 15 { return nil }
            if weekday == 7 && hour < 21 { return nil }
            return date
        }
        for event in events where event.isBirthday || event.isAllDay {
            if let morning = time(event.start, 9) {
                result.append((morning, event.isBirthday ? "יום הולדת היום" : "היום בלוח השנה", event.title))
            }
            if event.isBirthday, let before = calendar.date(byAdding: .day, value: -1, to: event.start),
               let evening = time(before, 20) {
                result.append((evening, "מחר יום הולדת", event.title))
            }
        }
        return Array(result.sorted { $0.0 < $1.0 }.prefix(12))
    }

    private static var demoEvents: [DayEvent] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func make(_ title: String, _ days: Int, _ minute: Int?, _ length: Int, birthday: Bool, _ tint: Color) -> DayEvent {
            let day = calendar.date(byAdding: .day, value: days, to: today) ?? today
            let start = minute.map { day.addingTimeInterval(Double($0) * 60) } ?? day
            return DayEvent(id: title, title: title, start: start, end: start.addingTimeInterval(Double(length) * 60),
                            isAllDay: minute == nil, isBirthday: birthday, tint: tint)
        }
        return [
            make("אסיפת הורים", 0, 19 * 60 + 30, 60, birthday: false, .blue),
            make("יום ההולדת של מושקא", 3, nil, 1440, birthday: true, .pink),
            make("חתונה של מענדי", 6, 19 * 60, 240, birthday: false, .purple),
            make("יום ההולדת של סבא", 19, nil, 1440, birthday: true, .pink),
        ]
    }
}

/// Home: the coming birthdays and events, or a one-time offer to connect the calendar.
struct CalendarCard: View {
    @State private var feed = CalendarFeed.shared
    @AppStorage(CalendarFeed.inviteHiddenKey) private var inviteHidden = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.modelContext) private var context

    var body: some View {
        let list = feed.upcoming()
        Group {
            if !feed.isOn {
                if !inviteHidden { invite }
            } else if !list.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("בקרוב")
                        .font(.system(size: 22, weight: .heavy))
                        .padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        ForEach(list) { event in
                            CalendarRow(event: event, showsDay: true)
                            if event.id != list.last?.id {
                                Divider().padding(.leading, 62)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .cardSurface()
                }
            }
        }
        .animation(.section, value: feed.isOn)
        .animation(.section, value: list.count)
        .task { feed.load() }
        .onChange(of: phase) { _, new in
            if new == .active { feed.load() }
        }
    }

    private var invite: some View {
        HStack(spacing: 12) {
            ArtworkIcon(artwork: Theme.pink, symbol: "gift.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("ימי הולדת ואירועים")
                    .font(.system(size: 16, weight: .bold))
                Text("להציג כאן את מה שכתוב בלוח השנה של האייפון")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("חיבור") {
                Task {
                    await feed.turnOn()
                    Notifier.shared.refresh(in: context)
                }
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Theme.accent, in: Capsule())
            .buttonStyle(.pressable)
            Button {
                withAnimation(.section) { inviteHidden = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 34)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("לא עכשיו")
        }
        .padding(14)
        .cardSurface()
        .transition(.sectionSwap)
    }
}

/// One line of the calendar: a date tile or a clock, then the title.
struct CalendarRow: View {
    let event: DayEvent
    var showsDay = false

    var body: some View {
        HStack(spacing: 12) {
            if showsDay {
                VStack(spacing: -1) {
                    Text(event.start, format: .dateTime.day())
                        .font(.system(size: 18, weight: .heavy))
                        .monospacedDigit()
                    Text(event.start, format: .dateTime.month(.abbreviated))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 38, height: 38)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(event.isAllDay ? "כל היום" : ScheduleItem.clock(ScheduleItem.minute(of: event.start)))
                    .font(.system(size: event.isAllDay ? 12 : 15, weight: .bold))
                    .monospacedDigit()
                    .frame(width: 46, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(showsDay ? CalendarFeed.when(event) : (event.isBirthday ? "יום הולדת" : "מלוח השנה"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: event.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(event.isBirthday ? Color.pink : event.tint)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Schedule: what Apple Calendar holds for the chosen day, read-only.
struct CalendarDayCard: View {
    let day: Date
    @State private var feed = CalendarFeed.shared

    var body: some View {
        let list = feed.on(day)
        if feed.isOn, !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("מלוח השנה")
                    .font(.system(size: 22, weight: .heavy))
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(list) { event in
                        CalendarRow(event: event)
                        if event.id != list.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .cardSurface()
            }
            .transition(.sectionSwap)
        }
    }
}
