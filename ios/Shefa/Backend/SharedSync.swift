import Foundation
import Observation
import SwiftData

/// What one shared thing looks like in the family database.
struct SharedPayload: Codable {
    var title: String?
    var isDone: Bool?
    var listKind: String?
    var categoryID: String?
    var limit: Double?
    var saved: Double?
    var target: Double?
    var symbol: String?
    var palette: Int?
    var createdMs: Int64?
    var deadlineMs: Int64?
    var amount: Double?
    var dateMs: Int64?
    var subID: String?
    var subTitle: String?
    var note: String?
    var source: String?
    var nature: String?
    var startMinute: Int?
    var duration: Int?
    var weekdays: Int?
    var dueMs: Int64?
    var priority: Int?
    var minutes: Int?
    var repeatRule: String?
    var todayDay: String?
    var onlyDay: String?
    var doneDays: String?
    var log: String?
    var occasion: String?
}

private struct SharedRow: Codable {
    let id: String
    let kind: String
    let data: SharedPayload
    let deleted: Bool
    let updated_ms: Int64
}

/// Keeps tasks, shopping, budget limits and savings goals the same on both
/// phones. The most recent change to each item wins.
@MainActor
@Observable
final class SharedSync {
    static let shared = SharedSync()

    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    private(set) var lastError: String?
    /// The last time the family database took and gave everything.
    private(set) var lastGood: Date?

    private init() {}

    /// Seeded examples carry this stamp until someone edits them; they are
    /// never uploaded, so examples from one phone do not reach the other.
    static let untouched = Date(timeIntervalSince1970: 1)

    static func stamp(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func date(_ stamp: Int64) -> Date {
        Date(timeIntervalSince1970: Double(stamp) / 1000)
    }

    private static func money(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private static func money(_ value: Double?) -> Decimal {
        Decimal(string: String(format: "%.2f", value ?? 0)) ?? 0
    }

    /// Call after any local change; uploads shortly after the user stops editing.
    func changed(in context: ModelContext) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.run(in: context)
        }
    }

    func run(in context: ModelContext) async {
        let backend = Backend.shared
        guard backend.isSignedIn, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let token = try await backend.validToken()
            let data = try await backend.send("rest/v1/shared_items", query: [
                URLQueryItem(name: "select", value: "id,kind,data,deleted,updated_ms"),
                URLQueryItem(name: "kind", value: "neq.backup"),
            ], token: token)
            let remote = try JSONDecoder().decode([SharedRow].self, from: data)
            var byID: [String: SharedRow] = [:]
            for row in remote { byID[row.id] = row }

            var outgoing: [SharedRow] = []
            try mergeLists(remote: remote, byID: byID, outgoing: &outgoing, context: context)
            try mergeGoals(remote: remote, byID: byID, outgoing: &outgoing, context: context)
            try mergeBudget(remote: remote, byID: byID, outgoing: &outgoing, context: context)
            try mergeSchedule(remote: remote, byID: byID, outgoing: &outgoing, context: context)
            try mergeManualEntries(remote: remote, byID: byID, outgoing: &outgoing, context: context)
            try context.save()

            if !outgoing.isEmpty {
                let body = try JSONEncoder().encode(outgoing)
                _ = try await backend.send(
                    "rest/v1/shared_items", method: "POST",
                    query: [URLQueryItem(name: "on_conflict", value: "id")],
                    body: body, token: token,
                    headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
            }
            lastError = nil
            lastGood = .now
        } catch {
            lastError = error.localizedDescription
        }
        await Backup.shared.sync(in: context)
    }

    /// Decides what to do with one local item against its remote copy.
    private enum Verdict { case takeRemote, deleteLocal, upload, keep }

    private func verdict(local: Date, removed: Bool, remote: SharedRow?) -> Verdict {
        let localStamp = Self.stamp(local)
        guard let remote else {
            return local <= Self.untouched ? .keep : .upload
        }
        if remote.updated_ms > localStamp { return remote.deleted ? .deleteLocal : .takeRemote }
        if localStamp > remote.updated_ms { return .upload }
        return removed ? .deleteLocal : .keep
    }

    private func mergeLists(remote: [SharedRow], byID: [String: SharedRow],
                            outgoing: inout [SharedRow], context: ModelContext) throws {
        var seen = Set<String>()
        for item in try context.fetch(FetchDescriptor<ListItem>()) {
            seen.insert(item.id)
            let row = byID[item.id]
            switch verdict(local: item.updatedAt, removed: item.removed, remote: row) {
            case .takeRemote:
                if let row {
                    item.title = row.data.title ?? item.title
                    item.isDone = row.data.isDone ?? item.isDone
                    item.due = row.data.dueMs.map(Self.date)
                    item.priority = row.data.priority ?? 0
                    item.minutes = row.data.minutes ?? 0
                    item.note = row.data.note
                    item.repeatRule = row.data.repeatRule ?? ""
                    item.todayDay = row.data.todayDay ?? ""
                    item.removed = false
                    item.updatedAt = Self.date(row.updated_ms)
                }
            case .deleteLocal:
                context.delete(item)
            case .upload:
                var payload = SharedPayload(title: item.title, isDone: item.isDone, listKind: item.kind,
                                            createdMs: Self.stamp(item.createdAt))
                payload.dueMs = item.due.map(Self.stamp)
                payload.priority = item.priority
                payload.minutes = item.minutes
                payload.note = item.note
                payload.repeatRule = item.repeatRule
                payload.todayDay = item.todayDay
                outgoing.append(SharedRow(id: item.id, kind: "list", data: payload,
                                          deleted: item.removed, updated_ms: Self.stamp(item.updatedAt)))
            case .keep:
                break
            }
        }
        for row in remote where row.kind == "list" && !row.deleted && !seen.contains(row.id) {
            let item = ListItem(kind: row.data.listKind ?? ListItem.task, title: row.data.title ?? "")
            item.id = row.id
            item.isDone = row.data.isDone ?? false
            item.due = row.data.dueMs.map(Self.date)
            item.priority = row.data.priority ?? 0
            item.minutes = row.data.minutes ?? 0
            item.note = row.data.note
            item.repeatRule = row.data.repeatRule ?? ""
            item.todayDay = row.data.todayDay ?? ""
            if let created = row.data.createdMs { item.createdAt = Self.date(created) }
            item.updatedAt = Self.date(row.updated_ms)
            context.insert(item)
        }
    }

    private func mergeGoals(remote: [SharedRow], byID: [String: SharedRow],
                            outgoing: inout [SharedRow], context: ModelContext) throws {
        let familyHasGoals = remote.contains { $0.kind == "goal" && !$0.deleted }
        var seen = Set<String>()
        for goal in try context.fetch(FetchDescriptor<SavingsGoal>()) {
            seen.insert(goal.id)
            let row = byID[goal.id]
            if row == nil && goal.updatedAt <= Self.untouched && familyHasGoals {
                context.delete(goal)
                continue
            }
            switch verdict(local: goal.updatedAt, removed: goal.removed, remote: row) {
            case .takeRemote:
                if let row {
                    goal.title = row.data.title ?? goal.title
                    goal.saved = Self.money(row.data.saved)
                    goal.target = Self.money(row.data.target)
                    goal.symbol = row.data.symbol ?? goal.symbol
                    goal.palette = row.data.palette ?? goal.palette
                    goal.deadline = row.data.deadlineMs.map(Self.date)
                    goal.log = row.data.log ?? goal.log
                    goal.occasion = row.data.occasion ?? goal.occasion
                    goal.removed = false
                    goal.updatedAt = Self.date(row.updated_ms)
                }
            case .deleteLocal:
                context.delete(goal)
            case .upload:
                var payload = SharedPayload(title: goal.title, saved: Self.money(goal.saved),
                                            target: Self.money(goal.target), symbol: goal.symbol,
                                            palette: goal.palette, createdMs: Self.stamp(goal.createdAt),
                                            deadlineMs: goal.deadline.map(Self.stamp))
                payload.log = goal.log
                payload.occasion = goal.occasion
                outgoing.append(SharedRow(id: goal.id, kind: "goal", data: payload,
                                          deleted: goal.removed, updated_ms: Self.stamp(goal.updatedAt)))
            case .keep:
                break
            }
        }
        for row in remote where row.kind == "goal" && !row.deleted && !seen.contains(row.id) {
            let goal = SavingsGoal(
                id: row.id, title: row.data.title ?? "", saved: Self.money(row.data.saved),
                target: Self.money(row.data.target), symbol: row.data.symbol ?? "star.fill",
                palette: row.data.palette ?? 0,
                createdAt: row.data.createdMs.map(Self.date) ?? .now)
            goal.deadline = row.data.deadlineMs.map(Self.date)
            goal.log = row.data.log ?? ""
            goal.occasion = row.data.occasion ?? ""
            goal.updatedAt = Self.date(row.updated_ms)
            context.insert(goal)
        }
    }

    private func mergeBudget(remote: [SharedRow], byID: [String: SharedRow],
                             outgoing: inout [SharedRow], context: ModelContext) throws {
        var seen = Set<String>()
        for line in try context.fetch(FetchDescriptor<BudgetLine>()) {
            let id = "budget-\(line.categoryID)"
            seen.insert(id)
            let row = byID[id]
            switch verdict(local: line.updatedAt, removed: false, remote: row) {
            case .takeRemote:
                if let row {
                    line.limit = Self.money(row.data.limit)
                    line.updatedAt = Self.date(row.updated_ms)
                }
            case .upload:
                outgoing.append(SharedRow(
                    id: id, kind: "budget",
                    data: SharedPayload(categoryID: line.categoryID, limit: Self.money(line.limit)),
                    deleted: false, updated_ms: Self.stamp(line.updatedAt)))
            case .deleteLocal, .keep:
                break
            }
        }
        for row in remote where row.kind == "budget" && !row.deleted && !seen.contains(row.id) {
            guard let category = row.data.categoryID else { continue }
            let line = BudgetLine(categoryID: category, limit: Self.money(row.data.limit))
            line.updatedAt = Self.date(row.updated_ms)
            context.insert(line)
        }
    }

    private func mergeSchedule(remote: [SharedRow], byID: [String: SharedRow],
                               outgoing: inout [SharedRow], context: ModelContext) throws {
        var seen = Set<String>()
        for item in try context.fetch(FetchDescriptor<ScheduleItem>()) {
            seen.insert(item.id)
            let row = byID[item.id]
            switch verdict(local: item.updatedAt, removed: item.removed, remote: row) {
            case .takeRemote:
                if let row {
                    item.title = row.data.title ?? item.title
                    item.startMinute = row.data.startMinute ?? item.startMinute
                    item.durationMinutes = row.data.duration ?? item.durationMinutes
                    item.weekdays = row.data.weekdays ?? item.weekdays
                    item.symbol = row.data.symbol ?? item.symbol
                    item.palette = row.data.palette ?? item.palette
                    item.onlyDay = row.data.onlyDay ?? ""
                    item.doneDays = row.data.doneDays ?? item.doneDays
                    item.removed = false
                    item.updatedAt = Self.date(row.updated_ms)
                }
            case .deleteLocal:
                context.delete(item)
            case .upload:
                var payload = SharedPayload(title: item.title, symbol: item.symbol, palette: item.palette)
                payload.onlyDay = item.onlyDay
                payload.doneDays = item.doneDays
                payload.startMinute = item.startMinute
                payload.duration = item.durationMinutes
                payload.weekdays = item.weekdays
                outgoing.append(SharedRow(id: item.id, kind: "schedule", data: payload,
                                          deleted: item.removed, updated_ms: Self.stamp(item.updatedAt)))
            case .keep:
                break
            }
        }
        for row in remote where row.kind == "schedule" && !row.deleted && !seen.contains(row.id) {
            let item = ScheduleItem(
                id: row.id, title: row.data.title ?? "", startMinute: row.data.startMinute ?? 480,
                durationMinutes: row.data.duration ?? 60, weekdays: row.data.weekdays ?? ScheduleItem.weekdaysMask,
                symbol: row.data.symbol ?? "clock.fill", palette: row.data.palette ?? 0)
            item.onlyDay = row.data.onlyDay ?? ""
            item.doneDays = row.data.doneDays ?? ""
            item.updatedAt = Self.date(row.updated_ms)
            context.insert(item)
        }
    }

    /// Lines the family typed in by hand, such as cash purchases.
    private func mergeManualEntries(remote: [SharedRow], byID: [String: SharedRow],
                                    outgoing: inout [SharedRow], context: ModelContext) throws {
        var seen = Set<String>()
        for entry in try context.fetch(FetchDescriptor<LedgerEntry>()) where entry.isManual {
            seen.insert(entry.id)
            let row = byID[entry.id]
            switch verdict(local: entry.updatedAt, removed: entry.removed, remote: row) {
            case .takeRemote:
                if let row {
                    entry.title = row.data.title ?? entry.title
                    entry.amount = Self.money(row.data.amount)
                    if let stamp = row.data.dateMs { entry.date = Self.date(stamp) }
                    entry.categoryID = row.data.categoryID
                    entry.subID = row.data.subID
                    entry.subTitle = row.data.subTitle
                    entry.note = row.data.note
                    entry.natureOverride = row.data.nature
                    entry.source = row.data.source ?? entry.source
                    entry.removed = false
                    entry.updatedAt = Self.date(row.updated_ms)
                }
            case .deleteLocal:
                context.delete(entry)
            case .upload:
                var payload = SharedPayload(title: entry.title, categoryID: entry.categoryID)
                payload.amount = Self.money(entry.amount)
                payload.dateMs = Self.stamp(entry.date)
                payload.subID = entry.subID
                payload.subTitle = entry.subTitle
                payload.note = entry.note
                payload.nature = entry.natureOverride
                payload.source = entry.source
                outgoing.append(SharedRow(id: entry.id, kind: "entry", data: payload,
                                          deleted: entry.removed, updated_ms: Self.stamp(entry.updatedAt)))
            case .keep:
                break
            }
        }
        for row in remote where row.kind == "entry" && !row.deleted && !seen.contains(row.id) {
            let entry = LedgerEntry(
                id: row.id, date: row.data.dateMs.map(Self.date) ?? .now, title: row.data.title ?? "",
                amount: Self.money(row.data.amount), source: row.data.source ?? "מזומן",
                categoryID: row.data.categoryID, note: row.data.note)
            entry.subID = row.data.subID
            entry.subTitle = row.data.subTitle
            entry.natureOverride = row.data.nature
            entry.updatedAt = Self.date(row.updated_ms)
            context.insert(entry)
        }
    }
}
