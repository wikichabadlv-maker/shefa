import Foundation
import Observation
import Security
import SwiftData

/// Where the shared family database lives. The publishable key is meant to be
/// embedded in apps; reading any data still requires signing in as a member.
enum BackendConfig {
    static let url = URL(string: "https://ezviruxnzstggpminlkt.supabase.co")!
    static let publishableKey = "sb_publishable__Pgnn7fcDQU9faQmx8ve2Q_QMDB8355"
}

struct BackendError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct BackendSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String
    var userID: String
}

/// Signs in to the family database, pulls the bank lines the sync engine
/// saved there, and pushes back the family's answers.
@MainActor
@Observable
final class Backend {
    static let shared = Backend()

    private(set) var session: BackendSession?
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var lastError: String?

    var isSignedIn: Bool { session != nil }

    private init() {
        session = SessionKeychain.load()
    }

    // MARK: Account

    func signIn(email: String, password: String) async throws {
        let body = try JSONEncoder().encode(["email": email, "password": password])
        let data = try await send("auth/v1/token", method: "POST",
                                  query: [URLQueryItem(name: "grant_type", value: "password")], body: body)
        try store(tokenResponse: data)
    }

    func signOut() {
        session = nil
        lastSync = nil
        lastError = nil
        SessionKeychain.save(nil)
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            let id: String
            let email: String?
        }
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User
    }

    private func store(tokenResponse data: Data) throws {
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        let new = BackendSession(
            accessToken: token.access_token, refreshToken: token.refresh_token,
            expiresAt: Date.now.addingTimeInterval(token.expires_in),
            email: token.user.email ?? "", userID: token.user.id)
        session = new
        SessionKeychain.save(new)
    }

    func validToken() async throws -> String {
        guard let current = session else { throw BackendError(message: "לא מחוברים לחשבון") }
        if current.expiresAt > Date.now.addingTimeInterval(60) {
            return current.accessToken
        }
        let body = try JSONEncoder().encode(["refresh_token": current.refreshToken])
        let data = try await send("auth/v1/token", method: "POST",
                                  query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: body)
        try store(tokenResponse: data)
        return session?.accessToken ?? ""
    }

    // MARK: Sync

    private struct Row: Decodable {
        let id: String
        let company: String
        let date: String
        let amount: Double
        let description: String
    }

    private struct DetailRow: Decodable {
        let transaction_id: String
        let category: String?
        let sub_category: String?
    }

    /// Pulls the bank lines and the family's saved answers into the journal.
    func sync(into context: ModelContext) async {
        guard isSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await validToken()
            let rowsData = try await send("rest/v1/bank_transactions", query: [
                URLQueryItem(name: "select", value: "id,company,date,amount,description"),
                URLQueryItem(name: "order", value: "date.desc"),
                URLQueryItem(name: "limit", value: "2000"),
            ], token: token)
            let detailsData = try await send("rest/v1/transaction_details", query: [
                URLQueryItem(name: "select", value: "transaction_id,category,sub_category"),
            ], token: token)
            let rows = try JSONDecoder().decode([Row].self, from: rowsData)
            let details = try JSONDecoder().decode([DetailRow].self, from: detailsData)
            try merge(rows: rows, details: details, into: context)
            lastSync = .now
            lastError = nil
            await SharedSync.shared.run(in: context)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func merge(rows: [Row], details: [DetailRow], into context: ModelContext) throws {
        var answers: [String: DetailRow] = [:]
        for detail in details where detail.category != nil {
            answers[detail.transaction_id] = detail
        }
        var rules: [String: MerchantRule] = [:]
        for rule in try context.fetch(FetchDescriptor<MerchantRule>()) {
            rules[rule.merchant] = rule
        }
        var known: [String: LedgerEntry] = [:]
        for entry in try context.fetch(FetchDescriptor<LedgerEntry>()) {
            if entry.isSample && !rows.isEmpty {
                context.delete(entry)
            } else {
                known[entry.id] = entry
            }
        }

        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.timeZone = TimeZone(identifier: "Asia/Jerusalem")
        dayFormat.dateFormat = "yyyy-MM-dd HH:mm"

        for row in rows {
            let amount = Decimal(string: String(format: "%.2f", row.amount)) ?? 0
            let entry: LedgerEntry
            let isNew: Bool
            if let existing = known[row.id] {
                entry = existing
                entry.amount = amount
                entry.title = row.description
                isNew = false
            } else {
                entry = LedgerEntry(
                    id: row.id,
                    date: dayFormat.date(from: "\(row.date) 12:00") ?? .now,
                    title: row.description, amount: amount,
                    source: Self.companyName(row.company))
                isNew = true
            }

            if let answer = answers[row.id] {
                entry.categoryID = answer.category
                entry.subID = answer.sub_category
                if let builtIn = SubCategory.find(answer.sub_category) {
                    entry.subTitle = builtIn.title
                } else if answer.sub_category == nil {
                    entry.subTitle = nil
                }
            } else if entry.categoryID == nil {
                if let rule = rules[Ledger.merchantKey(row.description)] {
                    entry.categoryID = rule.categoryID
                    entry.subID = rule.subID
                    entry.subTitle = rule.subTitle
                } else if let guess = Classifier.guess(
                    title: row.description, amount: amount, isBankAccount: row.company == "discount") {
                    entry.categoryID = guess.categoryID
                    entry.subID = guess.sub?.id
                    entry.subTitle = guess.sub?.title
                }
            } else if entry.subID == nil, !isNew,
                      let guess = Classifier.guess(
                        title: row.description, amount: amount, isBankAccount: row.company == "discount"),
                      guess.categoryID == entry.categoryID {
                // A line classified by an older version gets its sub-category now.
                entry.subID = guess.sub?.id
                entry.subTitle = guess.sub?.title
            }
            guard isNew else { continue }
            context.insert(entry)
            known[row.id] = entry
        }
        try context.save()
    }

    private static func companyName(_ company: String) -> String {
        switch company {
        case "discount": return "דיסקונט"
        case "max": return "מקס"
        case "visaCal": return "כאל"
        default: return company
        }
    }

    /// Saves what the family said about a bank line, so both phones see it.
    func saveAnswer(entryID: String, categoryID: String, subID: String? = nil) async {
        guard isSignedIn, !entryID.hasPrefix("sample-") else { return }
        do {
            let token = try await validToken()
            let stamp = ISO8601DateFormatter().string(from: .now)
            let payload: [[String: String?]] = [[
                "transaction_id": entryID,
                "category": categoryID,
                "sub_category": subID,
                "answered_by": session?.userID,
                "updated_at": stamp,
            ]]
            let body = try JSONEncoder().encode(payload)
            _ = try await send("rest/v1/transaction_details", method: "POST",
                               query: [URLQueryItem(name: "on_conflict", value: "transaction_id")],
                               body: body, token: token,
                               headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Network

    func send(_ path: String, method: String = "GET", query: [URLQueryItem] = [],
                      body: Data? = nil, token: String? = nil,
                      headers: [String: String] = [:]) async throws -> Data {
        guard var components = URLComponents(
            url: BackendConfig.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw BackendError(message: "כתובת לא תקינה") }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw BackendError(message: "כתובת לא תקינה") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(BackendConfig.publishableKey, forHTTPHeaderField: "apikey")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError(message: "אין תשובה מהשרת")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError(message: Self.explain(status: http.statusCode, data: data))
        }
        return data
    }

    private static func explain(status: Int, data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.contains("invalid_credentials") || text.contains("Invalid login") {
            return "האימייל או הסיסמה שגויים"
        }
        if status == 401 || status == 403 {
            return "אין הרשאה. נסו להתנתק ולהתחבר מחדש."
        }
        return "שגיאת שרת (\(status))"
    }
}

/// Keeps the signed-in session in the iPhone keychain.
enum SessionKeychain {
    private static let service = "app.shefa.ios"
    private static let account = "family-database-session"

    private static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ session: BackendSession?) {
        SecItemDelete(base as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load() -> BackendSession? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(BackendSession.self, from: data)
    }
}
