import SwiftData
import SwiftUI

/// Free notes as colorful cards: things to remember, or learning notes.
struct NotesView: View {
    let kind: String
    let title: String
    let placeholder: String
    let emptyTitle: String
    let emptyText: String
    let symbol: String

    @Environment(\.modelContext) private var context
    @Query private var items: [ListItem]
    @State private var draft = ""
    @State private var editing: ListItem?
    @State private var editText = ""
    @FocusState private var isTyping: Bool

    init(kind: String, title: String, placeholder: String, emptyTitle: String, emptyText: String, symbol: String) {
        self.kind = kind
        self.title = title
        self.placeholder = placeholder
        self.emptyTitle = emptyTitle
        self.emptyText = emptyText
        self.symbol = symbol
        _items = Query(filter: #Predicate<ListItem> { $0.kind == kind && !$0.removed },
                       sort: \ListItem.createdAt, order: .reverse)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(placeholder, text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($isTyping)
                        .font(.system(size: 16))
                    Button {
                        add()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("הוספה")
                }
                .padding(14)
                .cardSurface()

                if items.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: symbol, description: Text(emptyText))
                        .padding(.top, 30)
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    card(item, artwork: SavingsGoal.palettes[index % SavingsGoal.palettes.count])
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(title)
        .refreshable { await SharedSync.shared.run(in: context) }
        .alert("עריכה", isPresented: isEditing) {
            TextField("תוכן", text: $editText)
            Button("שמירה") { saveEdit() }
            Button("ביטול", role: .cancel) {}
        }
    }

    private var isEditing: Binding<Bool> {
        Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })
    }

    private func card(_ item: ListItem, artwork: Artwork) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            HStack {
                Text(item.createdAt.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide)))
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.85)
                Spacer()
                Menu {
                    Button("עריכה", systemImage: "pencil") {
                        editText = item.title
                        editing = item
                    }
                    Button("מחיקה", systemImage: "trash", role: .destructive) {
                        withAnimation(.snappy) {
                            item.removed = true
                            item.updatedAt = .now
                        }
                        saveAndShare()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 30)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("אפשרויות")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(artwork.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.snappy) {
            context.insert(ListItem(kind: kind, title: text))
        }
        saveAndShare()
        draft = ""
    }

    private func saveEdit() {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let item = editing, !text.isEmpty {
            item.title = text
            item.updatedAt = .now
            saveAndShare()
        }
        editing = nil
    }

    private func saveAndShare() {
        try? context.save()
        SharedSync.shared.changed(in: context)
    }
}
