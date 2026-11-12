import Foundation

struct ScheduleTask {
    let title: String
    let symbol: String
    let minutesLeft: Int
}

struct MonthSummary {
    let budget: Decimal
    let remaining: Decimal
    let daysLeft: Int
    let income: Decimal
    let saved: Decimal
    let maaserGiven: Decimal
    let maaserDue: Decimal

    var spentShare: Double {
        guard budget > 0 else { return 0 }
        return NSDecimalNumber(decimal: (budget - remaining) / budget).doubleValue
    }
}

struct Transaction: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let amount: Decimal
    let symbol: String
    let artwork: Artwork
    var needsAnswer = false
}

struct TransactionDay: Identifiable {
    let id = UUID()
    let title: String
    let items: [Transaction]

    var total: Decimal { items.reduce(0) { $0 + $1.amount } }
}

struct SavingsGoal: Identifiable {
    let id = UUID()
    let title: String
    let saved: Decimal
    let target: Decimal
    let symbol: String
    let artwork: Artwork

    var share: Double {
        guard target > 0 else { return 0 }
        return NSDecimalNumber(decimal: saved / target).doubleValue
    }
}

/// Example data shown until the bank sync is connected to the app.
enum SampleData {
    static let currentTask = ScheduleTask(title: "חברותא · גמרא", symbol: "book.fill", minutesLeft: 32)

    static let month = MonthSummary(
        budget: 14_500, remaining: 9_080, daysLeft: 18,
        income: 16_900, saved: 2_000, maaserGiven: 1_240, maaserDue: 1_690
    )

    static let question = Transaction(
        title: "שופרסל דיל", detail: "אתמול · כאל", amount: Decimal(string: "-612.40")!,
        symbol: "cart.fill", artwork: Theme.pink, needsAnswer: true
    )

    static let days: [TransactionDay] = [
        TransactionDay(title: "היום · חמישי", items: [
            Transaction(title: "בית חב״ד השכונתי", detail: "מעשר · הוראת קבע · מקס",
                        amount: -180, symbol: "heart.fill", artwork: Theme.amber),
            Transaction(title: "פז · תדלוק", detail: "תחבורה · Apple Pay",
                        amount: Decimal(string: "-284.60")!, symbol: "fuelpump.fill", artwork: Theme.blue),
            Transaction(title: "משכורת", detail: "הכנסות · דיסקונט",
                        amount: 9_850, symbol: "arrow.up", artwork: Theme.green),
        ]),
        TransactionDay(title: "אתמול · רביעי", items: [
            Transaction(title: "רמי לוי שיווק השקמה", detail: "מזון ומכולת · כאל · קבלה",
                        amount: Decimal(string: "-421.90")!, symbol: "cart.fill", artwork: Theme.pink),
            Transaction(title: "שופרסל דיל", detail: "לבירור · כאל",
                        amount: Decimal(string: "-612.40")!, symbol: "questionmark", artwork: Theme.amber,
                        needsAnswer: true),
            Transaction(title: "חברת החשמל", detail: "חשבונות הבית · הוראת קבע",
                        amount: -150, symbol: "bolt.fill", artwork: Theme.violet),
        ]),
    ]

    static let goals: [SavingsGoal] = [
        SavingsGoal(title: "דירה משלנו", saved: 48_000, target: 200_000,
                    symbol: "house.fill", artwork: Theme.blue),
        SavingsGoal(title: "בר מצווה של מענדי", saved: 12_300, target: 30_000,
                    symbol: "star.fill", artwork: Theme.violet),
        SavingsGoal(title: "חופשת קיץ", saved: 3_100, target: 8_000,
                    symbol: "sun.max.fill", artwork: Theme.pink),
    ]
}
