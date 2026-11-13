import SwiftData
import SwiftUI

/// The week's three on the tasks screen: an offer in the first days of a
/// week that has none yet, and afterwards the three themselves, with how
/// far the week got.
struct WeekCard: View {
    /// Every task, the done ones too.
    let items: [ListItem]
    var now: Date = .now
    let toggle: (ListItem) -> Void
    let toToday: (ListItem) -> Void
    let open: (ListItem) -> Void
    @State private var router = AppRouter.shared

    static let artwork = Artwork(0xC026D3, 0x7C3AED)

    var body: some View {
        // Read here, so a change to the week's three draws the card again.
        let _ = router.weekTurn
        let list: [ListItem] = WeekFocus.tasks(in: items, now: now)
        if !list.isEmpty {
            chosen(list)
                .transition(.sectionSwap)
        } else if WeekFocus.offers(now: now) {
            offer
                .transition(.sectionSwap)
        }
    }

    // MARK: The three

    private func chosen(_ list: [ListItem]) -> some View {
        let done: Int = list.filter(\.isDone).count
        let isFull: Bool = done == list.count
        let title: String = WeekFocus.isComing(now: now) ? "הדברים של השבוע הבא" : "הדברים של השבוע"
        let line: String = WeekFocus.line(done: done, of: list.count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ArtworkIcon(artwork: WeekCard.artwork, symbol: isFull ? "checkmark.seal.fill" : "target")
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                marks(list)
                Button {
                    Feedback.tap()
                    router.isPickingWeek = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 36, height: 36)
                        .background(Theme.chip, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("שינוי הדברים של השבוע")
            }
            VStack(spacing: 0) {
                ForEach(list) { task in
                    Divider().padding(.leading, 46)
                    row(task)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .cardSurface()
        .animation(.section, value: done)
    }

    /// One mark for each thing, filled once it is done.
    private func marks(_ list: [ListItem]) -> some View {
        HStack(spacing: 4) {
            ForEach(list) { task in
                Capsule()
                    .fill(task.isDone ? AnyShapeStyle(WeekCard.artwork.gradient) : AnyShapeStyle(Theme.chip))
                    .frame(width: 16, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func row(_ task: ListItem) -> some View {
        let isDone: Bool = task.isDone
        let isToday: Bool = task.isForToday
        return HStack(spacing: 4) {
            CheckButton(isDone: isDone, isImportant: task.priority > 0, action: { toggle(task) })

            Button {
                open(task)
            } label: {
                Text(task.title)
                    .font(.system(size: 16, weight: isDone ? .regular : .semibold))
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            if isDone {
                Text("נעשה")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            } else if isToday {
                Text("על היום")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.amberInk)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Theme.amberGround, in: Capsule())
            } else {
                Button {
                    toToday(task)
                } label: {
                    Image(systemName: "sun.max")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.amberInk)
                        .frame(width: 40, height: 40)
                        .background(Theme.amberGround, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("להיום")
            }
        }
        .frame(minHeight: 52)
    }

    // MARK: The offer

    private var offer: some View {
        let weekday: Int = Calendar.current.component(.weekday, from: now)
        var title: String = weekday == 1 ? "שבוע חדש" : "השבוע הזה"
        if WeekFocus.isComing(now: now) { title = "שבוע חדש בפתח" }
        return HStack(spacing: 4) {
            Button {
                Feedback.tap()
                router.isPickingWeek = true
            } label: {
                HStack(spacing: 12) {
                    ArtworkIcon(artwork: WeekCard.artwork, symbol: "target")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.primary)
                        Text("מה שלושת הדברים שיעשו אותו טוב?")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            Button {
                withAnimation(.section) { WeekFocus.skip(now: now) }
                Feedback.tap()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.chip, in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("לא השבוע")
        }
        .padding(14)
        .cardSurface()
    }
}

/// Choosing the week's three: from the open tasks, or by writing a new one.
struct WeekPicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ListItem> { $0.kind == "task" && !$0.removed },
           sort: \ListItem.createdAt, order: .reverse)
    private var items: [ListItem]
    /// The chosen ones, in the order they were chosen.
    @State private var picked: [String] = []
    @State private var hasLoaded = false
    @State private var draft = ""
    /// Counts the tries to bring in a fourth, so the card can answer them.
    @State private var refusals = 0
    @FocusState private var isTyping: Bool

    var body: some View {
        let chosen: [ListItem] = picked.compactMap { id in items.first { $0.id == id } }
        let others: [ListItem] = DayPlan.ordered(items.filter { !$0.isDone && !picked.contains($0.id) })
        let name: String = WeekFocus.isComing() ? "השבוע הבא" : "השבוע"
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero(chosen)
                        .cascade(0)
                    addBar
                        .cascade(1)
                    if !others.isEmpty {
                        candidates(others)
                            .cascade(2)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.ground)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { save() }
                        .fontWeight(.bold)
                }
            }
        }
        .arrives()
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear(perform: load)
    }

    // MARK: The three places

    private func hero(_ chosen: [ListItem]) -> some View {
        let isOver: Bool = refusals > 0 && chosen.count >= WeekFocus.limit
        let badge: String = "\(chosen.count) מתוך \(WeekFocus.limit)"
        let text: String = isOver
            ? "שלושה, ולא יותר. כדי להכניס עוד אחד, מוציאים אחד."
            : "לא כל המטלות. רק הדברים שאם ייעשו, זה יהיה שבוע טוב."
        return VStack(alignment: .leading, spacing: 6) {
            Label(badge, systemImage: "target")
                .font(.system(size: 13, weight: .heavy))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(.white.opacity(0.2), in: Capsule())
            Text("שלושה דברים")
                .font(.system(size: 30, weight: .heavy))
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .opacity(0.92)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(0..<WeekFocus.limit, id: \.self) { index in
                    slot(index, chosen.indices.contains(index) ? chosen[index] : nil)
                }
            }
            .padding(.top, 10)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .livingCard(WeekCard.artwork, seed: 0.3, watermark: "target")
    }

    private func slot(_ index: Int, _ task: ListItem?) -> some View {
        let number: String = "\(index + 1)"
        return HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
                .frame(width: 28, height: 28)
                .background(.white.opacity(task == nil ? 0.14 : 0.28), in: Circle())
            if let task {
                Text(task.title)
                    .font(.system(size: 16, weight: .bold))
                    .strikethrough(task.isDone)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    Feedback.tap()
                    let id: String = task.id
                    withAnimation(.section) { picked.removeAll { $0 == id } }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("להוציא מהשבוע")
            } else {
                Text(index == 0 ? "בחרו מהרשימה, או כתבו דבר חדש" : "עוד אחד")
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.7)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(.white.opacity(task == nil ? 0.08 : 0.16),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Where they come from

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField("דבר חדש לשבוע", text: $draft)
                .focused($isTyping)
                .submitLabel(.done)
                .onSubmit { add() }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                add()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(WeekCard.artwork.gradient, in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("הוספה לשבוע")
        }
    }

    private func candidates(_ list: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("מהמטלות הפתוחות")
                .font(.system(size: 20, weight: .heavy))
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(list) { task in
                    candidate(task)
                    if task.id != list.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 12)
            .cardSurface()
        }
    }

    private func candidate(_ task: ListItem) -> some View {
        let due: String? = task.dueText
        let isImportant: Bool = task.priority > 0
        return Button {
            choose(task)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.chip, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if isImportant || due != nil {
                        HStack(spacing: 8) {
                            if isImportant {
                                Image(systemName: "flag.fill").foregroundStyle(Color(hex: 0xEA580C))
                            }
                            if let due {
                                Text(due).foregroundStyle(task.isOverdue ? Theme.amberInk : Color.secondary)
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: Doing

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        picked = WeekFocus.tasks(in: items).map(\.id)
    }

    private func choose(_ task: ListItem) {
        guard picked.count < WeekFocus.limit else {
            refuse()
            return
        }
        Feedback.tap()
        withAnimation(.section) { picked.append(task.id) }
    }

    /// A thing that is not on the list yet becomes a task, and one of the three.
    private func add() {
        let name: String = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard picked.count < WeekFocus.limit else {
            refuse()
            return
        }
        let item = ListItem(kind: ListItem.task, title: name)
        context.insert(item)
        try? context.save()
        SharedSync.shared.changed(in: context)
        withAnimation(.section) { picked.append(item.id) }
        Feedback.added()
        draft = ""
    }

    /// Three is the whole point: a fourth is answered, not taken.
    private func refuse() {
        withAnimation(.section) { refusals += 1 }
        Feedback.tap()
    }

    private func save() {
        WeekFocus.set(picked)
        Feedback.done()
        dismiss()
    }
}
