import SwiftData
import SwiftUI

/// A colorful rounded square with a symbol, like an album cover.
struct ArtworkIcon: View {
    let artwork: Artwork
    let symbol: String
    var size: CGFloat = 42

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(artwork.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// A bold section title with a chevron, as in Apple Music.
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .padding(.horizontal, 4)
    }
}

/// What is on now, or the next time of the day, floating above the tab bar
/// on every screen. Tapping it opens the schedule; the bolt adds anything.
struct NowTaskBar: View {
    @Binding var selection: AppTab
    @Query(filter: #Predicate<ScheduleItem> { !$0.removed }, sort: \ScheduleItem.startMinute)
    private var items: [ScheduleItem]
    @AppStorage(City.storageKey) private var cityID = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let status = NowStatus.make(items: items, now: timeline.date)
            HStack(spacing: 10) {
                Button {
                    selection = .schedule
                } label: {
                    HStack(spacing: 10) {
                        ArtworkIcon(artwork: status.artwork, symbol: status.symbol, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(status.title)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(status.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    AppRouter.shared.isQuickAdding = true
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("הוספה מהירה")
            }
            .padding(.horizontal, 12)
            .id(cityID)
        }
    }
}
