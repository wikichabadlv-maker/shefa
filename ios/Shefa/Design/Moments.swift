import Observation
import SwiftUI

/// One rare, big celebration: the whole screen floods with color.
struct Moment: Identifiable, Equatable {
    let id = UUID()
    let symbol: String
    let title: String
    let text: String
    let artwork: Artwork
}

/// Decides when a celebration takes the whole screen. Each kind is shown
/// once a day, so that it stays rare; a repeat on the same day is left to
/// the usual chime of whoever asked.
@Observable
final class Moments {
    static let shared = Moments()

    var current: Moment?
    /// The screens that can show a moment, the front one last.
    var hosts: [UUID] = []

    /// Returns true when the celebration is shown, with its own sound. With
    /// a delay it waits first, for a sheet that is still closing above it.
    @discardableResult
    func play(_ kind: String, symbol: String, title: String, text: String, artwork: Artwork,
              after delay: Double = 0) -> Bool {
        let key = "moment." + kind
        let today = DayKey.of()
        guard UserDefaults.standard.string(forKey: key) != today else { return false }
        UserDefaults.standard.set(today, forKey: key)
        let moment = Moment(symbol: symbol, title: title, text: text, artwork: artwork)
        guard delay > 0 else {
            Feedback.celebrate()
            current = moment
            return true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            Feedback.celebrate()
            self.current = moment
        }
        return true
    }

    /// Shows a moment with no conditions, for a test run.
    func show(symbol: String, title: String, text: String, artwork: Artwork) {
        current = Moment(symbol: symbol, title: title, text: text, artwork: artwork)
    }

    func close(_ moment: Moment) {
        if current?.id == moment.id { current = nil }
    }

    /// A savings goal that was just filled to the top.
    static func goalReached(_ goal: SavingsGoal) {
        shared.play("goal." + goal.id, symbol: goal.symbol, title: "הגעתם ליעד",
                    text: "\(goal.title): \(Money.text(goal.target)) בצד.", artwork: goal.artwork)
    }
}

/// Lets a screen show the celebrations. The front screen shows them, so a
/// moment that starts inside a sheet is seen there.
struct MomentHost: ViewModifier {
    @State private var moments = Moments.shared
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if let moment = moments.current, moments.hosts.last == id {
                        MomentView(moment: moment) {
                            withAnimation(.easeInOut(duration: 0.45)) { moments.close(moment) }
                        }
                        .id(moment.id)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    }
                }
            }
            .onAppear {
                if !moments.hosts.contains(id) { moments.hosts.append(id) }
            }
            .onDisappear {
                moments.hosts.removeAll { $0 == id }
            }
    }
}

extension View {
    /// See `MomentHost`.
    func momentHost() -> some View {
        modifier(MomentHost())
    }
}

/// The celebration itself: color floods out of the middle of the screen, a
/// white disc lands with the symbol, and paper flies.
struct MomentView: View {
    let moment: Moment
    let close: () -> Void
    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let reach: CGFloat = max(proxy.size.width, proxy.size.height) * 1.5
            ZStack {
                LivingGradient(artwork: moment.artwork, seed: 0.4)
                    .mask {
                        Circle()
                            .frame(width: reach, height: reach)
                            .scaleEffect(isOpen || reduceMotion ? 1 : 0.001)
                            .animation(.easeOut(duration: 0.55), value: isOpen)
                    }
                    .opacity(isOpen || !reduceMotion ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: isOpen)
                if isOpen {
                    ConfettiBurst()
                }
                VStack(spacing: 30) {
                    disc
                    words
                }
                .padding(.horizontal, 32)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { close() }
        .onAppear { isOpen = true }
        .task {
            // A test run keeps the moment on screen for its picture.
            guard Launch.screen.isEmpty else { return }
            try? await Task.sleep(for: .seconds(3.8))
            if !Task.isCancelled { close() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(moment.title). \(moment.text)")
        .accessibilityHint("הקשה סוגרת")
        .accessibilityAddTraits(.isModal)
    }

    private var disc: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                    .frame(width: 150, height: 150)
                    .scaleEffect(isOpen && !reduceMotion ? 2.5 + CGFloat(index) * 0.9 : 1)
                    .opacity(isOpen ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.4).delay(0.28 + Double(index) * 0.24), value: isOpen)
            }
            Circle()
                .fill(Color.white)
                .frame(width: 150, height: 150)
                .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
            Image(systemName: moment.symbol)
                .font(.system(size: 66, weight: .heavy))
                .foregroundStyle(moment.artwork.end)
                .symbolEffect(.bounce, value: isOpen)
        }
        .scaleEffect(isOpen || reduceMotion ? 1 : 0.4)
        .opacity(isOpen ? 1 : 0)
        .animation(.spring(duration: 0.6, bounce: 0.3).delay(0.12), value: isOpen)
    }

    private var words: some View {
        VStack(spacing: 10) {
            Text(moment.title)
                .font(.system(size: 40, weight: .heavy))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Text(moment.text)
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)
                .opacity(0.92)
        }
        .foregroundStyle(.white)
        .opacity(isOpen ? 1 : 0)
        .offset(y: isOpen || reduceMotion ? 0 : 18)
        .animation(.smooth(duration: 0.5).delay(0.32), value: isOpen)
    }
}

/// Paper thrown up from the middle of the screen, once.
struct ConfettiBurst: View {
    var count = 84
    @State private var start = Date.now
    @State private var isOver = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [
        .white, Color(hex: 0xFDE68A), Color(hex: 0xFBCFE8), Color(hex: 0xBAE6FD), Color(hex: 0xA7F3D0),
    ]

    var body: some View {
        ZStack {
            if !reduceMotion && !isOver {
                TimelineView(.animation) { timeline in
                    let time: Double = timeline.date.timeIntervalSince(start)
                    Canvas { context, size in
                        for index in 0..<count {
                            ConfettiBurst.draw(index, at: time, in: size, with: context)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(3.4))
            isOver = true
        }
    }

    /// One piece of paper: thrown upward, slowed by the air, then falling.
    private static func draw(_ index: Int, at time: Double, in size: CGSize, with context: GraphicsContext) {
        let seed: Double = Double(index) + 1
        let age: Double = time - 0.15 - Noise.unit(seed * 5.3) * 0.18
        if age <= 0 || age > 3 { return }
        let angle: Double = -Double.pi / 2 + (Noise.unit(seed * 1.7) - 0.5) * 2.7
        let speed: Double = 380 + Noise.unit(seed * 3.1) * 640
        let travel: Double = speed * (1 - exp(-age * 2.2)) / 2.2
        let x: Double = Double(size.width) / 2 + cos(angle) * travel
        let y: Double = Double(size.height) * 0.4 + sin(angle) * travel + 250 * age * age
        let side: Double = 7 + Noise.unit(seed * 7.9) * 7
        let turn: Double = age * (3 + Noise.unit(seed * 9.2) * 6) + seed
        let flip: Double = cos(turn * 1.7)
        var piece: GraphicsContext = context
        piece.opacity = min(max((2.7 - age) / 0.8, 0), 1)
        piece.translateBy(x: CGFloat(x), y: CGFloat(y))
        piece.rotate(by: Angle(radians: turn))
        // Paper turning in the air shows its thin side now and then.
        piece.scaleBy(x: 1, y: CGFloat(abs(flip) < 0.08 ? 0.08 : flip))
        let rect = CGRect(x: -side / 2, y: -side * 0.3, width: side, height: side * 0.6)
        let color: Color = colors[index % colors.count]
        piece.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
    }
}
