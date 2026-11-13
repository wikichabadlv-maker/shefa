import Foundation

/// A first guess at what a bank line is, from words in its description.
/// The family's own answers and learned merchant rules always win over this.
enum Classifier {
    struct Guess {
        let categoryID: String
        let sub: SubCategory?
    }

    /// Lines in the bank account that only move money to a card company.
    /// The purchases themselves arrive from the card, so counting these too
    /// would count every purchase twice.
    private static let cardCharges = [
        "כאל", "כ.א.ל", "מקס איט", "מקס", "ויזה", "ישראכרט", "לאומי קארד",
        "אמריקן אקספרס", "דיינרס", "כרטיסי אשראי", "כרטיס אשראי",
    ]

    /// Checked in order; the first match wins, so specific words come first.
    private static let keywords: [(sub: String?, group: String, words: [String])] = [
        ("savings.deposit", "savings", ["חיסכון", "חסכון", "פיקדון", "פקדון", "קופת גמל", "השתלמות"]),
        (nil, "maaser", ["צדקה", "תרומה", "חב\"ד", "חב״ד", "בית כנסת", "גמ\"ח", "גמ״ח", "עמותת", "מעשר"]),
        ("shabbat.mikveh", "shabbat", ["מקווה", "מקוה"]),
        ("shabbat.tefillin", "shabbat", ["תפילין", "מזוזות", "סופר סת"]),
        ("shabbat.judaica", "shabbat", ["יודאיקה", "קה\"ת", "קה״ת", "ספרי קודש"]),
        ("health.kupah", "health", ["מכבי", "כללית", "מאוחדת", "לאומית שירותי"]),
        ("food.pharm", "food", ["סופר פארם", "סופר-פארם", "בית מרקחת", "פארם"]),
        ("health.optics", "health", ["אופטיק", "משקפיים"]),
        ("health.care", "health", ["מרפאת", "רופא", "פועה"]),
        ("food.groceries", "food", ["שופרסל", "רמי לוי", "יוחננוף", "אושר עד", "ויקטורי", "טיב טעם", "יינות ביתן",
                                    "חצי חינם", "מחסני השוק", "נתיב החסד", "בר כל", "יש חסד", "סופרמרקט", "מכולת",
                                    "מאפיית", "מאפה", "קצביית", "אטליז"]),
        ("transport.fuel", "transport", ["פז ", "פז-", "דלק", "סונול", "דור אלון", "ten "]),
        ("transport.public", "transport", ["רב קו", "רב-קו", "רכבת ישראל", "אגד", "מטרופולין", "קווים"]),
        ("transport.parking", "transport", ["פנגו", "סלופארק", "חניון", "כביש 6", "נתיבי"]),
        ("transport.taxi", "transport", ["גט טקסי", "gett", "מונית", "yango"]),
        ("transport.rental", "transport", ["השכרת רכב", "אלדן", "שלמה סיקסט", "הרץ", "באדג'ט", "אוטותל", "גטאראונד"]),
        ("transport.insurance", "transport", ["ביטוח רכב", "ביטוח חובה"]),
        ("transport.service", "transport", ["מוסך", "טסט"]),
        ("home.rent", "home", ["שכירות", "שכר דירה"]),
        ("home.electric", "home", ["חברת החשמל", "חשמל"]),
        ("home.water", "home", ["תאגיד מים", "מי אביבים", "הגיחון", "מי "]),
        ("home.arnona", "home", ["ארנונה", "עיריית"]),
        ("home.gas", "home", ["אמישראגז", "פזגז", "סופרגז"]),
        ("home.internet", "home", ["בזק", "הוט ", "אינטרנט", "סיבים"]),
        ("home.mobile", "home", ["פרטנר", "סלקום", "פלאפון", "גולן טלקום", "הוט מובייל", "019", "רמי לוי תקשורת"]),
        ("home.subscriptions", "home", ["google", "גוגל", "apple.com", "spotify", "netflix", "icloud"]),
        ("home.vaad", "home", ["ועד בית"]),
        ("home.furniture", "home", ["איקאה", "ikea", "ריהוט", "רהיט", "מחסני חשמל", "א.ל.מ"]),
        ("kids.daycare", "kids", ["גן ילדים", "מעון", "צהרון"]),
        ("kids.classes", "kids", ["מורה שמיים", "חוגים", "קייטנ"]),
        ("kids.study", "kids", ["תלמוד תורה", "שכר לימוד", "בית ספר"]),
        ("clothing.wig", "clothing", ["פאה", "פאות"]),
        ("clothing.clothes", "clothing", ["קסטרו", "פוקס", "זארה", "h&m", "גולף", "נעלי", "אופנת"]),
        ("gift.restaurants", "gift", ["מסעד", "קפה ", "פיצה", "בורגר", "שווארמה", "פלאפל", "וולט", "wolt", "תן ביס"]),
        ("gift.vacation", "gift", ["מלון", "צימר", "booking", "airbnb"]),
        ("gift.books", "gift", ["סטימצקי", "צומת ספרים", "ספרים"]),
        ("gift.gifts", "gift", ["מתנה", "אולמי", "פרחי"]),
    ]

    private static let incomeWords: [(sub: String, words: [String])] = [
        ("income.army", ["צבא", "צה\"ל", "צה״ל", "משרד הביטחון", "משרד הבטחון"]),
        ("income.rentaid", ["סיוע בשכר דירה", "משרד השיכון", "משרד הבינוי"]),
        ("income.salary", ["משכורת", "שכר"]),
    ]

    /// - Parameters:
    ///   - isBankAccount: `true` for lines from the bank itself rather than a card.
    static func guess(title: String, amount: Decimal, isBankAccount: Bool) -> Guess? {
        let text = title.lowercased() + " "
        if isBankAccount && amount < 0 && cardCharges.contains(where: { text.contains($0) }) {
            return Guess(categoryID: SpendCategory.transferID, sub: nil)
        }
        if amount > 0 {
            let match = incomeWords.first { $0.words.contains(where: { text.contains($0) }) }
            return Guess(categoryID: SpendCategory.incomeID, sub: SubCategory.find(match?.sub))
        }
        for rule in keywords where rule.words.contains(where: { text.contains($0) }) {
            return Guess(categoryID: rule.group, sub: SubCategory.find(rule.sub))
        }
        return nil
    }
}
