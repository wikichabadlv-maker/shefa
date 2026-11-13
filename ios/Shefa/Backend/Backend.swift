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
        let processed_date: String?
        let status: String?
        let installment_number: Int?
        let installment_total: Int?
        let memo: String?
        let account: String?
    }

    private struct BalanceRow: Decodable {
        let source: String
        let account: String?
        let balance: Double
        let as_of: String
    }

    private struct RunRow: Decodable {
        let source: String
        let ran_at: String
        let ok: Bool
        let error_type: String?
        let count: Int?
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
                URLQueryItem(name: "select", value: Self.rowFields),
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
            await pullBankState(token: token)
            await SharedSync.shared.run(in: context)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static let rowFields =
        "id,company,date,amount,description,processed_date,status,installment_number,installment_total,memo,account"

    /// The account balances and the health of each bank source, as the sync
    /// engine last wrote them. The journal is complete without them, so a
    /// failure here is not a failed sync.
    private func pullBankState(token: String) async {
        do {
            let balancesData = try await send("rest/v1/account_balances", query: [
                URLQueryItem(name: "select", value: "source,account,balance,as_of"),
                URLQueryItem(name: "order", value: "as_of.desc"),
                URLQueryItem(name: "limit", value: "300"),
            ], token: token)
            let runsData = try await send("rest/v1/sync_runs", query: [
                URLQueryItem(name: "select", value: "source,ran_at,ok,error_type,count"),
                URLQueryItem(name: "order", value: "ran_at.desc"),
                URLQueryItem(name: "limit", value: "80"),
            ], token: token)
            let balanceRows = try JSONDecoder().decode([BalanceRow].self, from: balancesData)
            let runRows = try JSONDecoder().decode([RunRow].self, from: runsData)
            var balances: [BankState.Balance] = []
            for row in balanceRows {
                guard let time = BankState.time(row.as_of) else { continue }
                balances.append(BankState.Balance(
                    source: Self.companyName(row.source), account: row.account ?? "",
                    amount: row.balance, asOf: time))
            }
            var runs: [BankState.Run] = []
            for row in runRows {
                guard let time = BankState.time(row.ran_at) else { continue }
                runs.append(BankState.Run(
                    source: Self.companyName(row.source), ranAt: time, ok: row.ok,
                    errorType: row.error_type, count: row.count ?? 0))
            }
            BankState.shared.update(balances: balances, runs: runs)
        } catch {
            // Keeps what was known before.
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
            if entry.isSample {
                context.delete(entry)
            } else {
                known[entry.id] = entry
            }
        }

        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.timeZone = TimeZone(identifier: "Asia/Jerusalem")
        dayFormat.dateFormat = "yyyy-MM-dd HH:mm"

        // The card companies whose purchases arrive line by line.
        let linkedCards = Set(rows.map { Self.companyName($0.company) }).intersection(Forecast.cardSources)

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

            let isBank = !Forecast.cardSources.contains(Self.companyName(row.company))
            let charge: Date? = row.processed_date.flatMap { dayFormat.date(from: "\($0) 12:00") }
            if entry.chargeDate != charge { entry.chargeDate = charge }
            if entry.installment != (row.installment_number ?? 0) { entry.installment = row.installment_number ?? 0 }
            if entry.installments != (row.installment_total ?? 0) { entry.installments = row.installment_total ?? 0 }
            if entry.pending != (row.status == "pending") { entry.pending = row.status == "pending" }
            if entry.memo != row.memo { entry.memo = row.memo }
            if entry.account != row.account { entry.account = row.account }

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
                    title: row.description, amount: amount, isBankAccount: isBank, linkedCards: linkedCards) {
                    entry.categoryID = guess.categoryID
                    entry.subID = guess.sub?.id
                    entry.subTitle = guess.title ?? guess.sub?.title
                }
            } else if isBank, amount < 0, rules[Ledger.merchantKey(row.description)] == nil,
                      entry.categoryID == SpendCategory.transferID || entry.subTitle == Classifier.unlinkedBill,
                      let guess = Classifier.guess(
                        title: row.description, amount: amount, isBankAccount: true, linkedCards: linkedCards),
                      guess.categoryID != entry.categoryID {
                // A card's monthly bill counts as spending for as long as
                // the card itself is not connected, and stops when it is.
                entry.categoryID = guess.categoryID
                entry.subID = guess.sub?.id
                entry.subTitle = guess.title ?? guess.sub?.title
            } else if entry.subID == nil, !isNew, entry.subTitle == nil,
                      let guess = Classifier.guess(
                        title: row.description, amount: amount, isBankAccount: isBank, linkedCards: linkedCards),
                      guess.categoryID == entry.categoryID {
                // A line classified by an older version gets its sub-category now.
                entry.subID = guess.sub?.id
                entry.subTitle = guess.title ?? guess.sub?.title
            }
            guard isNew else { continue }
            context.insert(entry)
            known[row.id] = entry
        }
        try context.save()
    }

    /// The Hebrew name of a bank source. A second account at the same
    /// company arrives as "max_2" and is named "מקס 2".
    nonisolated static func companyName(_ company: String) -> String {
        let parts = company.split(separator: "_", maxSplits: 1)
        let name: String
        switch parts.first.map(String.init) ?? "" {
        case "discount": name = "דיסקונט"
        case "max": name = "מקס"
        case "visaCal": name = "כאל"
        default: return company
        }
        return parts.count > 1 ? "\(name) \(parts[1])" : name
    }

    /// Saves what the family said about a bank line, so both phones see it.
    func saveAnswer(entryID: String, categoryID: String, subID: String? = nil) async {
        guard isSignedIn, !entryID.hasPrefix("sample-"), !entryID.hasPrefix("excel-") else { return }
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
        struct ServerMessage: Decodable { let message: String? }
        let detail = (try? JSONDecoder().decode(ServerMessage.self, from: data))?.message ?? ""
        return detail.isEmpty ? "שגיאת שרת (\(status))" : "שגיאת שרת (\(status)): \(detail)"
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
