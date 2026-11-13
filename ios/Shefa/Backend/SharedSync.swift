import Foundation
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
final class SharedSync {
    static let shared = SharedSync()

    private var pending: Task<Void, Never>?
    private var isRunning = false
    private(set) var lastError: String?

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
            ], token: token)
            let remote = try JSONDecoder().decode([SharedRow].self, from: data)
            var byID: [String: SharedRow] = [:]
            for row in remote { byID[row.id] = row }

            var outgoing: [SharedRow] = []
            try mergeLists(remote: remote, byID: byID, outgoing: &outgoing, context: context)
            try mergeGoals(remote: remote, byID: byID, outgoing: &outgoing, context: context)
            try mergeBudget(remote: remote, byID: byID, outgoing: &outgoing, context: context)
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
        } catch {
            lastError = error.localizedDescription
        }
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
                    item.removed = false
                    item.updatedAt = Self.date(row.updated_ms)
                }
            case .deleteLocal:
                context.delete(item)
            case .upload:
                outgoing.append(SharedRow(
                    id: item.id, kind: "list",
                    data: SharedPayload(title: item.title, isDone: item.isDone, listKind: item.kind,
                                        createdMs: Self.stamp(item.createdAt)),
                    deleted: item.removed, updated_ms: Self.stamp(item.updatedAt)))
            case .keep:
                break
            }
        }
        for row in remote where row.kind == "list" && !row.deleted && !seen.contains(row.id) {
            let item = ListItem(kind: row.data.listKind ?? ListItem.task, title: row.data.title ?? "")
            item.id = row.id
            item.isDone = row.data.isDone ?? false
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
                    goal.removed = false
                    goal.updatedAt = Self.date(row.updated_ms)
                }
            case .deleteLocal:
                context.delete(goal)
            case .upload:
                outgoing.append(SharedRow(
                    id: goal.id, kind: "goal",
                    data: SharedPayload(title: goal.title, saved: Self.money(goal.saved),
                                        target: Self.money(goal.target), symbol: goal.symbol,
                                        palette: goal.palette, createdMs: Self.stamp(goal.createdAt)),
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
}
