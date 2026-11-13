import SwiftData
import SwiftUI

/// One honest page about what is connected and how fresh everything is: the
/// bank and the cards, the balance, the cloud and the installation.
struct SystemStatusView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<LedgerEntry> { !$0.removed }) private var entries: [LedgerEntry]
    @State private var bank = BankState.shared
    @State private var backend = Backend.shared
    @State private var shared = SharedSync.shared
    @State private var backup = Backup.shared
    @State private var isSettingBalance = false
    @State private var isRefreshing = false

    private enum Level {
        case good, late, failed, off

        var color: Color {
            switch self {
            case .good: return Color(hex: 0x10B981)
            case .late, .failed: return Color(hex: 0xD97706)
            case .off: return Color.secondary
            }
        }

        var word: String {
            switch self {
            case .good: return "תקין"
            case .late: return "מתעכב"
            case .failed: return "לא התעדכן"
            case .off: return "לא מחובר"
            }
        }
    }

    private struct Line: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let level: Level
        let text: String
    }

    /// What a failed run means, in plain words.
    private static func explain(_ type: String?) -> String {
        switch type ?? "" {
        case "INVALID_PASSWORD":
            return "שם המשתמש או הסיסמה לא התקבלו. אם הסיסמה הוחלפה, צריך לעדכן אותה גם בסנכרון."
        case "CHANGE_PASSWORD":
            return "האתר מבקש להחליף סיסמה. מחליפים אותה באתר, ומעדכנים גם בסנכרון."
        case "ACCOUNT_BLOCKED":
            return "הכניסה נחסמה אחרי כמה ניסיונות. צריך לשחרר אותה מול הבנק או חברת האשראי."
        case "TIMEOUT":
            return "האתר לא ענה בזמן. בדרך כלל זה מסתדר בריצה הבאה."
        case "TWO_FACTOR_RETRIEVER_MISSING":
            return "האתר ביקש קוד חד־פעמי, והסנכרון האוטומטי לא יכול להזין אותו."
        default:
            return "האתר לא נתן את הנתונים הפעם. בדרך כלל זה מסתדר בריצה הבאה."
        }
    }

    /// The bank and the cards that the sync reaches, and cards that charge
    /// the account but are not connected.
    private var sources: [Line] {
        var result: [Line] = []
        for run in bank.runs {
            let symbol: String = Forecast.isCard(run.source) ? "creditcard.fill" : "building.columns.fill"
            if run.ok {
                let isLate: Bool = Date.now.timeIntervalSince(run.ranAt) > 36 * 3600
                result.append(Line(id: run.source, title: run.source, symbol: symbol, level: isLate ? .late : .good,
                                   text: isLate ? "העדכון האחרון היה \(BankState.ago(run.ranAt)), ומאז הסנכרון לא רץ."
                                       : "התעדכן \(BankState.ago(run.ranAt))."))
            } else {
                var text: String = SystemStatusView.explain(run.errorType)
                if let good = bank.lastGood[run.source] {
                    text += " הפעם האחרונה שהצליח: \(BankState.ago(good))."
                }
                result.append(Line(id: run.source, title: run.source, symbol: symbol, level: .failed, text: text))
            }
        }
        for company in unlinked {
            result.append(Line(id: "unlinked." + company, title: company, symbol: "creditcard.fill", level: .off,
                               text: "הכרטיס מחויב בחשבון הבנק, אבל הקניות שבו לא מגיעות לכאן. הן מופיעות כסכום אחד בחודש, בלי פירוט."))
        }
        return result
    }

    /// Card companies whose bill shows in the bank account, with no card
    /// lines of their own.
    private var unlinked: [String] {
        let known: [String] = Array(Set(entries.filter { Forecast.isCardLine($0) }.map { $0.source }))
            + bank.runs.map { $0.source }
        let since: Date = Date.now.addingTimeInterval(-100 * 86_400)
        var found: Set<String> = []
        for entry in entries where entry.date >= since && entry.amount < 0 && Forecast.isBankLine(entry)
            && Classifier.isCardBill(entry.title) {
            if let company = Classifier.cardCompany(in: entry.title) { found.insert(company) }
        }
        return found.filter { company in !known.contains { $0.hasPrefix(company) } }.sorted()
    }

    private var cloud: [Line] {
        guard backend.isSignedIn else {
            return [Line(id: "account", title: "החשבון המשפחתי", symbol: "person.2.fill", level: .off,
                         text: "בלי התחברות אין תנועות מהבנק, אין שיתוף בין הטלפונים ואין גיבוי. מתחברים בהגדרות.")]
        }
        var result: [Line] = []
        if let error = backend.lastError {
            result.append(Line(id: "pull", title: "תנועות מהבנק לאפליקציה", symbol: "arrow.down.circle.fill",
                               level: .failed, text: "המשיכה האחרונה לא הצליחה: \(error)"))
        } else {
            result.append(Line(id: "pull", title: "תנועות מהבנק לאפליקציה", symbol: "arrow.down.circle.fill",
                               level: .good,
                               text: backend.lastSync.map { "נמשכו \(BankState.ago($0))." } ?? "נמשכות בכל פתיחה של האפליקציה."))
        }
        if let error = shared.lastError {
            // The shared table is one setup step that may not have been done yet.
            let isMissing: Bool = error.contains("shared_items") || error.contains("404")
            result.append(Line(id: "shared", title: "שיתוף בין הטלפונים", symbol: "arrow.triangle.2.circlepath",
                               level: .failed,
                               text: isMissing
                                   ? "עוד לא הופעל בענן: חסר שלב אחד בהקמה. עד אז הרשימות, היעדים והלו״ז נשמרים במכשיר הזה בלבד."
                                   : "לא הצליח: \(error)"))
        } else {
            result.append(Line(id: "shared", title: "שיתוף בין הטלפונים", symbol: "arrow.triangle.2.circlepath",
                               level: .good,
                               text: shared.lastGood.map { "רשימות, יעדים ולו״ז סונכרנו \(BankState.ago($0))." }
                                   ?? "רשימות, יעדים ולו״ז מסתנכרנים אחרי כל שינוי."))
        }
        if let error = backup.lastError {
            result.append(Line(id: "backup", title: "גיבוי", symbol: "icloud.fill", level: .failed,
                               text: "הגיבוי האחרון לא הצליח: \(error) התוכן שמור במכשיר."))
        } else {
            result.append(Line(id: "backup", title: "גיבוי", symbol: "icloud.fill", level: .good,
                               text: backup.lastSaved.map { "נשמר בענן \(BankState.ago($0))." } ?? "עוד לא בוצע גיבוי ראשון."))
        }
        return result
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short: String = info?["CFBundleShortVersionString"] as? String ?? ""
        let build: String = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }

    var body: some View {
        let banks: [Line] = sources
        let clouds: [Line] = cloud
        let troubled: Int = (banks + clouds).filter { $0.level == .failed || $0.level == .late }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary(troubled: troubled, isEmpty: banks.isEmpty)
                    .cascade(0)
                card("בנק וכרטיסים",
                     footer: "הסנכרון רץ לבד חמש פעמים ביום, והתנועות מגיעות לכאן בכל פתיחה של האפליקציה.") {
                    if banks.isEmpty {
                        Text(backend.isSignedIn ? "עוד לא התקבל דיווח מהסנכרון." : "הדיווח מגיע אחרי התחברות לחשבון המשפחתי.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    rows(banks)
                }
                .cascade(1)
                balanceCard
                    .cascade(2)
                card("האפליקציה והענן", footer: nil) {
                    rows(clouds)
                    if backend.isSignedIn {
                        Button {
                            refresh()
                        } label: {
                            HStack(spacing: 8) {
                                if isRefreshing {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .heavy))
                                }
                                Text(isRefreshing ? "מסנכרן…" : "סנכרון עכשיו")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.chip, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                        .disabled(isRefreshing)
                        .padding(.top, 4)
                    }
                }
                .cascade(3)
                installCard
                    .cascade(4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background { AmbientGround(artwork: Theme.blue) }
        .navigationTitle("מצב החיבורים")
        .navigationBarTitleDisplayMode(.inline)
        .arrives()
        .sheet(isPresented: $isSettingBalance) {
            BalanceSheet()
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        Feedback.tap()
        isRefreshing = true
        Task {
            await backend.sync(into: context)
            await shared.run(in: context)
            isRefreshing = false
        }
    }

    /// The whole picture in one colorful card.
    private func summary(troubled: Int, isEmpty: Bool) -> some View {
        let isOff: Bool = !backend.isSignedIn
        let artwork: Artwork = isOff ? Artwork(0x64748B, 0x334155) : (troubled > 0 ? Theme.amber : Theme.emerald)
        let symbol: String = isOff ? "person.crop.circle.badge.questionmark" : (troubled > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
        let title: String = isOff ? "לא מחוברים לחשבון המשפחתי"
            : (troubled == 0 ? (isEmpty ? "מחוברים, ומחכים לדיווח ראשון" : "הכול מחובר ומעודכן")
               : (troubled == 1 ? "דבר אחד מחכה לטיפול" : "\(troubled) דברים מחכים לטיפול"))
        let text: String = isOff ? "האפליקציה עובדת גם כך, אבל הכול נשאר במכשיר הזה בלבד."
            : (troubled == 0 ? "אין מה לעשות. הדף הזה כאן בשביל הרגעים שבהם משהו נתקע."
               : "הפירוט למטה, עם מה שאפשר לעשות בכל שורה.")
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.2), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 21, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(artwork, radius: 26, seed: 0.3)
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(_ title: String, footer: String?,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .heavy))
            content()
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func rows(_ lines: [Line]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(lines) { line in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: line.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(line.level.color)
                        .frame(width: 38, height: 38)
                        .background(line.level.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(line.title)
                                .font(.system(size: 16, weight: .bold))
                            Spacer(minLength: 8)
                            Text(line.level.word)
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(line.level.color)
                        }
                        Text(line.text)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var balanceCard: some View {
        let current = bank.current
        return card("יתרה", footer: "ממנה מתחיל קו האופק. כשהבנק מדווח נתון חדש יותר, הוא מחליף יתרה שהוזנה ידנית.") {
            if let current {
                HStack(alignment: .firstTextBaseline) {
                    Text(Money.text(Decimal(current.amount.rounded())))
                        .font(.system(size: 30, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(current.amount < 0 ? HorizonView.rose : Color.primary)
                    Spacer()
                    Text((current.isManual ? "הוזנה " : "מהבנק, ") + BankState.ago(current.asOf))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("עוד אין יתרה. היא מגיעה מהבנק עם הסנכרון, ואפשר גם להזין אותה.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Feedback.tap()
                isSettingBalance = true
            } label: {
                Text(current == nil ? "הזנת יתרה" : "עדכון ידני")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.chip, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
    }

    private var installCard: some View {
        card("ההתקנה", footer: nil) {
            LabeledContent("גרסה", value: version)
                .font(.system(size: 15))
            if let expiry = Signing.expiry, let days = Signing.daysLeft {
                let day: String = expiry.formatted(Date.FormatStyle(locale: Ledger.hebrew).weekday(.wide).day().month(.wide))
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text(days == 0 ? "היום האחרון לחדש את האפליקציה" : "לחדש עד \(day) (עוד \(Ledger.daysText(days)))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(days <= 2 ? Theme.amberInk : Color.primary)
                    Text(Signing.steps)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
