import Foundation

/// A first guess at what a bank line is, from words in its description.
/// The family's own answers and learned merchant rules always win over this.
enum Classifier {
    /// Lines in the bank account that only move money to a card company.
    /// The purchases themselves arrive from the card, so counting these too
    /// would count every purchase twice.
    private static let cardCharges = [
        "כאל", "כ.א.ל", "מקס איט", "מקס", "ויזה", "ישראכרט", "לאומי קארד",
        "אמריקן אקספרס", "דיינרס", "כרטיסי אשראי", "כרטיס אשראי",
    ]

    private static let keywords: [(category: String, words: [String])] = [
        ("savings", ["חיסכון", "חסכון", "פיקדון", "פקדון", "קופת גמל", "השתלמות"]),
        ("maaser", ["צדקה", "תרומה", "חב\"ד", "חב״ד", "בית כנסת", "גמ\"ח", "גמ״ח", "כולל", "עמותת", "מעשר"]),
        ("health", ["מכבי", "כללית", "מאוחדת", "לאומית שירותי", "סופר פארם", "סופר-פארם", "בית מרקחת", "פארם", "מרפאת"]),
        ("food", ["שופרסל", "רמי לוי", "יוחננוף", "אושר עד", "ויקטורי", "טיב טעם", "יינות ביתן", "חצי חינם",
                  "מחסני השוק", "נתיב החסד", "בר כל", "יש חסד", "סופרמרקט", "מכולת", "מאפיית", "מאפה", "קצביית", "אטליז"]),
        ("transport", ["פז ", "פז-", "דלק", "סונול", "דור אלון", "ten ", "רב קו", "רב-קו", "רכבת ישראל", "אגד",
                       "פנגו", "סלופארק", "חניון", "מוסך", "כביש 6", "ביטוח רכב", "טסט"]),
        ("home", ["חברת החשמל", "חשמל", "תאגיד מים", "מי אביבים", "הגיחון", "ארנונה", "עיריית", "אמישראגז", "פזגז",
                  "סופרגז", "בזק", "פרטנר", "סלקום", "הוט ", "פלאפון", "גולן טלקום", "ועד בית", "שכירות", "משכנתא", "שכר דירה"]),
        ("kids", ["גן ילדים", "מעון", "תלמוד תורה", "צהרון", "חוגים", "קייטנ", "שכר לימוד", "בית ספר"]),
        ("clothing", ["קסטרו", "פוקס", "זארה", "h&m", "גולף", "נעלי", "אופנת"]),
        ("gift", ["מתנה", "אולמי", "פרחי"]),
    ]

    /// - Parameters:
    ///   - isBankAccount: `true` for lines from the bank itself rather than a card.
    static func guess(title: String, amount: Decimal, isBankAccount: Bool) -> String? {
        let text = title.lowercased() + " "
        if isBankAccount && amount < 0 && cardCharges.contains(where: { text.contains($0) }) {
            return SpendCategory.transferID
        }
        if amount > 0 {
            return SpendCategory.incomeID
        }
        for group in keywords where group.words.contains(where: { text.contains($0) }) {
            return group.category
        }
        return nil
    }
}
