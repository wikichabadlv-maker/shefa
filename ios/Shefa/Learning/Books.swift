import SwiftData
import SwiftUI

/// A book being read, with the page reached on each day.
@Model
final class Book {
    @Attribute(.unique) var id: String
    var title: String
    var author: String = ""
    var totalPages: Int = 0
    var page: Int = 0
    /// "2026-11-13:45,2026-11-14:61": the page reached at the end of each day.
    var log: String = ""
    var palette: Int = 0
    var createdAt: Date = Date.now
    var finishedAt: Date? = nil
    var removed: Bool = false

    init(title: String, author: String, totalPages: Int, palette: Int) {
        self.id = UUID().uuidString
        self.title = title
        self.author = author
        self.totalPages = totalPages
        self.palette = palette
    }

    var artwork: Artwork { SavingsGoal.palettes[abs(palette) % SavingsGoal.palettes.count] }

    var share: Double { totalPages > 0 ? min(Double(page) / Double(totalPages), 1) : 0 }

    var isFinished: Bool { finishedAt != nil }

    var entries: [(day: String, page: Int)] {
        log.split(separator: ",").compactMap { part in
            let pieces = part.split(separator: ":")
            guard pieces.count == 2, let page = Int(pieces[1]) else { return nil }
            return (String(pieces[0]), page)
        }
    }

    /// Records the page reached today.
    func setPage(_ value: Int, on date: Date = .now) {
        page = max(0, totalPages > 0 ? min(value, totalPages) : value)
        var all = entries.filter { $0.day != DayKey.of(date) }
        all.append((DayKey.of(date), page))
        log = all.suffix(200).map { "\($0.day):\($0.page)" }.joined(separator: ",")
        if totalPages > 0, page >= totalPages {
            if finishedAt == nil { finishedAt = date }
        } else {
            finishedAt = nil
        }
    }

    /// Pages read today.
    var pagesToday: Int {
        let all = entries
        guard let last = all.last, last.day == DayKey.of() else { return 0 }
        let before = all.dropLast().last?.page ?? 0
        return max(last.page - before, 0)
    }

    var readToday: Bool { entries.last?.day == DayKey.of() }

    /// Average pages a day over the last two weeks of reading.
    var pace: Double {
        guard let start = DayKey.date(DayKey.of(createdAt)) else { return 0 }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let from = max(start, cutoff)
        let basePage = entries.last { (DayKey.date($0.day) ?? .now) < from }?.page ?? 0
        let days = max(Calendar.current.dateComponents([.day], from: from, to: .now).day ?? 0, 0) + 1
        return Double(max(page - basePage, 0)) / Double(days)
    }

    /// When the book will be finished at the current pace.
    var finishDate: Date? {
        guard totalPages > page, pace > 0.2 else { return nil }
        let days = Int((Double(totalPages - page) / pace).rounded(.up))
        return Calendar.current.date(byAdding: .day, value: days, to: .now)
    }

    var days: Set<String> { Set(entries.map(\.day)) }
}

extension Book {
    /// The celebration for a book that was just read to its last page;
    /// returns true when it played.
    @MainActor @discardableResult
    static func celebrateFinish(_ book: Book, after delay: Double = 0) -> Bool {
        Moments.shared.play(
            "book." + book.id, symbol: "book.closed.fill", title: "סיימתם ספר",
            text: "\(book.title): \(book.totalPages) עמודים, מכריכה לכריכה.",
            artwork: book.artwork, after: delay)
    }
}

/// The bookshelf: what is being read now, how fast, and what was finished.
struct BooksView: View {
    /// The color of the bookshelf everywhere in the app.
    static let artwork = Artwork(0x0891B2, 0x155E75)

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Book> { !$0.removed }, sort: \Book.createdAt, order: .reverse)
    private var books: [Book]
    @State private var editing: Book?
    @State private var isAdding = false

    private var reading: [Book] { books.filter { !$0.isFinished } }
    private var finished: [Book] { books.filter(\.isFinished) }

    private var streak: Int {
        DayKey.streak(books.reduce(into: Set<String>()) { $0.formUnion($1.days) }, skipShabbat: true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                    .cascade(0)

                if books.isEmpty {
                    emptyState
                        .cascade(1)
                }

                if !reading.isEmpty {
                    Text("קוראים עכשיו")
                        .font(.system(size: 22, weight: .heavy))
                        .padding(.horizontal, 4)
                        .cascade(1)
                    ForEach(reading) { book in
                        BookCard(book: book) { editing = book }
                            .cascade(2)
                    }
                }

                if !finished.isEmpty {
                    Text("סיימנו")
                        .font(.system(size: 22, weight: .heavy))
                        .padding(.horizontal, 4)
                        .cascade(3)
                    shelf
                    VStack(spacing: 0) {
                        ForEach(finished) { book in
                            Button {
                                editing = book
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkIcon(artwork: book.artwork, symbol: "checkmark", size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(book.title)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(Color.primary)
                                        Text([book.author, book.finishedAt.map { "סיום: " + HebrewDate.text($0) } ?? ""]
                                            .filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                            if book.id != finished.last?.id { Divider().padding(.leading, 48) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .cardSurface()
                    .cascade(5)
                }
            }
            .padding(16)
            .animation(.section, value: books.map(\.page))
        }
        .background { AmbientGround(artwork: BooksView.artwork) }
        .navigationTitle("מדף הספרים")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("ספר חדש", systemImage: "plus") { isAdding = true }
            }
        }
        .arrives()
        .sheet(isPresented: $isAdding) { BookSheet(book: nil) }
        .sheet(item: $editing) { book in BookSheet(book: book) }
    }

    /// The finished books as spines standing on a shelf, the newest first.
    private var shelf: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(finished.enumerated()), id: \.element.id) { index, book in
                        Button {
                            editing = book
                        } label: {
                            spine(book)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(book.title)
                        .cascade(4 + index)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            // The board the books stand on.
            Capsule()
                .fill(Theme.chip)
                .frame(height: 7)
        }
    }

    private func spine(_ book: Book) -> some View {
        // Every book keeps its own height and thickness.
        let height: CGFloat = 122 + CGFloat((abs(book.palette) * 7 + book.title.count * 13) % 37)
        let width: CGFloat = 38 + CGFloat(min(max(book.totalPages, 0), 600)) / 600 * 20
        return UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 2,
                                      bottomTrailingRadius: 2, topTrailingRadius: 6, style: .continuous)
            .fill(book.artwork.gradient)
            .frame(width: width, height: height)
            .overlay {
                Text(book.title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: height - 34, alignment: .leading)
                    // A Hebrew spine reads from the top down. The turn is
                    // mirrored in a right-to-left layout, hence the sign.
                    .rotationEffect(.degrees(90))
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.white.opacity(0.4))
                    .frame(height: 2)
                    .padding(.top, 9)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.white.opacity(0.4))
                    .frame(height: 2)
                    .padding(.bottom, 9)
            }
            .shadow(color: book.artwork.end.opacity(0.35), radius: 6, y: 3)
    }

    private var hero: some View {
        let today = reading.reduce(0) { $0 + $1.pagesToday }
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("קריאה")
                    .font(.system(size: 15, weight: .semibold))
                    .opacity(0.9)
                Text(today > 0 ? "\(today) עמודים היום" : (reading.isEmpty ? "מה קוראים עכשיו?" : "עוד לא קראנו היום"))
                    .font(.system(size: 28, weight: .heavy))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(streak > 1 ? "\(streak) ימים ברצף של קריאה. גם עמוד אחד שומר על הרצף."
                     : "עמוד אחד ביום עדיף על פרק שלם פעם בשבוע.")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.92)
            }
            Spacer(minLength: 0)
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 40, weight: .bold))
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(20)
        .livingCard(BooksView.artwork, seed: 0.35)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "book")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("המדף עוד ריק")
                .font(.system(size: 20, weight: .heavy))
            Text("הוסיפו את הספר שאתם קוראים עכשיו, ועדכנו בכל יום לאיזה עמוד הגעתם. האפליקציה תחשב את הקצב ומתי תסיימו.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("הוספת ספר ראשון", systemImage: "plus") { isAdding = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// One book in progress: where we are, how fast, and a quick way to move forward.
struct BookCard: View {
    let book: Book
    let onOpen: () -> Void
    @Environment(\.modelContext) private var context

    private var line: String {
        var parts: [String] = []
        if book.totalPages > 0 {
            parts.append("עמוד \(book.page) מתוך \(book.totalPages)")
        } else {
            parts.append("עמוד \(book.page)")
        }
        if book.pace >= 0.5 { parts.append("כ־\(Int(book.pace.rounded())) עמודים ביום") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(book.artwork.gradient)
                        .frame(width: 52, height: 72)
                        .overlay {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .shadow(color: book.artwork.end.opacity(0.4), radius: 8, y: 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.title)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !book.author.isEmpty {
                            Text(book.author)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(line)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                    if book.totalPages > 0 {
                        ProgressRing(share: book.share, lineWidth: 6, track: Theme.chip, fill: book.artwork.start)
                            .frame(width: 50, height: 50)
                            .overlay {
                                Text(book.share, format: .percent.precision(.fractionLength(0)))
                                    .font(.system(size: 12, weight: .heavy))
                                    .monospacedDigit()
                            }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            if let finish = book.finishDate {
                Label("בקצב הזה תסיימו ב־\(finish.formatted(Date.FormatStyle(locale: Ledger.hebrew).day().month(.wide)))",
                      systemImage: "flag.checkered")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 8) {
                ForEach([1, 5, 10, 20], id: \.self) { step in
                    Button {
                        withAnimation(.section) { book.setPage(book.page + step) }
                        try? context.save()
                        if !book.isFinished || !Book.celebrateFinish(book) { Feedback.done() }
                    } label: {
                        Text("+\(step)")
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .foregroundStyle(Color.primary)
                            .background(Theme.chip, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("קראתי עוד \(step) עמודים")
                }
            }
        }
        .padding(16)
        .cardSurface()
    }
}

/// Adding a book, or correcting its details and the page reached.
struct BookSheet: View {
    let book: Book?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var totalText = ""
    @State private var pageText = ""
    @State private var palette = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("שם הספר", text: $title)
                        .font(.system(size: 18, weight: .semibold))
                    TextField("מחבר (לא חובה)", text: $author)
                }
                Section {
                    TextField("כמה עמודים יש בספר", text: $totalText)
                        .keyboardType(.numberPad)
                    TextField("באיזה עמוד אנחנו עכשיו", text: $pageText)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("מספר העמודים מאפשר לחשב את הקצב ולהעריך מתי תסיימו.")
                }
                Section("צבע הכריכה") {
                    PaletteRow(selection: $palette)
                }
                if let book {
                    Section {
                        Button("הסרה מהמדף", role: .destructive) {
                            book.removed = true
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(book == nil ? "ספר חדש" : "ספר")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let book else { return }
                title = book.title
                author = book.author
                totalText = book.totalPages > 0 ? "\(book.totalPages)" : ""
                pageText = "\(book.page)"
                palette = book.palette
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespaces)
        let total = Int(totalText) ?? 0
        let page = Int(pageText) ?? 0
        if let book {
            let wasFinished: Bool = book.isFinished
            book.title = name
            book.author = author.trimmingCharacters(in: .whitespaces)
            book.totalPages = total
            book.palette = palette
            if page != book.page { book.setPage(page) }
            // After the sheet has closed, on the screen behind it.
            if book.isFinished, !wasFinished { Book.celebrateFinish(book, after: 0.5) }
        } else {
            let new = Book(title: name, author: author.trimmingCharacters(in: .whitespaces),
                           totalPages: total, palette: palette)
            new.page = page
            if page > 0 { new.log = "\(DayKey.of(Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)):\(page)" }
            context.insert(new)
            Feedback.added()
        }
        try? context.save()
        Notifier.shared.refresh(in: context)
    }
}
