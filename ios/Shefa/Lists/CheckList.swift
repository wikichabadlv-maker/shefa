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
    @FocusState private var isTyping: Bool

    init(kind: String, title: String, placeholder: String, emptyText: String) {
        self.kind = kind
        self.title = title
        self.placeholder = placeholder
        self.emptyText = emptyText
        _items = Query(filter: #Predicate<ListItem> { $0.kind == kind },
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
                    Button("ניקוי כל מה שהושלם", role: .destructive) {
                        for item in done { context.delete(item) }
                        try? context.save()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle(title)
        .animation(.snappy, value: items.map(\.isDone))
    }

    private func row(_ item: ListItem) -> some View {
        Button {
            item.isDone.toggle()
            item.doneAt = item.isDone ? .now : nil
            try? context.save()
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

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        context.insert(ListItem(kind: kind, title: text))
        try? context.save()
        draft = ""
        isTyping = true
    }

    private func remove(_ list: [ListItem], at offsets: IndexSet) {
        for index in offsets where list.indices.contains(index) {
            context.delete(list[index])
        }
        try? context.save()
    }
}
