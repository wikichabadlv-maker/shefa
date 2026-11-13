import SwiftData
import SwiftUI

private enum AreaKind: String {
    case shopping, notes, learning, achievements, assistant, settings
}

private struct AppArea: Identifiable {
    let kind: AreaKind
    let title: String
    let subtitle: String
    let symbol: String
    let artwork: Artwork

    var id: String { kind.rawValue }
}

/// Search across the whole app, and the areas that are not in the tab bar.
struct MoreView: View {
    @State private var query = ""
    @State private var path: [String] = Launch.morePath
    @State private var viewing: LedgerEntry?
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ListItem> { !$0.removed }, sort: \ListItem.createdAt, order: .reverse)
    private var items: [ListItem]
    @Query(filter: #Predicate<LedgerEntry> { !$0.removed }, sort: \LedgerEntry.date, order: .reverse)
    private var entries: [LedgerEntry]

    private let areas = [
        AppArea(kind: .shopping, title: "רשימת קניות", subtitle: "משותפת לשניכם", symbol: "cart.fill", artwork: Theme.pink),
        AppArea(kind: .notes, title: "לזכור", subtitle: "פתקים ודברים חשובים", symbol: "lightbulb.fill", artwork: Theme.amber),
        AppArea(kind: .learning, title: "לימוד וחידושים", subtitle: "מה למדנו ומה חידשנו", symbol: "book.fill", artwork: Theme.blue),
        AppArea(kind: .achievements, title: "הישגים", subtitle: "מהפעילות האמיתית שלכם", symbol: "trophy.fill", artwork: Theme.violet),
        AppArea(kind: .assistant, title: "שפע · עוזר קולי", subtitle: "בקרוב", symbol: "waveform", artwork: Theme.emerald),
        AppArea(kind: .settings, title: "הגדרות", subtitle: "חשבון, עיר ומראה", symbol: "gearshape.fill", artwork: Artwork(0x64748B, 0x334155)),
    ]

    private func count(_ kind: String) -> Int {
        items.filter { $0.kind == kind && !$0.isDone }.count
    }

    private func badge(_ area: AppArea) -> String? {
        switch area.kind {
        case .shopping:
            let open = count(ListItem.shopping)
            return open > 0 ? "\(open)" : nil
        case .notes:
            let open = count(ListItem.note)
            return open > 0 ? "\(open)" : nil
        case .learning:
            let open = count(ListItem.learning)
            return open > 0 ? "\(open)" : nil
        default:
            return nil
        }
    }

    private func tile(_ area: AppArea) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Image(systemName: area.symbol)
                    .font(.system(size: 24, weight: .semibold))
                Spacer()
                if let text = badge(area) {
                    Text(text)
                        .font(.system(size: 13, weight: .heavy))
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(.white.opacity(0.25), in: Capsule())
                }
            }
            Spacer()
            Text(area.title)
                .font(.system(size: 17, weight: .heavy))
            Text(area.subtitle)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.85)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
        .background(area.artwork.gradient,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(area.kind == .assistant ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func destination(_ id: String) -> some View {
        switch AreaKind(rawValue: id) {
        case .shopping:
            CheckListView(kind: ListItem.shopping, title: "רשימת קניות", placeholder: "מה צריך לקנות?",
                          emptyText: "הרשימה ריקה. הוסיפו מוצר ראשון.")
        case .notes:
            NotesView(kind: ListItem.note, title: "לזכור", placeholder: "מה חשוב לזכור?",
                      emptyTitle: "עוד אין פתקים", emptyText: "קוד לדלת, מידה, רעיון למתנה. כל מה שלא רוצים לשכוח.",
                      symbol: "lightbulb.fill")
        case .learning:
            NotesView(kind: ListItem.learning, title: "לימוד וחידושים", placeholder: "מה למדתי? מה התחדש לי?",
                      emptyTitle: "עוד אין רשומות", emptyText: "כתבו נקודה מהשיעור, חידוש, או מה מתכננים ללמוד.",
                      symbol: "book.fill")
        case .achievements:
            AchievementsView()
        case .settings:
            SettingsView()
        default:
            ComingSoonBody(title: "עוזר קולי", symbol: "waveform",
                           text: "דיבור חופשי כדי להוסיף הוצאה, מטלה או פתק. האזור הזה עוד לא נבנה.")
        }
    }

    private var matchedItems: [ListItem] {
        Array(items.filter { $0.title.localizedCaseInsensitiveContains(query) }.prefix(12))
    }

    private var matchedEntries: [LedgerEntry] {
        Array(entries.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.subTitle ?? "").contains(query)
                || ($0.category?.title ?? "").contains(query)
                || ($0.note ?? "").localizedCaseInsensitiveContains(query)
        }.prefix(25))
    }

    private func kindName(_ kind: String) -> String {
        switch kind {
        case ListItem.shopping: return "קניות"
        case ListItem.note: return "לזכור"
        case ListItem.learning: return "לימוד"
        default: return "מטלות"
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(areas) { area in
                            NavigationLink(value: area.id) {
                                tile(area)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                } else {
                    results
                        .padding(16)
                }
            }
            .background(Theme.ground)
            .navigationTitle("עוד")
            .navigationDestination(for: String.self) { id in
                destination(id)
            }
            .searchable(text: $query, prompt: "חיפוש בכל האפליקציה")
            .sheet(item: $viewing) { entry in
                EntryDetailSheet(entry: entry)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        let foundItems = matchedItems
        let foundEntries = matchedEntries
        VStack(alignment: .leading, spacing: 18) {
            if foundItems.isEmpty && foundEntries.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            if !foundItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("רשימות ופתקים")
                        .font(.system(size: 20, weight: .heavy))
                    VStack(spacing: 0) {
                        ForEach(foundItems) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? Theme.accent : Color.secondary)
                                Text(item.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                Text(kindName(item.kind))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 46)
                            if item.id != foundItems.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .cardSurface()
                }
            }
            if !foundEntries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("תנועות")
                        .font(.system(size: 20, weight: .heavy))
                    VStack(spacing: 0) {
                        ForEach(foundEntries) { item in
                            Button {
                                viewing = item
                            } label: {
                                TransactionRow(entry: item).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if item.id != foundEntries.last?.id {
                                Divider().padding(.leading, 54)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .cardSurface()
                }
            }
        }
    }
}

/// An honest placeholder for an area that is not built yet.
struct ComingSoonBody: View {
    let title: String
    let symbol: String
    let text: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
