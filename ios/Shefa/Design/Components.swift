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

/// The current schedule task, shown above the tab bar on every screen.
struct NowTaskBar: View {
    let task: ScheduleTask
    @State private var isDone = false

    var body: some View {
        HStack(spacing: 10) {
            ArtworkIcon(artwork: Theme.green, symbol: task.symbol, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Text(isDone ? "הושלם" : "עכשיו בלו״ז · נשארו \(task.minutesLeft) דק׳")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                isDone.toggle()
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("סיימתי")
        }
        .padding(.horizontal, 12)
    }
}

/// A full-screen placeholder for an area that is built in a later stage.
struct ComingSoonView: View {
    let title: String
    let symbol: String
    let text: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(text + "\nהמסך הזה נבנה בשלב הבא.")
            }
            .background(Theme.ground)
            .navigationTitle(title)
        }
    }
}
