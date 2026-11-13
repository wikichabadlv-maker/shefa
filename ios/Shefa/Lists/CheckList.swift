import SwiftData
import SwiftUI

/// One line in a simple checklist: a task, or something to buy.
@Model
final class ListItem {
    @Attribute(.unique) var id: String
    var kind: String
    var title: String
    var isDone: Bool
    var createdAt: Date
    var doneAt: Date?
    var updatedAt: Date = Date.now
    var removed: Bool = false
    /// The day the task should be done by, if any.
    var due: Date? = nil
    /// 1 marks an important task.
    var priority: Int = 0
    /// How long it should take, in minutes; 0 when not estimated.
    var minutes: Int = 0
    var note: String? = nil
    /// "", "daily" or "weekly".
    var repeatRule: String = ""
    /// The day this task was picked as one of "today's three".
    var todayDay: String = ""

    init(kind: String, title: String) {
        self.id = UUID().uuidString
        self.kind = kind
        self.title = title
        self.isDone = false
        self.createdAt = .now
        self.doneAt = nil
    }

    static let task = "task"
    static let shopping = "shopping"
    static let note = "note"
    static let learning = "learning"

    var isForToday: Bool {
        if todayDay == DayKey.of() { return true }
        guard let due else { return false }
        return due < Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
    }

    var isOverdue: Bool {
        guard let due, !isDone else { return false }
        return due < Calendar.current.startOfDay(for: .now)
    }

    /// For example "היום", "מחר", "באיחור של יומיים" or "יום שלישי".
    var dueText: String? {
        guard let due else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case 0: return "היום"
        case 1: return "מחר"
        case -1: return "מאתמול"
        case ..<(-1): return "באיחור של \(-days) ימים"
        case 2...6: return HebrewDate.weekday(due)
        default: return due.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.abbreviated))
        }
    }
}

/// A list you add to from the top and tick off, used for tasks and shopping.
struct CheckListView: View {
    let kind: String
    let title: String
    let placeholder: String
    let emptyText: String

    @Environment(\.modelContext) private var context
    @Query private var items: [ListItem]
    @State private var draft = ""
    @State private var isCheckingOut = false
    @State private var totalText = ""
    @State private var storeName = ""
    @FocusState private var isTyping: Bool

    private let staples = ["חלב", "ביצים", "לחם", "חלות לשבת", "יין", "עוף", "דגים", "ירקות", "פירות",
                           "גבינה צהובה", "נרות שבת", "נייר סופג"]

    private var isShopping: Bool { kind == ListItem.shopping }

    private var shareText: String {
        "רשימת קניות:\n" + open.map { "• " + $0.title }.joined(separator: "\n")
    }

    init(kind: String, title: String, placeholder: String, emptyText: String) {
        self.kind = kind
        self.title = title
        self.placeholder = placeholder
        self.emptyText = emptyText
        _items = Query(filter: #Predicate<ListItem> { $0.kind == kind && !$0.removed },
                       sort: \ListItem.createdAt, order: .reverse)
    }

    private var open: [ListItem] { items.filter { !$0.isDone } }
    private var done: [ListItem] { items.filter(\.isDone) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accent)
                    TextField(placeholder, text: $draft)
                        .focused($isTyping)
                        .submitLabel(.done)
                        .onSubmit { add() }
                }
            } footer: {
                if items.isEmpty { Text(emptyText) }
            }

            if isShopping {
                Section("הוספה בנגיעה") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(staples.filter { name in !open.contains { $0.title == name } }, id: \.self) { name in
                                Button {
                                    withAnimation(.snappy) { context.insert(ListItem(kind: kind, title: name)) }
                                    saveAndShare()
                                    Feedback.added()
                                } label: {
                                    Text(name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .padding(.horizontal, 14)
                                        .frame(height: 36)
                                        .background(Theme.chip, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
            }

            if !open.isEmpty {
                Section {
                    ForEach(open) { item in
                        row(item)
                    }
                    .onDelete { offsets in remove(open, at: offsets) }
                }
            }

            if !done.isEmpty {
                Section("הושלמו") {
                    ForEach(done) { item in
                        row(item)
                    }
                    .onDelete { offsets in remove(done, at: offsets) }
                    if isShopping {
                        Button("סיום קנייה ותיעוד בהוצאות", systemImage: "creditcard.fill") {
                            totalText = ""
                            storeName = ""
                            isCheckingOut = true
                        }
                    }
                    Button("ניקוי כל מה שהושלם", role: .destructive) {
                        for item in done {
                            item.removed = true
                            item.updatedAt = .now
                        }
                        saveAndShare()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle(title)
        .refreshable { await SharedSync.shared.run(in: context) }
        .animation(.snappy, value: items.map(\.isDone))
        .toolbar {
            if isShopping && !open.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText) {
                        Label("שיתוף הרשימה", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .alert("סיום קנייה", isPresented: $isCheckingOut) {
            TextField("כמה שילמנו? בשקלים", text: $totalText)
                .keyboardType(.decimalPad)
            TextField("איפה? למשל רמי לוי", text: $storeName)
            Button("תיעוד") { checkOut() }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("הקנייה תירשם בהוצאות עם רשימת המוצרים שסומנו, והם יוסרו מהרשימה.")
        }
    }

    private func row(_ item: ListItem) -> some View {
        Button {
            item.isDone.toggle()
            item.doneAt = item.isDone ? .now : nil
            item.updatedAt = .now
            saveAndShare()
            if item.isDone { Feedback.done() } else { Feedback.tap() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isDone ? Theme.accent : Color.secondary)
                Text(item.title)
                    .font(.system(size: 17, weight: item.isDone ? .regular : .semibold))
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.isDone ? .isSelected : [])
    }

    /// Records the shopping trip as an expense, with what was bought as its note.
    private func checkOut() {
        guard let total = Ledger.amount(from: totalText), total > 0 else { return }
        let store = storeName.trimmingCharacters(in: .whitespaces)
        let entry = LedgerEntry(
            id: LedgerEntry.manualPrefix + UUID().uuidString, date: .now,
            title: store.isEmpty ? "קנייה בסופר" : store, amount: -total, source: "קניות",
            categoryID: "food", note: done.map(\.title).joined(separator: ", "),
            sub: SubCategory.find("food.groceries"))
        context.insert(entry)
        for item in done {
            item.removed = true
            item.updatedAt = .now
        }
        saveAndShare()
        Feedback.done()
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        context.insert(ListItem(kind: kind, title: text))
        saveAndShare()
        draft = ""
        isTyping = true
    }

    private func remove(_ list: [ListItem], at offsets: IndexSet) {
        for index in offsets where list.indices.contains(index) {
            list[index].removed = true
            list[index].updatedAt = .now
        }
        saveAndShare()
    }

    private func saveAndShare() {
        try? context.save()
        SharedSync.shared.changed(in: context)
    }
}
