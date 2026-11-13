import CryptoKit
import Foundation
import Observation
import SwiftData
import SwiftUI

/// Everything that lives only on this phone, as one package for the cloud:
/// daily pillars, lessons learned, books, what the coach knows, settings.
/// Tasks, shopping, schedule, goals, budget and manual entries are already
/// kept in the family database by `SharedSync`.
struct BackupBlob: Codable {
    struct HabitCopy: Codable {
        var id: String, title: String, symbol: String, palette: Int, order: Int
        var doneDays: String, createdMs: Int64, removed: Bool
        /// Added later, so a package saved before them still opens.
        var anchor: String?, small: String?, isQuiet: Bool?
    }

    struct BookCopy: Codable {
        var id: String, title: String, author: String, totalPages: Int, page: Int
        var log: String, palette: Int, createdMs: Int64, finishedMs: Int64?, removed: Bool
    }

    struct RuleCopy: Codable {
        var merchant: String, categoryID: String, subID: String?, subTitle: String?
    }

    struct SubCopy: Codable {
        var id: String, groupID: String, title: String, createdMs: Int64
    }

    /// Settings and small logs, each value as JSON text.
    var defaults: [String: String] = [:]
    var habits: [HabitCopy] = []
    var books: [BookCopy] = []
    var rules: [RuleCopy] = []
    var customSubs: [SubCopy] = []
}

private struct BackupRow: Codable {
    struct Body: Codable { var blob: BackupBlob }
    let id: String
    let kind: String
    let data: Body
    let deleted: Bool
    let updated_ms: Int64
}

/// Saves the phone-only content to the family database whenever it changes,
/// and brings it back after a fresh install.
@MainActor
@Observable
final class Backup {
    static let shared = Backup()

    private(set) var lastError: String?
    private(set) var lastSaved: Date? = UserDefaults.standard.object(forKey: "backup.lastSaved") as? Date
    private(set) var restoredNow = false
    private var isRunning = false

    private static let readyKey = "backup.ready"
    private static let hashKey = "backup.hash"

    /// Exact settings to keep, plus everything the coach learned.
    private static let keys = [
        "studyMarksByDay", "studyDoneByDay", "studyTracked", "studyStartDay", "shoppingBoughtDays",
        "doneTasksByDay", "addedDefaultHabits", "addedMikveh", "deviceLatitude", "deviceLongitude", "deviceName",
        "appearance", "givesChomesh", City.storageKey, Feedback.soundsKey, Coach.enabledKey,
        Notifier.scheduleKey, Notifier.tasksKey, Notifier.shmaKey, Notifier.candlesKey, Notifier.sunsetKey,
    ] + FinancePlan.keys

    private init() {}

    // MARK: Package

    private func snapshot(_ context: ModelContext) -> BackupBlob {
        var blob = BackupBlob()
        let store = UserDefaults.standard
        let all = store.dictionaryRepresentation()
        for key in Self.keys + all.keys.filter({ $0.hasPrefix("coach.") }).sorted() {
            guard let value = all[key], JSONSerialization.isValidJSONObject([value]),
                  let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { continue }
            blob.defaults[key] = text
        }
        blob.habits = ((try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.id)]))) ?? []).map {
            .init(id: $0.id, title: $0.title, symbol: $0.symbol, palette: $0.palette, order: $0.order,
                  doneDays: $0.doneDays, createdMs: SharedSync.stamp($0.createdAt), removed: $0.removed,
                  anchor: $0.anchor, small: $0.small, isQuiet: $0.isQuiet)
        }
        blob.books = ((try? context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.id)]))) ?? []).map {
            .init(id: $0.id, title: $0.title, author: $0.author, totalPages: $0.totalPages, page: $0.page,
                  log: $0.log, palette: $0.palette, createdMs: SharedSync.stamp($0.createdAt),
                  finishedMs: $0.finishedAt.map { SharedSync.stamp($0) }, removed: $0.removed)
        }
        blob.rules = ((try? context.fetch(FetchDescriptor<MerchantRule>(sortBy: [SortDescriptor(\.merchant)]))) ?? []).map {
            .init(merchant: $0.merchant, categoryID: $0.categoryID, subID: $0.subID, subTitle: $0.subTitle)
        }
        blob.customSubs = ((try? context.fetch(FetchDescriptor<CustomSub>(sortBy: [SortDescriptor(\.id)]))) ?? []).map {
            .init(id: $0.id, groupID: $0.groupID, title: $0.title, createdMs: SharedSync.stamp($0.createdAt))
        }
        return blob
    }

    /// Adds what the package holds to what is on the phone; nothing here is lost.
    private func apply(_ blob: BackupBlob, to context: ModelContext) {
        let store = UserDefaults.standard
        for (key, text) in blob.defaults {
            guard store.object(forKey: key) == nil || key.hasSuffix("ByDay") || key == "shoppingBoughtDays",
                  let data = text.data(using: .utf8),
                  let wrapped = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  let value = wrapped.first else { continue }
            if let saved = value as? [String: Any], let local = store.dictionary(forKey: key) {
                // Day logs: keep the days of both.
                store.set(saved.merging(local) { _, mine in mine }, forKey: key)
            } else {
                store.set(value, forKey: key)
            }
        }

        let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
        for copy in blob.habits {
            if let mine = habits.first(where: { $0.id == copy.id }) {
                mine.doneDays = DayKey.join(mine.days.union(DayKey.split(copy.doneDays)), keep: 400)
                mine.title = copy.title
                mine.symbol = copy.symbol
                mine.palette = copy.palette
                mine.order = copy.order
                mine.removed = copy.removed
                // The practice began when it first began, on whichever phone.
                mine.createdAt = min(mine.createdAt, SharedSync.date(copy.createdMs))
                if let anchor = copy.anchor { mine.anchor = anchor }
                if let small = copy.small { mine.small = small }
                if let isQuiet = copy.isQuiet { mine.isQuiet = isQuiet }
            } else {
                let habit = Habit(id: copy.id, title: copy.title, symbol: copy.symbol, palette: copy.palette, order: copy.order)
                habit.doneDays = copy.doneDays
                habit.createdAt = SharedSync.date(copy.createdMs)
                habit.removed = copy.removed
                habit.anchor = copy.anchor ?? ""
                habit.small = copy.small ?? ""
                habit.isQuiet = copy.isQuiet ?? false
                context.insert(habit)
            }
        }

        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        for copy in blob.books where !books.contains(where: { $0.id == copy.id }) {
            let book = Book(title: copy.title, author: copy.author, totalPages: copy.totalPages, palette: copy.palette)
            book.id = copy.id
            book.page = copy.page
            book.log = copy.log
            book.createdAt = SharedSync.date(copy.createdMs)
            book.finishedAt = copy.finishedMs.map { SharedSync.date($0) }
            book.removed = copy.removed
            context.insert(book)
        }

        let rules = (try? context.fetch(FetchDescriptor<MerchantRule>())) ?? []
        for copy in blob.rules where !rules.contains(where: { $0.merchant == copy.merchant }) {
            context.insert(MerchantRule(merchant: copy.merchant, categoryID: copy.categoryID,
                                        subID: copy.subID, subTitle: copy.subTitle))
        }

        let subs = (try? context.fetch(FetchDescriptor<CustomSub>())) ?? []
        for copy in blob.customSubs where !subs.contains(where: { $0.id == copy.id }) {
            let sub = CustomSub(groupID: copy.groupID, title: copy.title)
            sub.id = copy.id
            sub.createdAt = SharedSync.date(copy.createdMs)
            context.insert(sub)
        }
        try? context.save()
        FinancePlan.shared.load()
    }

    // MARK: Cloud

    /// Restores once after a fresh install, then uploads whenever something changed.
    func sync(in context: ModelContext, force: Bool = false) async {
        let backend = Backend.shared
        guard backend.isSignedIn, let userID = backend.session?.userID, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let rowID = "backup-" + userID
        do {
            let token = try await backend.validToken()
            let store = UserDefaults.standard

            if !store.bool(forKey: Self.readyKey) {
                // A phone that has never backed up first takes what the cloud
                // holds, so an empty new install can never overwrite a full backup.
                let data = try await backend.send("rest/v1/shared_items", query: [
                    URLQueryItem(name: "select", value: "id,kind,data,deleted,updated_ms"),
                    URLQueryItem(name: "id", value: "eq." + rowID),
                ], token: token)
                if let row = try JSONDecoder().decode([BackupRow].self, from: data).first {
                    apply(row.data.blob, to: context)
                    restoredNow = true
                    Notifier.shared.refresh(in: context)
                }
                store.set(true, forKey: Self.readyKey)
            }

            let blob = snapshot(context)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let hash = SHA256.hash(data: try encoder.encode(blob)).map { String(format: "%02x", $0) }.joined()
            if force || hash != store.string(forKey: Self.hashKey) {
                let row = BackupRow(id: rowID, kind: "backup", data: .init(blob: blob), deleted: false,
                                    updated_ms: SharedSync.stamp(.now))
                _ = try await backend.send(
                    "rest/v1/shared_items", method: "POST",
                    query: [URLQueryItem(name: "on_conflict", value: "id")],
                    body: try encoder.encode([row]), token: token,
                    headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
                store.set(hash, forKey: Self.hashKey)
                lastSaved = .now
                store.set(lastSaved, forKey: "backup.lastSaved")
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Shown on the home screen when the content on this phone is not protected.
struct BackupBanner: View {
    @State private var backup = Backup.shared
    @State private var backend = Backend.shared

    var body: some View {
        if backend.isSignedIn, let problem = backup.lastError ?? SharedSync.shared.lastError {
            banner("הגיבוי לא הצליח", "התוכן שמור במכשיר, אבל לא עלה לענן. " + problem, "exclamationmark.icloud.fill")
        } else if backup.restoredNow {
            banner("התוכן שוחזר מהגיבוי", "קביעות היום, השיעורים, הספרים וההגדרות חזרו למכשיר.", "checkmark.icloud.fill")
        }
    }

    private func banner(_ title: String, _ text: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkIcon(artwork: Theme.amber, symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.amberInk)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.amberInk.opacity(0.85))
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.amberGround, in: Theme.cardShape)
        .accessibilityElement(children: .combine)
    }
}
