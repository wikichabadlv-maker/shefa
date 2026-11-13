import Foundation
import Observation

/// How one kind of income is treated when maaser is reckoned. The family
/// decides, with their rav; the app only keeps the decision.
enum MaaserRule: String, CaseIterable, Identifiable {
    case full, partial, exempt, ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "נכלל"
        case .partial: return "אחרי ניכויים"
        case .exempt: return "לא נכלל"
        case .ask: return "לשאול רב"
        }
    }

    var symbol: String {
        switch self {
        case .full: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .exempt: return "minus.circle"
        case .ask: return "questionmark.circle.fill"
        }
    }
}

/// A payment or an income the family expects, entered by hand.
struct PlannedItem: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var title: String
    /// Negative for money out.
    var amount: Double
    /// The day of the month, for an item that returns every month.
    var day: Int
    var isMonthly: Bool
    /// The day itself, for an item that happens once.
    var date: Date?

    /// The amount as an exact figure.
    var value: Decimal { Decimal(string: String(format: "%.2f", amount)) ?? 0 }
}

/// The family's own decisions about money. They live on the phone and in
/// the backup, and every screen that shows a total reads them from here.
@Observable
final class FinancePlan {
    static let shared = FinancePlan()

    static let salaryKey = "finance.houseSalary"
    static let rulesKey = "finance.maaserRules"
    static let sharesKey = "finance.maaserShares"
    static let recordOnlyKey = "finance.maaserRecordOnly"
    static let plannedKey = "finance.planned"
    static let hiddenKey = "finance.hiddenForecasts"
    static let seenRulesKey = "finance.sawMaaserRules"
    /// Older than the rest, so it keeps its first name.
    static let chomeshKey = "givesChomesh"

    /// Every key, for the cloud backup.
    static let keys = [salaryKey, rulesKey, sharesKey, recordOnlyKey, plannedKey, hiddenKey, seenRulesKey]

    /// The steady amount the house pays itself each month; 0 when not set.
    private(set) var salary: Decimal = 0
    private(set) var maaserRules: [String: String] = [:]
    /// For income counted "after deductions": the part that counts, 0...1.
    private(set) var maaserShares: [String: Double] = [:]
    /// The family records what it gives, with no figure to reach.
    private(set) var recordOnly = false
    /// The family gives a fifth, not a tenth.
    private(set) var isChomesh = false
    private(set) var planned: [PlannedItem] = []
    /// Forecast lines the family said will not return.
    private(set) var hidden: Set<String> = []

    private var store: UserDefaults { .standard }

    private init() {
        load()
    }

    /// Reads everything again, after a backup was restored.
    func load() {
        salary = Decimal(Int(store.double(forKey: Self.salaryKey).rounded()))
        maaserRules = (store.dictionary(forKey: Self.rulesKey) as? [String: String]) ?? [:]
        maaserShares = (store.dictionary(forKey: Self.sharesKey) as? [String: Double]) ?? [:]
        recordOnly = store.bool(forKey: Self.recordOnlyKey)
        isChomesh = store.bool(forKey: Self.chomeshKey)
        hidden = Set(store.stringArray(forKey: Self.hiddenKey) ?? [])
        if let text = store.string(forKey: Self.plannedKey), let data = text.data(using: .utf8),
           let list = try? Self.decoder.decode([PlannedItem].self, from: data) {
            planned = list
        } else {
            planned = []
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    func setSalary(_ value: Decimal) {
        salary = max(value, 0)
        store.set(salary.double, forKey: Self.salaryKey)
    }

    func setRule(_ rule: MaaserRule, for key: String) {
        maaserRules[key] = rule.rawValue
        store.set(maaserRules, forKey: Self.rulesKey)
    }

    func setShare(_ share: Double, for key: String) {
        maaserShares[key] = min(max(share, 0.05), 1)
        store.set(maaserShares, forKey: Self.sharesKey)
    }

    func setRecordOnly(_ value: Bool) {
        recordOnly = value
        store.set(value, forKey: Self.recordOnlyKey)
    }

    func setChomesh(_ value: Bool) {
        isChomesh = value
        store.set(value, forKey: Self.chomeshKey)
    }

    func savePlanned(_ item: PlannedItem) {
        if let index = planned.firstIndex(where: { $0.id == item.id }) {
            planned[index] = item
        } else {
            planned.append(item)
        }
        persistPlanned()
    }

    func removePlanned(_ id: String) {
        planned.removeAll { $0.id == id }
        persistPlanned()
    }

    private func persistPlanned() {
        guard let data = try? Self.encoder.encode(planned), let text = String(data: data, encoding: .utf8) else { return }
        store.set(text, forKey: Self.plannedKey)
    }

    func hide(_ key: String) {
        hidden.insert(key)
        store.set(Array(hidden).sorted(), forKey: Self.hiddenKey)
    }

    /// Brings back everything that was hidden from the forecast.
    func unhideAll() {
        hidden = []
        store.removeObject(forKey: Self.hiddenKey)
    }

    /// Made-up decisions for a demo run. Nothing is written to the phone.
    func fillDemo() {
        salary = 15200
        planned = [
            PlannedItem(id: "demo-plan-vaad", title: "ועד בית", amount: -180, day: 25, isMonthly: true, date: nil),
        ]
        maaserRules = ["income.rentaid": MaaserRule.ask.rawValue]
    }
}

/// The maaser rules as they stand at one moment, for reckoning many lines.
struct MaaserBook {
    let rules: [String: String]
    let shares: [String: Double]
    /// A tenth, or a fifth for a family that gives chomesh.
    let rate: Decimal
    let recordOnly: Bool

    init(plan: FinancePlan = .shared) {
        rules = plan.maaserRules
        shares = plan.maaserShares
        recordOnly = plan.recordOnly
        rate = plan.isChomesh ? (Decimal(string: "0.2") ?? 0) : (Decimal(string: "0.1") ?? 0)
    }

    /// The kind of income a line belongs to: its sub-category, or income in general.
    static func key(for entry: LedgerEntry) -> String {
        entry.subID ?? SpendCategory.incomeID
    }

    /// Kinds of income on which the authorities differ, so the app points
    /// them out and decides nothing.
    static let disputed: Set<String> = ["income.rentaid", "income.army", "income.family"]

    func rule(_ key: String) -> MaaserRule {
        MaaserRule(rawValue: rules[key] ?? "") ?? .full
    }

    func share(_ key: String) -> Double {
        shares[key] ?? 0.8
    }

    private func isIncome(_ entry: LedgerEntry) -> Bool {
        entry.amount > 0 && entry.categoryID != SpendCategory.transferID
    }

    /// The part of this line that maaser is reckoned from.
    func counted(_ entry: LedgerEntry) -> Decimal {
        guard isIncome(entry) else { return 0 }
        let key = MaaserBook.key(for: entry)
        switch rule(key) {
        case .full: return entry.amount
        case .partial: return entry.amount * Decimal(share(key))
        case .exempt, .ask: return 0
        }
    }

    /// Income that waits for a rav's answer, and is held out of the reckoning until then.
    func waiting(_ entries: [LedgerEntry]) -> Decimal {
        var sum = Decimal(0)
        for entry in entries where isIncome(entry) && rule(MaaserBook.key(for: entry)) == .ask {
            sum += entry.amount
        }
        return sum
    }

    /// What maaser is reckoned from, out of these lines.
    func base(_ entries: [LedgerEntry]) -> Decimal {
        var sum = Decimal(0)
        for entry in entries {
            sum += counted(entry)
        }
        return sum
    }

    /// The maaser of these lines.
    func due(_ entries: [LedgerEntry]) -> Decimal {
        recordOnly ? 0 : base(entries) * rate
    }
}
