import Foundation
import SwiftData

/// One line from the bank or a credit card, plus what we know about it.
@Model
final class LedgerEntry {
    @Attribute(.unique) var id: String
    var date: Date
    var title: String
    var amount: Decimal
    var source: String
    var method: String?
    /// `nil` means the app does not know yet what this purchase was.
    var categoryID: String?
    var note: String?
    var isSample: Bool

    init(id: String, date: Date, title: String, amount: Decimal, source: String,
         method: String? = nil, categoryID: String? = nil, note: String? = nil,
         isSample: Bool = false) {
        self.id = id
        self.date = date
        self.title = title
        self.amount = amount
        self.source = source
        self.method = method
        self.categoryID = categoryID
        self.note = note
        self.isSample = isSample
    }

    var category: SpendCategory? { SpendCategory.find(categoryID) }

    /// An expense that still waits for the user to say what it was.
    var needsAnswer: Bool { categoryID == nil && amount < 0 }

    var detail: String {
        var parts = [category?.title ?? (amount < 0 ? "לבירור" : "הכנסה")]
        parts.append(source)
        if let method { parts.append(method) }
        return parts.joined(separator: " · ")
    }
}

/// What the user taught the app: purchases at this merchant go to this category.
@Model
final class MerchantRule {
    @Attribute(.unique) var merchant: String
    var categoryID: String

    init(merchant: String, categoryID: String) {
        self.merchant = merchant
        self.categoryID = categoryID
    }
}

struct SpendCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let artwork: Artwork

    static let maaserID = "maaser"
    static let incomeID = "income"
    static let transferID = "transfer"
    static let savingsID = "savings"

    /// Categories that move money around rather than spend it.
    static let notSpending: Set<String> = [transferID, savingsID]

    static let all: [SpendCategory] = [
        SpendCategory(id: "food", title: "מזון ומכולת", symbol: "cart.fill", artwork: Theme.pink),
        SpendCategory(id: "home", title: "בית וחשבונות", symbol: "bolt.fill", artwork: Theme.violet),
        SpendCategory(id: "transport", title: "תחבורה", symbol: "fuelpump.fill", artwork: Theme.blue),
        SpendCategory(id: "kids", title: "ילדים וחינוך", symbol: "figure.and.child.holdinghands", artwork: Artwork(0x0891B2, 0x155E75)),
        SpendCategory(id: "health", title: "בריאות", symbol: "cross.case.fill", artwork: Artwork(0xDC2626, 0x991B1B)),
        SpendCategory(id: "clothing", title: "ביגוד", symbol: "tshirt.fill", artwork: Artwork(0x4F46E5, 0x312E81)),
        SpendCategory(id: "shabbat", title: "שבת וחג", symbol: "flame.fill", artwork: Artwork(0xEA580C, 0x9A3412)),
        SpendCategory(id: "gift", title: "מתנות ושמחות", symbol: "gift.fill", artwork: Artwork(0xC026D3, 0x86198F)),
        SpendCategory(id: maaserID, title: "מעשר וצדקה", symbol: "heart.fill", artwork: Theme.amber),
        SpendCategory(id: "savings", title: "חיסכון", symbol: "banknote.fill", artwork: Theme.emerald),
        SpendCategory(id: incomeID, title: "הכנסות", symbol: "arrow.up", artwork: Theme.green),
        SpendCategory(id: transferID, title: "חיוב כרטיס והעברות", symbol: "arrow.left.arrow.right", artwork: Artwork(0x94A3B8, 0x475569)),
        SpendCategory(id: "other", title: "אחר", symbol: "square.grid.2x2.fill", artwork: Artwork(0x64748B, 0x334155)),
    ]

    static let unknown = SpendCategory(id: "unknown", title: "לבירור", symbol: "questionmark", artwork: Theme.amber)

    static func find(_ id: String?) -> SpendCategory? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
