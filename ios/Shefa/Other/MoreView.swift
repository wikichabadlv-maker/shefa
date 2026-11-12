import SwiftUI

struct AppArea: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let artwork: Artwork
}

/// Search, and the areas of the app that are not in the tab bar.
struct MoreView: View {
    @State private var query = ""

    private let areas = [
        AppArea(title: "לימוד וחידושים", symbol: "book.fill", artwork: Theme.blue),
        AppArea(title: "רשימת קניות", symbol: "cart.fill", artwork: Theme.pink),
        AppArea(title: "לזכור", symbol: "lightbulb.fill", artwork: Theme.amber),
        AppArea(title: "שפע · עוזר קולי", symbol: "waveform", artwork: Theme.emerald),
        AppArea(title: "הישגים", symbol: "trophy.fill", artwork: Theme.violet),
        AppArea(title: "הגדרות", symbol: "gearshape.fill", artwork: Artwork(0x64748B, 0x334155)),
    ]

    private var shown: [AppArea] {
        query.isEmpty ? areas : areas.filter { $0.title.contains(query) }
    }

    private func tile(_ area: AppArea) -> some View {
        VStack(alignment: .leading) {
            Image(systemName: area.symbol)
                .font(.system(size: 24, weight: .semibold))
            Spacer()
            Text(area.title)
                .font(.system(size: 17, weight: .heavy))
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(area.artwork.gradient,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(shown) { area in
                        if area.symbol == "gearshape.fill" {
                            NavigationLink {
                                SettingsView()
                            } label: {
                                tile(area)
                            }
                            .buttonStyle(.plain)
                        } else {
                            tile(area)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("עוד")
            .searchable(text: $query, prompt: "חיפוש בכל האפליקציה")
        }
    }
}
