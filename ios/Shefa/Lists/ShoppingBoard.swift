import SwiftData
import SwiftUI

/// The two halves of the tasks tab.
enum TasksSection: String, CaseIterable, Identifiable {
    case tasks = "מטלות"
    case shopping = "קניות"

    var id: String { rawValue }
}

/// The household shopping list: everyone signed in to the same home sees
/// and ticks off the same list.
struct ShoppingBoard: View {
    @Environment(\.modelContext) private var context
    /// Removed lines stay in the query so the list can learn what is bought often.
    @Query(filter: #Predicate<ListItem> { $0.kind == "shopping" },
           sort: \ListItem.createdAt, order: .reverse)
    private var everything: [ListItem]

    @State private var backend = Backend.shared
    @State private var draft = ""
    @State private var isCheckingOut = false
    @State private var totalText = ""
    @State private var storeName = ""
    @FocusState private var isTyping: Bool

    private static let staples = ["חלב", "ביצים", "לחם", "חלות לשבת", "יין", "עוף", "דגים", "ירקות", "פירות",
                                  "גבינה צהובה", "נרות שבת", "נייר סופג"]

    private var items: [ListItem] { everything.filter { !$0.removed } }
    private var open: [ListItem] { items.filter { !$0.isDone } }
    private var inCart: [ListItem] { items.filter(\.isDone) }

    /// What is probably running out, by how often this home buys it.
    private var due: [ShoppingMemory.Rhythm] { Array(ShoppingMemory.due(everything).prefix(8)) }

    /// What this home buys most often comes first, then the usual staples.
    private var suggestions: [String] {
        var seen = Set(items.map(\.title)).union(due.map(\.title))
        var result: [String] = []
        for name in ShoppingMemory.favorites(everything) + Self.staples where !seen.contains(name) {
            seen.insert(name)
            result.append(name)
        }
        return Array(result.prefix(14))
    }

    private var shareText: String {
        "רשימת קניות:\n" + open.map { "• " + $0.title }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
                .cascade(0)
            addBar
                .cascade(1)

            if !due.isEmpty {
                dueCard
            }

            if !suggestions.isEmpty {
                suggestionRow
            }

            if items.isEmpty {
                emptyState
            }

            if !open.isEmpty {
                block("לקנות", count: open.count, list: open)
            }

            if !inCart.isEmpty {
                block("בעגלה", count: inCart.count, list: inCart)
                cartActions
            }
        }
        .animation(.section, value: items.map(\.isDone))
        .animation(.section, value: items.count)
        .task {
            // A shared list has to stay fresh while two people shop from it.
            while !Task.isCancelled {
                await SharedSync.shared.run(in: context)
                try? await Task.sleep(for: .seconds(20))
            }
        }
        .alert("סיום קנייה", isPresented: $isCheckingOut) {
            TextField("כמה שילמנו? בשקלים", text: $totalText)
                .keyboardType(.decimalPad)
            TextField("איפה? למשל רמי לוי", text: $storeName)
            Button("תיעוד") { checkOut() }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("הקנייה תירשם בהוצאות עם רשימת המוצרים שבעגלה, והם יוסרו מהרשימה.")
        }
    }

    // MARK: Parts

    private var hero: some View {
        let total = items.count
        let share = total > 0 ? Double(inCart.count) / Double(total) : 0
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(backend.isSignedIn ? "משותפת לבני הבית" : "במכשיר הזה בלבד",
                      systemImage: backend.isSignedIn ? "person.2.fill" : "iphone")
                    .font(.system(size: 13, weight: .heavy))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(.white.opacity(0.2), in: Capsule())
                Text(headline)
                    .font(.system(size: 30, weight: .heavy))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(backend.isSignedIn
                     ? "כל מה שמוסיפים או מסמנים מופיע מיד אצל שניכם."
                     : "התחברו בהגדרות, והרשימה תתעדכן אצל שניכם.")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.92)
            }
            Spacer(minLength: 0)
            ProgressRing(share: share, lineWidth: 10)
                .frame(width: 84, height: 84)
                .overlay {
                    Image(systemName: total > 0 && open.isEmpty ? "checkmark" : "cart.fill")
                        .font(.system(size: 26, weight: .heavy))
                        .contentTransition(.symbolEffect(.replace))
                }
        }
        .foregroundStyle(.white)
        .padding(20)
        .livingCard(Theme.green, seed: 0.7)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if items.isEmpty { return "הרשימה ריקה" }
        if open.isEmpty { return "הכול בעגלה" }
        if open.count == 1 { return "נשאר מוצר אחד" }
        return "\(open.count) מוצרים לקנות"
    }

    private var addBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Theme.accent)
            TextField("מה צריך לקנות?", text: $draft)
                .font(.system(size: 17))
                .focused($isTyping)
                .submitLabel(.done)
                .onSubmit { add(draft, keepsTyping: true) }
            if !open.isEmpty {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 36)
                        .background(Theme.chip, in: Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("שליחת הרשימה")
            }
        }
        .padding(14)
        .cardSurface()
    }

    /// Products whose usual time has come, each with its rhythm.
    private var dueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("כנראה נגמר", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.amberInk)
                Spacer()
                Button("הוספת הכול") {
                    for item in due { add(item.title, keepsTyping: false) }
                }
                .font(.system(size: 14, weight: .bold))
                .buttonStyle(.pressable)
                .foregroundStyle(Theme.amberInk)
            }
            Text("לפי הקצב שבו אתם קונים. ככל שתסיימו יותר קניות דרך האפליקציה, ההצעות ידייקו.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.amberInk.opacity(0.8))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(due) { item in
                        Button {
                            add(item.title, keepsTyping: false)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Label(item.title, systemImage: "plus")
                                    .font(.system(size: 15, weight: .bold))
                                Text(ShoppingMemory.intervalText(item.interval)
                                     + " · עברו \(item.daysSinceLast)")
                                    .font(.system(size: 11, weight: .medium))
                                    .opacity(0.75)
                            }
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 50)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(14)
        .background(Theme.amberGround, in: Theme.cardShape)
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { name in
                    Button {
                        add(name, keepsTyping: false)
                    } label: {
                        Label(name, systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Theme.card, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cart")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("אין מה לקנות כרגע")
                .font(.system(size: 20, weight: .heavy))
            Text("הוסיפו מוצר בנגיעה מהשורה למעלה, או כתבו כל דבר אחר.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func block(_ title: String, count: Int, list: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                Text("\(count)")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(list) { item in
                    row(item)
                    if item.id != list.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .padding(.horizontal, 12)
            .cardSurface()
        }
    }

    private func row(_ item: ListItem) -> some View {
        HStack(spacing: 4) {
            CheckButton(isDone: item.isDone, title: item.title) { toggle(item) }

            Button {
                withAnimation(.section) {
                    item.removed = true
                    item.updatedAt = .now
                }
                save()
                Feedback.tap()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("הסרה מהרשימה")
        }
        .frame(minHeight: 52)
    }

    private var cartActions: some View {
        HStack(spacing: 10) {
            Button {
                totalText = ""
                storeName = ""
                isCheckingOut = true
            } label: {
                Label("סיום קנייה ותיעוד בהוצאות", systemImage: "creditcard.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.pressable)

            Button {
                ShoppingMemory.record(inCart.map(\.title))
                withAnimation(.section) {
                    for item in inCart {
                        item.removed = true
                        item.updatedAt = .now
                    }
                }
                save()
                Notifier.shared.refresh(in: context)
                Feedback.tap()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 52, height: 48)
                    .background(Theme.chip, in: Capsule())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("קנינו, בלי תיעוד בהוצאות")
        }
    }

    // MARK: Actions

    private func add(_ text: String, keepsTyping: Bool) {
        let name = text.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(.section) { context.insert(ListItem(kind: ListItem.shopping, title: name)) }
        save()
        Feedback.added()
        if keepsTyping {
            draft = ""
            isTyping = true
        }
    }

    /// The check button has already given the tap and the chime.
    private func toggle(_ item: ListItem) {
        let wasLast = !item.isDone && open.count == 1
        let count = items.count
        withAnimation(.section) {
            item.isDone.toggle()
            item.doneAt = item.isDone ? .now : nil
            item.updatedAt = .now
        }
        save()
        // A real shopping trip, not a single carton of milk.
        if wasLast, count >= 3 {
            Moments.shared.play("shopping", symbol: "cart.fill", title: "הכול בעגלה",
                                text: "\(count) מוצרים, ואף אחד לא נשכח.", artwork: Theme.green)
        }
    }

    /// Records the shopping trip as an expense, with what was bought as its note.
    private func checkOut() {
        guard let total = Ledger.amount(from: totalText), total > 0 else { return }
        let store = storeName.trimmingCharacters(in: .whitespaces)
        let entry = LedgerEntry(
            id: LedgerEntry.manualPrefix + UUID().uuidString, date: .now,
            title: store.isEmpty ? "קנייה בסופר" : store, amount: -total, source: "קניות",
            categoryID: "food", note: inCart.map(\.title).joined(separator: ", "),
            sub: SubCategory.find("food.groceries"))
        context.insert(entry)
        ShoppingMemory.record(inCart.map(\.title))
        Notifier.shared.refresh(in: context)
        withAnimation(.section) {
            for item in inCart {
                item.removed = true
                item.updatedAt = .now
            }
        }
        save()
        Feedback.done()
    }

    private func save() {
        try? context.save()
        SharedSync.shared.changed(in: context)
    }
}

/// The shopping list as a screen of its own, opened from "More".
struct ShoppingScreen: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            ShoppingBoard()
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .background { AmbientGround(artwork: Theme.green) }
        .navigationTitle("רשימת קניות")
        .arrives()
        .refreshable { await SharedSync.shared.run(in: context) }
    }
}

/// A compact look at the shopping list for the home screen.
struct ShoppingCard: View {
    let open: [ListItem]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: Theme.green, symbol: "cart.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(open.isEmpty ? "רשימת קניות" : "\(open.count) מוצרים ברשימת הקניות")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .contentTransition(.numericText())
                    Text(open.isEmpty ? "ריקה כרגע. הקישו כדי להוסיף."
                         : open.prefix(4).map(\.title).joined(separator: ", "))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .cardSurface()
        }
        .buttonStyle(.pressable)
    }
}
