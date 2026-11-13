import Foundation

/// How an expense behaves over time. Mixing the three hides the real picture:
/// fixed costs are decided once, variable ones are steered week by week, and
/// one-time ones should not distort the monthly average.
enum Nature: String, CaseIterable, Identifiable {
    case fixed, variable, once

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixed: return "קבועה"
        case .variable: return "משתנה"
        case .once: return "חד פעמית"
        }
    }

    var plural: String {
        switch self {
        case .fixed: return "קבועות"
        case .variable: return "משתנות"
        case .once: return "חד פעמיות"
        }
    }
}

/// A top-level group of spending or income.
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
        SpendCategory(id: "home", title: "דיור וחשבונות", symbol: "house.fill", artwork: Theme.violet),
        SpendCategory(id: "food", title: "מזון ובית", symbol: "cart.fill", artwork: Theme.pink),
        SpendCategory(id: "transport", title: "תחבורה", symbol: "bus.fill", artwork: Theme.blue),
        SpendCategory(id: "health", title: "בריאות", symbol: "cross.case.fill", artwork: Artwork(0xDC2626, 0x991B1B)),
        SpendCategory(id: "shabbat", title: "יהדות, שבת וחג", symbol: "flame.fill", artwork: Artwork(0xEA580C, 0x9A3412)),
        SpendCategory(id: "clothing", title: "ביגוד וטיפוח", symbol: "tshirt.fill", artwork: Artwork(0x4F46E5, 0x312E81)),
        SpendCategory(id: "gift", title: "פנאי ומתנות", symbol: "gift.fill", artwork: Artwork(0xC026D3, 0x86198F)),
        SpendCategory(id: "kids", title: "ילדים וחינוך", symbol: "figure.and.child.holdinghands", artwork: Artwork(0x0891B2, 0x155E75)),
        SpendCategory(id: maaserID, title: "מעשר וצדקה", symbol: "heart.fill", artwork: Theme.amber),
        SpendCategory(id: savingsID, title: "חיסכון", symbol: "banknote.fill", artwork: Theme.emerald),
        SpendCategory(id: incomeID, title: "הכנסות", symbol: "arrow.up", artwork: Theme.green),
        SpendCategory(id: transferID, title: "חיוב כרטיס והעברות", symbol: "arrow.left.arrow.right", artwork: Artwork(0x94A3B8, 0x475569)),
        SpendCategory(id: "other", title: "שונות", symbol: "square.grid.2x2.fill", artwork: Artwork(0x64748B, 0x334155)),
    ]

    /// The groups a family budgets for month by month.
    static var spending: [SpendCategory] {
        all.filter { $0.id != incomeID && $0.id != maaserID && !notSpending.contains($0.id) }
    }

    static let unknown = SpendCategory(id: "unknown", title: "לבירור", symbol: "questionmark", artwork: Theme.amber)

    static func find(_ id: String?) -> SpendCategory? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

/// A specific line inside a group, such as rent inside housing.
struct SubCategory: Identifiable, Hashable {
    let id: String
    let groupID: String
    let title: String
    let nature: Nature

    private static func make(_ group: String, _ key: String, _ title: String, _ nature: Nature = .variable) -> SubCategory {
        SubCategory(id: "\(group).\(key)", groupID: group, title: title, nature: nature)
    }

    static let builtIn: [SubCategory] = [
        make("home", "rent", "שכר דירה", .fixed),
        make("home", "arnona", "ארנונה", .fixed),
        make("home", "electric", "חשמל", .fixed),
        make("home", "water", "מים", .fixed),
        make("home", "gas", "גז", .fixed),
        make("home", "vaad", "ועד בית", .fixed),
        make("home", "internet", "אינטרנט", .fixed),
        make("home", "mobile", "סלולר", .fixed),
        make("home", "subscriptions", "מנויים דיגיטליים", .fixed),
        make("home", "furniture", "ריהוט ומוצרי חשמל", .once),
        make("home", "moving", "מעבר דירה ומתווך", .once),
        make("home", "repairs", "תיקונים ואחזקה"),

        make("food", "groceries", "סופר ומכולת"),
        make("food", "pharm", "פארם וטואלטיקה"),

        make("transport", "public", "תחבורה ציבורית"),
        make("transport", "fuel", "דלק"),
        make("transport", "parking", "חניה וכבישים"),
        make("transport", "taxi", "מוניות"),
        make("transport", "rental", "השכרת רכב"),
        make("transport", "insurance", "ביטוח רכב", .fixed),
        make("transport", "service", "טיפולים ותיקונים", .once),

        make("health", "kupah", "קופת חולים", .fixed),
        make("health", "insurance", "ביטוח בריאות", .fixed),
        make("health", "care", "רופאים ותרופות"),
        make("health", "optics", "אופטיקה", .once),

        make("shabbat", "mikveh", "מקווה"),
        make("shabbat", "shabbat", "שבת וחג"),
        make("shabbat", "tefillin", "תפילין ומזוזות", .once),
        make("shabbat", "judaica", "יודאיקה וספרי קודש", .once),

        make("clothing", "clothes", "ביגוד והנעלה"),
        make("clothing", "wig", "פאה", .once),
        make("clothing", "care", "קוסמטיקה ומספרה"),

        make("gift", "takeaway", "אוכל בחוץ"),
        make("gift", "restaurants", "מסעדות וקפה"),
        make("gift", "vacation", "חופשות וטיולים", .once),
        make("gift", "gifts", "מתנות ואירועים"),
        make("gift", "books", "ספרים ומשחקים"),

        make("kids", "daycare", "גנים ומעונות", .fixed),
        make("kids", "study", "חומרי לימוד"),
        make("kids", "classes", "מנויים וחוגים", .fixed),

        make("maaser", "regular", "תרומה קבועה", .fixed),
        make("maaser", "single", "תרומה חד פעמית"),

        make("savings", "deposit", "הפקדה לחיסכון", .fixed),

        make("income", "salary", "משכורת", .fixed),
        make("income", "spouse", "משכורת בת הזוג", .fixed),
        make("income", "business", "הכנסה מעסק"),
        make("income", "army", "שכר מהצבא", .fixed),
        make("income", "rentaid", "סיוע בשכר דירה", .fixed),
        make("income", "family", "עזרה מהמשפחה"),
        make("income", "other", "הכנסה אחרת"),
    ]

    static func find(_ id: String?) -> SubCategory? {
        guard let id else { return nil }
        return builtIn.first { $0.id == id }
    }

    static func inGroup(_ groupID: String) -> [SubCategory] {
        builtIn.filter { $0.groupID == groupID }
    }
}
