import SwiftData
import SwiftUI

enum QuickKind: String, CaseIterable, Identifiable {
    case expense = "הוצאה"
    case income = "הכנסה"
    case task = "מטלה"
    case shopping = "קניות"
    case note = "פתק"

    var id: String { rawValue }

    var isMoney: Bool { self == .expense || self == .income }

    var symbol: String {
        switch self {
        case .expense: return "minus.circle.fill"
        case .income: return "plus.circle.fill"
        case .task: return "checklist"
        case .shopping: return "cart.fill"
        case .note: return "lightbulb.fill"
        }
    }

    var prompt: String {
        switch self {
        case .expense: return "על מה? למשל ירקות בשוק"
        case .income: return "ממי? למשל שיעור פרטי"
        case .task: return "מה צריך לעשות?"
        case .shopping: return "מה צריך לקנות?"
        case .note: return "מה חשוב לזכור?"
        }
    }

    var listKind: String {
        switch self {
        case .shopping: return ListItem.shopping
        case .note: return ListItem.note
        default: return ListItem.task
        }
    }
}

/// The lightning button: add anything in a few seconds.
struct QuickAddSheet: View {
    @State var kind: QuickKind = .expense
    var presetCategory: String?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var method = "מזומן"
    @State private var categoryID: String?
    @State private var savedCount = 0
    @FocusState private var focus: Field?

    private enum Field { case amount, text }

    private let methods = ["מזומן", "ביט", "העברה", "אחר"]

    private var amount: Decimal? {
        guard let value = Ledger.amount(from: amountText), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespaces).isEmpty
        return kind.isMoney ? amount != nil : hasText
    }

    private var categories: [SpendCategory] {
        SpendCategory.all.filter { $0.id != SpendCategory.incomeID && $0.id != SpendCategory.transferID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("סוג", selection: $kind) {
                        ForEach(QuickKind.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if kind.isMoney {
                    Section {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("₪")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("0", text: $amountText)
                                .font(.system(size: 44, weight: .heavy))
                                .keyboardType(.decimalPad)
                                .focused($focus, equals: .amount)
                        }
                        .environment(\.layoutDirection, .leftToRight)
                        TextField(kind.prompt, text: $text)
                            .focused($focus, equals: .text)
                        DatePicker("תאריך", selection: $date, in: ...Date.now, displayedComponents: .date)
                        Picker("איך", selection: $method) {
                            ForEach(methods, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if kind == .expense {
                        Section("קטגוריה") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                ForEach(categories) { category in
                                    categoryChip(category)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    Section {
                        TextField(kind.prompt, text: $text, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focus, equals: .text)
                    } footer: {
                        if savedCount > 0 {
                            Text(savedCount == 1 ? "נוסף. אפשר להמשיך להוסיף." : "נוספו \(savedCount). אפשר להמשיך להוסיף.")
                        }
                    }
                }
            }
            .navigationTitle("הוספה מהירה")
            .onAppear { if categoryID == nil { categoryID = presetCategory } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגירה") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { save() }
                        .disabled(!canSave)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(0.6))
                focus = kind.isMoney ? .amount : .text
            }
            .onChange(of: kind) { _, value in focus = value.isMoney ? .amount : .text }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.large])
    }

    private func categoryChip(_ category: SpendCategory) -> some View {
        let isOn = categoryID == category.id
        return Button {
            categoryID = isOn ? nil : category.id
        } label: {
            VStack(spacing: 4) {
                Image(systemName: category.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(category.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? AnyShapeStyle(category.artwork.gradient) : AnyShapeStyle(Theme.chip),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func save() {
        let title = text.trimmingCharacters(in: .whitespaces)
        if kind.isMoney {
            guard let amount else { return }
            let signed = kind == .expense ? -amount : amount
            let name = title.isEmpty ? (kind == .expense ? "הוצאה ב\(method)" : "הכנסה") : title
            let guess = Classifier.guess(title: name, amount: signed, isBankAccount: false)
            let category = kind == .income ? SpendCategory.incomeID : (categoryID ?? guess?.categoryID)
            let sub = guess?.categoryID == category ? guess?.sub : nil
            let entry = LedgerEntry(
                id: LedgerEntry.manualPrefix + UUID().uuidString, date: date, title: name,
                amount: signed, source: method, categoryID: category, sub: sub)
            context.insert(entry)
            try? context.save()
            SharedSync.shared.changed(in: context)
            dismiss()
        } else {
            guard !title.isEmpty else { return }
            let created = ListItem(kind: kind.listKind, title: title)
            if kind == .task { created.todayDay = DayKey.of() }
            context.insert(created)
            Feedback.added()
            try? context.save()
            SharedSync.shared.changed(in: context)
            savedCount += 1
            text = ""
            focus = .text
        }
    }
}

/// Everything about one line: what it was, a note, and for lines added by
/// hand also the amount and the date.
struct EntryDetailSheet: View {
    let entry: LedgerEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<LedgerEntry> { !$0.removed }, sort: \LedgerEntry.date, order: .reverse)
    private var all: [LedgerEntry]
    @State private var isChoosing = false
    @State private var note = ""
    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var confirmsDelete = false

    private var look: SpendCategory {
        entry.category ?? (entry.amount > 0 ? (SpendCategory.find(SpendCategory.incomeID) ?? .unknown) : .unknown)
    }

    private var nature: Binding<Nature> {
        Binding(
            get: { entry.nature },
            set: { value in
                entry.natureOverride = value.rawValue
                entry.updatedAt = .now
                try? context.save()
            })
    }

    private var dateLine: String {
        let day = entry.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide).year())
        return entry.source == ExcelImport.source
            ? entry.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide).year())
            : "\(day) · \(HebrewDate.text(entry.date))"
    }

    private var isFromFeed: Bool {
        !entry.isManual && entry.source != ExcelImport.source && !entry.isSample
    }

    /// When a card purchase reaches the bank account.
    private var chargeLine: (label: String, value: String)? {
        guard isFromFeed, Forecast.isCardLine(entry), entry.amount < 0 else { return nil }
        let cards: [LedgerEntry] = all.filter { Forecast.isCardLine($0) }
        let day: Int = Forecast.billingDays(cards)[entry.source] ?? 10
        let charge: Date = Forecast.chargeDay(of: entry, billingDay: day)
        let isAhead: Bool = charge > Calendar.current.startOfDay(for: .now)
        return (isAhead ? "יורד מהבנק" : "ירד מהבנק", "ב־" + Ledger.dayText(charge))
    }

    /// Whether the feed told anything worth a section of its own.
    private var hasDetails: Bool {
        guard isFromFeed else { return false }
        return chargeLine != nil || entry.paymentsText != nil || !(entry.account ?? "").isEmpty
            || !(entry.memo ?? "").isEmpty
    }

    /// For a purchase in payments: what is still to come, and until when.
    private var paymentsLine: String? {
        guard let text = entry.paymentsText else { return nil }
        let after: Int = entry.installments - entry.installment
        guard after > 0, let last = Calendar.current.date(byAdding: .month, value: after, to: entry.date) else {
            return text + " · האחרון"
        }
        let month: String = last.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide).year())
        return "\(text) · נשארו \(Money.text(entry.paymentsLeft)), עד \(month)"
    }

    /// Earlier lines from the same place, the newest first.
    private var history: [LedgerEntry] {
        guard entry.source != ExcelImport.source else { return [] }
        let key: String = Ledger.merchantKey(entry.title)
        guard !key.isEmpty else { return [] }
        let isOut: Bool = entry.amount < 0
        return all.filter {
            $0.id != entry.id && $0.source != ExcelImport.source && ($0.amount < 0) == isOut
                && Ledger.merchantKey($0.title) == key
        }
    }

    /// The top of the sheet, in the color of the line's group.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: look.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.2), in: Circle())
                Text(entry.subTitle ?? entry.category?.title ?? (entry.amount < 0 ? "לבירור" : "הכנסה"))
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if entry.pending {
                    Text("עוד לא סופי")
                        .font(.system(size: 12, weight: .heavy))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
            Text(entry.title)
                .font(.system(size: 24, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .padding(.top, 6)
            Text(Money.text(entry.amount, fractionDigits: 2, showPlus: true))
                .font(.system(size: 42, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(dateLine) · \(entry.source)")
                .font(.system(size: 13, weight: .semibold))
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(look.artwork, radius: 24, seed: 0.4, watermark: look.symbol)
        .accessibilityElement(children: .combine)
    }

    /// How often the family is at this place, and what it comes to.
    private func historyLine(_ past: [LedgerEntry]) -> String {
        let count: Int = past.count + 1
        var sum: Decimal = entry.amount < 0 ? -entry.amount : entry.amount
        for item in past {
            sum += item.amount < 0 ? -item.amount : item.amount
        }
        let average: Decimal = sum / Decimal(count)
        return "\(count) פעמים בסך הכול, \(Money.text(sum)). בממוצע \(Money.text(average)) בכל פעם."
    }

    var body: some View {
        let past: [LedgerEntry] = history
        NavigationStack {
            Form {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    Button {
                        isChoosing = true
                    } label: {
                        HStack {
                            Text("קטגוריה")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Text(entry.subTitle ?? entry.category?.title ?? "לבירור")
                                .foregroundStyle(entry.needsAnswer ? Theme.amberInk : Color.secondary)
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if entry.amount < 0 {
                        Picker("סוג ההוצאה", selection: nature) {
                            ForEach(Nature.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    }
                } footer: {
                    if entry.amount < 0 {
                        Text("קבועה חוזרת כל חודש. חד פעמית לא נכנסת לממוצע החודשי.")
                    }
                }

                Section("הערה") {
                    TextField("למשל: מתנה ליום הולדת של אמא", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if hasDetails {
                    Section {
                        if let charge = chargeLine {
                            LabeledContent(charge.label, value: charge.value)
                        }
                        if let payments = paymentsLine {
                            LabeledContent("תשלומים", value: payments)
                        }
                        if let account = entry.account, !account.isEmpty {
                            LabeledContent(Forecast.isCardLine(entry) ? "כרטיס" : "חשבון",
                                           value: "\(entry.source) · \(account)")
                        }
                        if let memo = entry.memo, !memo.isEmpty {
                            LabeledContent("כתוב בדף החשבון", value: memo)
                        }
                    } header: {
                        Text("פרטים")
                    } footer: {
                        if entry.pending {
                            Text("התנועה עוד לא סופית אצל חברת האשראי, והסכום עשוי להשתנות מעט.")
                        }
                    }
                }

                if !past.isEmpty {
                    Section {
                        ForEach(past.prefix(4)) { item in
                            HStack {
                                Text(item.date.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide).year()))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Money.text(item.amount, fractionDigits: 2, showPlus: true))
                                    .font(.system(size: 16, weight: .semibold))
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        Text("אותו מקום, בעבר")
                    } footer: {
                        Text(historyLine(past))
                    }
                }

                if entry.isManual {
                    Section("פרטים") {
                        TextField("תיאור", text: $title)
                        TextField("סכום", text: $amountText)
                            .keyboardType(.decimalPad)
                        DatePicker("תאריך", selection: $date, in: ...Date.now, displayedComponents: .date)
                    }
                    Section {
                        Button("מחיקת התנועה", role: .destructive) { confirmsDelete = true }
                    }
                } else if entry.source == ExcelImport.source {
                    Section {
                        Text("השורה הזאת הגיעה מקובץ התקציב שלכם, כסיכום חודשי של הקטגוריה.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("פרטי התנועה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") {
                        apply()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("למחוק את התנועה?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("מחיקה", role: .destructive) {
                    entry.removed = true
                    entry.updatedAt = .now
                    try? context.save()
                    SharedSync.shared.changed(in: context)
                    dismiss()
                }
                Button("ביטול", role: .cancel) {}
            }
            .sheet(isPresented: $isChoosing) {
                CategoryPicker(entry: entry)
            }
            .onAppear {
                note = entry.note ?? ""
                title = entry.title
                amountText = Money.digits(entry.amount, fractionDigits: 2).replacingOccurrences(of: ",", with: "")
                date = entry.date
            }
        }
        .arrives()
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.large])
    }

    private func apply() {
        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = false
        if cleaned != (entry.note ?? "") {
            entry.note = cleaned.isEmpty ? nil : cleaned
            changed = true
        }
        if entry.isManual {
            let name = title.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name != entry.title {
                entry.title = name
                changed = true
            }
            if let value = Ledger.amount(from: amountText), value > 0 {
                let signed = entry.amount < 0 ? -value : value
                if signed != entry.amount {
                    entry.amount = signed
                    changed = true
                }
            }
            if !Calendar.current.isDate(date, inSameDayAs: entry.date) {
                entry.date = date
                changed = true
            }
        }
        guard changed else { return }
        entry.updatedAt = .now
        try? context.save()
        if entry.isManual { SharedSync.shared.changed(in: context) }
    }
}
