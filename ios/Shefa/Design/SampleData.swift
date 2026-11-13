import Foundation

struct ScheduleTask {
    let title: String
    let symbol: String
    let minutesLeft: Int
}

/// Example data shown until the bank sync is connected to the app.
enum SampleData {
    static let currentTask = ScheduleTask(title: "חברותא · גמרא", symbol: "book.fill", minutesLeft: 32)

    static func entries(now: Date = .now) -> [LedgerEntry] {
        func make(_ index: Int, hoursAgo: Double, _ title: String, _ amount: String,
                  _ source: String, method: String? = nil, category: String? = nil) -> LedgerEntry {
            LedgerEntry(
                id: "sample-\(index)", date: now.addingTimeInterval(-hoursAgo * 3600),
                title: title, amount: Decimal(string: amount) ?? 0, source: source,
                method: method, categoryID: category, isSample: true,
                sub: Classifier.guess(title: title, amount: Decimal(string: amount) ?? 0, isBankAccount: false)?.sub
            )
        }
        return [
            make(1, hoursAgo: 1, "בית חב״ד השכונתי", "-180", "מקס", method: "הוראת קבע", category: "maaser"),
            make(2, hoursAgo: 3, "פז · תדלוק", "-284.60", "כאל", method: "Apple Pay", category: "transport"),
            make(3, hoursAgo: 5, "משכורת", "9850", "דיסקונט", category: "income"),
            make(4, hoursAgo: 26, "רמי לוי שיווק השקמה", "-421.90", "כאל", method: "קבלה", category: "food"),
            make(5, hoursAgo: 28, "שופרסל דיל 214", "-612.40", "כאל"),
            make(6, hoursAgo: 30, "חברת החשמל", "-150", "דיסקונט", method: "הוראת קבע", category: "home"),
            make(7, hoursAgo: 52, "העברה בביט", "-250", "דיסקונט"),
            make(8, hoursAgo: 54, "קופת חולים מכבי", "-96", "מקס", category: "health"),
            make(9, hoursAgo: 76, "הפקדה לחיסכון", "-2000", "דיסקונט", method: "הוראת קבע", category: "savings"),
            make(10, hoursAgo: 78, "שופרסל דיל 214", "-88.70", "כאל"),
            make(11, hoursAgo: 100, "משכורת", "7050", "דיסקונט", category: "income"),
            make(12, hoursAgo: 102, "קרן צדקה", "-360", "דיסקונט", method: "הוראת קבע", category: "maaser"),
        ]
    }
}
