import SwiftData
import SwiftUI

/// One line in a simple checklist: a task, or something to buy.
@Model
final class ListItem {
    @Attribute(.unique) var id: String
    var kind: String
    var title: String
    var isDone: Bool
    var createdAt: Date
    var doneAt: Date?
    var updatedAt: Date = Date.now
    var removed: Bool = false
    /// The day the task should be done by, if any.
    var due: Date? = nil
    /// 1 marks an important task.
    var priority: Int = 0
    /// How long it should take, in minutes; 0 when not estimated.
    var minutes: Int = 0
    var note: String? = nil
    /// "", "daily" or "weekly".
    var repeatRule: String = ""
    /// The day this task was picked as one of "today's three". When that day
    /// passed with the task still open, the day follows `leftMark`.
    var todayDay: String = ""
    /// How many times it was put off: by choice, or by a day that ended
    /// without it.
    var pushed: Int = 0
    /// The last day on which a putting off was counted, so a day counts once.
    var pushedDay: String = ""

    init(kind: String, title: String) {
        self.id = UUID().uuidString
        self.kind = kind
        self.title = title
        self.isDone = false
        self.createdAt = .now
        self.doneAt = nil
    }

    static let task = "task"
    static let shopping = "shopping"
    static let note = "note"
    static let learning = "learning"

    /// Starts `todayDay` of a task that was chosen for a day that has passed.
    static let leftMark = "~"

    /// Chosen for an earlier day and still open: the morning asks about it again.
    var isLeftOver: Bool { !isDone && todayDay.hasPrefix(ListItem.leftMark) }

    /// Put off three times: too big as it stands, or not really needed.
    var isStuck: Bool { !isDone && pushed >= 3 }

    var isForToday: Bool {
        if todayDay == DayKey.of() { return true }
        guard let due else { return false }
        return due < Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
    }

    var isOverdue: Bool {
        guard let due, !isDone else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    /// For example "היום", "מחר", "מלפני יומיים" or "יום שלישי". A day that
    /// has passed is named as it is, with no word of blame.
    var dueText: String? {
        guard let due else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case 0: return "היום"
        case 1: return "מחר"
        case -1: return "מאתמול"
        case -2: return "מלפני יומיים"
        case ..<(-2): return "מלפני \(-days) ימים"
        case 2...6: return HebrewDate.weekday(due)
        default: return due.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.abbreviated))
        }
    }
}
