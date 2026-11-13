import Foundation
import Observation

/// A focus session: one thing, a set time, and a bell at the end.
@Observable
final class FocusTimer {
    static let shared = FocusTimer()

    private(set) var title = ""
    private(set) var total: TimeInterval = 0
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    /// Counts finished sessions, so views can celebrate once.
    private(set) var finishedCount = 0
    /// The task the session is spent on, when it is one.
    private(set) var taskID = ""

    private init() {
        let defaults = UserDefaults.standard
        let end = defaults.double(forKey: "focusEnd")
        if end > Date.now.timeIntervalSince1970 {
            endDate = Date(timeIntervalSince1970: end)
            total = defaults.double(forKey: "focusTotal")
            title = defaults.string(forKey: "focusTitle") ?? ""
            taskID = defaults.string(forKey: "focusTask") ?? ""
        }
    }

    // MARK: How long tasks really take

    private static let startsKey = "focusStartByTask"

    private static var starts: [String: Double] {
        (UserDefaults.standard.dictionary(forKey: startsKey) as? [String: Double]) ?? [:]
    }

    /// Remembers when work on a task began. From there until the task is
    /// marked done is how long it really took, interruptions and all.
    static func noteStart(of taskID: String, at date: Date = .now) {
        guard !taskID.isEmpty else { return }
        // A start from another day says nothing about today's sitting.
        let dayStart: Double = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        var all: [String: Double] = starts.filter { $0.value >= dayStart }
        if all[taskID] == nil { all[taskID] = date.timeIntervalSince1970 }
        UserDefaults.standard.set(all, forKey: startsKey)
    }

    /// The minutes since work on a task began today, when it was started
    /// with the timer. Asked once: the start is forgotten.
    static func takeMinutes(of taskID: String, now: Date = .now) -> Int? {
        var all: [String: Double] = starts
        guard let start = all[taskID] else { return nil }
        all[taskID] = nil
        UserDefaults.standard.set(all, forKey: startsKey)
        let minutes: Int = Int(((now.timeIntervalSince1970 - start) / 60).rounded())
        return (1...360).contains(minutes) ? minutes : nil
    }

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isRunning: Bool { endDate != nil }

    func remaining(at now: Date = .now) -> TimeInterval {
        if let endDate { return max(endDate.timeIntervalSince(now), 0) }
        return pausedRemaining ?? 0
    }

    func progress(at now: Date = .now) -> Double {
        guard total > 0 else { return 0 }
        return min(max(1 - remaining(at: now) / total, 0), 1)
    }

    func start(title: String, minutes: Int, taskID: String = "") {
        self.title = title
        self.taskID = taskID
        FocusTimer.noteStart(of: taskID)
        total = Double(max(minutes, 1)) * 60
        pausedRemaining = nil
        endDate = Date.now.addingTimeInterval(total)
        persist()
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(endDate.timeIntervalSinceNow, 0)
        self.endDate = nil
        persist()
    }

    func resume() {
        guard let pausedRemaining else { return }
        endDate = Date.now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
        persist()
    }

    func stop() {
        endDate = nil
        pausedRemaining = nil
        persist()
    }

    /// Call regularly while visible; rings the bell when the time is up.
    func tick(now: Date = .now) {
        guard let endDate, now >= endDate else { return }
        self.endDate = nil
        finishedCount += 1
        UserDefaults.standard.removeObject(forKey: "focusEnd")
        Feedback.play(.bell)
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let endDate {
            defaults.set(endDate.timeIntervalSince1970, forKey: "focusEnd")
            defaults.set(total, forKey: "focusTotal")
            defaults.set(title, forKey: "focusTitle")
            defaults.set(taskID, forKey: "focusTask")
            Task { @MainActor in Notifier.shared.scheduleFocusEnd(at: endDate, title: self.title) }
        } else {
            defaults.removeObject(forKey: "focusEnd")
            Task { @MainActor in Notifier.shared.cancelFocusEnd() }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
