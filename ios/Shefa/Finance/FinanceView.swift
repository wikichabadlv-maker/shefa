import SwiftData
import SwiftUI

enum FinanceSection: String, CaseIterable, Identifiable {
    case overview = "סקירה"
    case transactions = "תנועות"
    case budget = "תקציב"
    case savings = "חיסכון"
    case maaser = "מעשר"

    var id: String { rawValue }

    /// The color that washes the top of the screen in this section.
    var artwork: Artwork {
        switch self {
        case .overview: return Theme.emerald
        case .transactions: return Theme.blue
        case .budget: return Theme.violet
        case .savings: return Theme.green
        case .maaser: return Theme.amber
        }
    }
}

struct FinanceView: View {
    @State private var router = AppRouter.shared
    @State private var query = ""
    @Query(filter: #Predicate<LedgerEntry> { !$0.removed }, sort: \LedgerEntry.date, order: .reverse)
    private var entries: [LedgerEntry]

    @State private var month = Launch.month
    @State private var isAdding = false
    @State private var showsCategory = Launch.screen == "finance-category"

    private var section: FinanceSection { router.financeSection }

    private var summary: MonthSummary {
        Ledger.summary(counted, now: month)
    }

    private var counted: [LedgerEntry] { Ledger.effective(entries) }

    private var monthEntries: [LedgerEntry] { Ledger.inMonth(entries, month) }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }

    private var monthTitle: String {
        month.formatted(Date.FormatStyle(locale: Ledger.hebrew).month(.wide).year())
    }

    private func shiftMonth(_ by: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: by, to: month) {
            withAnimation(.snappy) { month = next }
        }
    }

    private var monthBar: some View {
        HStack {
            Button("החודש הקודם", systemImage: "chevron.backward") { shiftMonth(-1) }
                .labelStyle(.iconOnly)
            Spacer()
            Text(monthTitle)
                .font(.system(size: 17, weight: .heavy))
                .contentTransition(.numericText())
            Spacer()
            Button("החודש הבא", systemImage: "chevron.forward") { shiftMonth(1) }
                .labelStyle(.iconOnly)
                .disabled(isCurrentMonth)
        }
        .font(.system(size: 16, weight: .bold))
        .padding(.horizontal, 6)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("מדור", selection: $router.financeSection) {
                        ForEach(FinanceSection.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if section != .savings {
                        monthBar
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        switch section {
                        case .overview:
                            OverviewView(entries: counted, month: month, summary: summary)
                        case .transactions:
                            TransactionsList(entries: query.isEmpty ? monthEntries : entries, query: query)
                        case .budget:
                            BudgetList(entries: counted, month: month)
                        case .savings:
                            SavingsList(month: Ledger.summary(counted), entries: counted)
                        case .maaser:
                            MaaserView(entries: counted, month: month, summary: summary)
                        }
                    }
                    .arrives()
                    .id(section)
                    .transition(.sectionSwap)
                }
                .animation(.section, value: section)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .task {
                guard !Launch.anchor.isEmpty else { return }
                try? await Task.sleep(for: .seconds(1.5))
                proxy.scrollTo(Launch.anchor, anchor: .top)
            }
            }
            .background { AmbientGround(artwork: section.artwork) }
            .navigationTitle("פיננסים")
            .searchable(text: $query, prompt: "חנות או קטגוריה")
            .onChange(of: query) { _, value in
                if !value.isEmpty { router.financeSection = .transactions }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("הוספת תנועה", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                QuickAddSheet(kind: .expense)
            }
            .navigationDestination(isPresented: $showsCategory) {
                CategoryDetailView(category: SpendCategory.all[0], entries: counted, month: month)
            }
        }
    }
}

enum LedgerFilter: String, CaseIterable, Identifiable {
    case all = "הכל"
    case expenses = "הוצאות"
    case income = "הכנסות"
    case maaser = "מעשר"
    case questions = "לבירור"

    var id: String { rawValue }

    func matches(_ entry: LedgerEntry) -> Bool {
        switch self {
        case .all: return true
        case .expenses: return entry.amount < 0
        case .income: return entry.amount > 0
        case .maaser: return entry.categoryID == SpendCategory.maaserID
        case .questions: return entry.needsAnswer
        }
    }
}

struct TransactionsList: View {
    let entries: [LedgerEntry]
    let query: String
    @State private var filter: LedgerFilter = .all
    @State private var editing: LedgerEntry?

    private var questionCount: Int { entries.filter(\.needsAnswer).count }

    private var shown: [LedgerEntry] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            filter.matches(entry)
                && (text.isEmpty || entry.title.localizedCaseInsensitiveContains(text)
                    || (entry.category?.title.contains(text) ?? false))
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LedgerFilter.allCases) { item in
                    filterChip(item)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)

        if shown.isEmpty {
            ContentUnavailableView(
                filter == .questions ? "אין שאלות פתוחות" : "אין תנועות להצגה",
                systemImage: filter == .questions ? "checkmark.circle.fill" : "tray")
        }

        ForEach(Ledger.days(shown)) { day in
            VStack(spacing: 6) {
                HStack {
                    Text(day.title)
                    Spacer()
                    Text(Money.text(day.total, fractionDigits: 2, showPlus: true))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)

                VStack(spacing: 0) {
                    ForEach(day.entries) { item in
                        Button {
                            editing = item
                        } label: {
                            TransactionRow(entry: item)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        if item.id != day.entries.last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .cardSurface()
            }
        }
        .sheet(item: $editing) { entry in
            EntryDetailSheet(entry: entry)
        }
        .task {
            guard Launch.screen == "finance-entry" else { return }
            try? await Task.sleep(for: .seconds(1))
            editing = entries.first
        }
    }

    private func filterChip(_ item: LedgerFilter) -> some View {
        let isOn = filter == item
        let isQuestions = item == .questions && questionCount > 0
        return Button {
            withAnimation(.snappy) { filter = item }
        } label: {
            HStack(spacing: 6) {
                Text(item.rawValue)
                if isQuestions {
                    Text("\(questionCount)")
                        .font(.system(size: 11, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color(hex: 0xB45309), in: Capsule())
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(isOn ? Theme.ground : (isQuestions ? Theme.amberInk : Color.primary))
            .background(isOn ? Color.primary : (isQuestions ? Theme.amberGround : Theme.chip), in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct TransactionRow: View {
    let entry: LedgerEntry

    private var look: SpendCategory { entry.category ?? (entry.amount > 0 ? (SpendCategory.find(SpendCategory.incomeID) ?? .unknown) : .unknown) }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkIcon(artwork: look.artwork, symbol: look.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Text(entry.note.map { "\(entry.detail) · \($0)" } ?? entry.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(entry.needsAnswer ? Theme.amberInk : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money.text(entry.amount, fractionDigits: 2, showPlus: true))
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(entry.amount > 0 ? Theme.accent : Color.primary)
        }
        .frame(height: 60)
        .accessibilityElement(children: .combine)
    }
}

/// The gold card of maaser for the month: tzedakah money that is held and
/// waits to be given. It is never worded as a debt.
struct MaaserCard: View {
    let month: MonthSummary
    /// Which month is shown, so that moving between months is not mistaken
    /// for a gift.
    var monthKey = ""
    /// Income that waits for a rav's answer and is not counted meanwhile.
    var waiting: Decimal = 0
    @State private var plan = FinancePlan.shared

    private struct Standing: Equatable {
        let month: String
        let isChomesh: Bool
        let isPaid: Bool
    }

    private var due: Decimal { month.maaserDue }
    private var remaining: Decimal { max(due - month.maaserGiven, 0) }
    private var share: Double {
        guard due > 0 else { return 0 }
        return min(NSDecimalNumber(decimal: month.maaserGiven / due).doubleValue, 1)
    }

    private var rate: Binding<Bool> {
        Binding(get: { plan.isChomesh }, set: { plan.setChomesh($0) })
    }

    var body: some View {
        let isChomesh: Bool = plan.isChomesh
        let recordOnly: Bool = plan.recordOnly
        let name: String = isChomesh ? "חומש" : "מעשר"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recordOnly ? "ניתן החודש" : (due > 0 && remaining <= 0 ? "ניתן במלואו" : "ממתין לנתינה"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !recordOnly {
                    Picker("שיעור", selection: rate) {
                        Text("מעשר 10%").tag(false)
                        Text("חומש 20%").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
            }
            BigMoney(value: (recordOnly ? month.maaserGiven : remaining).double, size: 54)
            if !recordOnly {
                GrowBar(share: share, height: 8, track: .white.opacity(0.25), fill: Color.white)
                HStack {
                    Text("ניתן \(Money.text(month.maaserGiven))")
                    Spacer()
                    Text("\(name) ממה שנכנס: \(Money.text(due))")
                }
                .font(.system(size: 13, weight: .semibold))
                if month.daysLeft > 0, month.maaserReserve > due {
                    Text("מחודש מלא, לפי התוכנית: \(Money.text(month.maaserReserve))")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.85)
                }
            }
            if waiting > 0 {
                Label("\(Money.text(waiting)) שנכנסו מחכים לתשובת רב, ולא נכללו בינתיים", systemImage: "questionmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.92)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .livingCard(Theme.amber, seed: 0.9)
        .animation(.snappy, value: isChomesh)
        .animation(.snappy, value: recordOnly)
        .onChange(of: Standing(month: monthKey, isChomesh: isChomesh, isPaid: due > 0 && remaining <= 0)) { old, new in
            guard new.isPaid, !old.isPaid, old.month == new.month, old.isChomesh == new.isChomesh else { return }
            // The gift is usually entered in a sheet, which is still closing.
            Moments.shared.play("maaser." + monthKey, symbol: "heart.fill",
                                title: isChomesh ? "החומש ניתן במלואו" : "המעשר ניתן במלואו",
                                text: "\(Money.text(month.maaserGiven)) מהכנסות החודש ניתנו לצדקה.",
                                artwork: Theme.amber, after: 0.45)
        }
    }
}
