import SwiftUI

private struct ArrivedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False for the instant before a screen opens, then true. Pictures use
    /// the change to draw themselves: rings close, bars grow, numbers count.
    var arrived: Bool {
        get { self[ArrivedKey.self] }
        set { self[ArrivedKey.self] = newValue }
    }
}

/// Marks a screen or a sheet that was just opened, so its pictures draw
/// themselves once.
struct Arrives: ViewModifier {
    @State private var isHere = false
    @Environment(\.arrived) private var outer

    func body(content: Content) -> some View {
        content
            .environment(\.arrived, isHere && outer)
            .onAppear { isHere = true }
    }
}

/// Lets the parts of a screen arrive one after another instead of all at once.
struct Cascade: ViewModifier {
    let index: Int
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived || reduceMotion ? 0 : 18)
            .animation(.smooth(duration: 0.45).delay(0.045 * Double(min(index, 9))), value: arrived)
    }
}

extension View {
    /// See `Arrives`.
    func arrives() -> some View {
        modifier(Arrives())
    }

    /// See `Cascade`. Lower numbers arrive first.
    func cascade(_ index: Int) -> some View {
        modifier(Cascade(index: index))
    }

    /// Uncovers a chart from one side as its screen opens.
    func reveal(_ edge: RevealEdge, delay: Double = 0.2) -> some View {
        modifier(Reveal(edge: edge, delay: delay))
    }

    /// Uncovers a round chart the way a clock hand goes once around.
    func sweepReveal(delay: Double = 0.2) -> some View {
        modifier(SweepReveal(delay: delay))
    }
}

/// Text that can be animated through every value on the way to a number.
private struct RollingText: View, Animatable {
    var value: Double
    let text: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(text(value))
    }
}

/// A number that counts up to its value as its screen opens, and rolls to a
/// new value whenever it changes inside an animation.
struct CountUp: View {
    let value: Double
    var duration: Double = 0.9
    let text: (Double) -> String
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RollingText(value: arrived || reduceMotion ? value : 0, text: text)
            .animation(.easeOut(duration: duration), value: arrived)
            .accessibilityLabel(text(value))
    }
}

/// A rounded bar that fills up to its share as its screen opens.
struct GrowBar<Fill: ShapeStyle>: View {
    let share: Double
    var height: CGFloat = 8
    var track: Color = Theme.chip
    var delay: Double = 0.15
    let fill: Fill
    @Environment(\.arrived) private var arrived

    var body: some View {
        let clamped = CGFloat(min(max(share, 0), 1))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: arrived ? max(proxy.size.width * clamped, clamped > 0 ? height : 0) : 0)
                    .animation(.smooth(duration: 0.8).delay(delay), value: arrived)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

enum RevealEdge {
    case leading, bottom
}

/// See `View.reveal`.
struct Reveal: ViewModifier {
    let edge: RevealEdge
    var delay: Double = 0.2
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction

    func body(content: Content) -> some View {
        let isOpen = arrived || reduceMotion
        let closed: CGFloat = 0.0001
        // The leading edge is on the right when the text runs right to left.
        let side: UnitPoint = UnitPoint(x: direction == .rightToLeft ? 1 : 0, y: 0.5)
        let anchor: UnitPoint = edge == .leading ? side : UnitPoint(x: 0.5, y: 1)
        content
            .mask {
                Rectangle()
                    .scaleEffect(x: edge == .leading && !isOpen ? closed : 1,
                                 y: edge == .bottom && !isOpen ? closed : 1,
                                 anchor: anchor)
                    .animation(.smooth(duration: 0.9).delay(delay), value: arrived)
            }
    }
}

/// See `View.sweepReveal`.
struct SweepReveal: ViewModifier {
    var delay: Double = 0.2
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { proxy in
                    // A stroke as wide as its own circle is a wedge that
                    // grows around the middle.
                    let reach: CGFloat = min(proxy.size.width, proxy.size.height) + 16
                    Circle()
                        .trim(from: 0, to: arrived || reduceMotion ? 1 : 0)
                        .stroke(Color.black, lineWidth: reach / 2)
                        .frame(width: reach / 2, height: reach / 2)
                        .rotationEffect(.degrees(-90))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .animation(.smooth(duration: 1.0).delay(delay), value: arrived)
                }
            }
    }
}

/// A soft light that crosses a colorful surface once as its screen opens.
struct Shine: ViewModifier {
    var delay: Double = 0.45
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.3), .white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.45, height: proxy.size.height * 2.2)
                            .rotationEffect(.degrees(20))
                            .position(x: proxy.size.width * (arrived ? 1.5 : -0.5), y: proxy.size.height / 2)
                            .animation(.easeInOut(duration: 1.1).delay(delay), value: arrived)
                    }
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }
}

/// A small ring of sparks around something that was just completed.
struct SparkBurst: View {
    /// Rises by one for every burst.
    let trigger: Int
    var color: Color = Theme.accent
    var reach: CGFloat = 20
    /// How far from the middle the sparks start.
    var radius: CGFloat = 13
    @State private var progress: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 8)
                    .offset(y: -(radius + reach * progress))
                    .rotationEffect(.degrees(Double(index) * 45))
            }
        }
        .opacity(Double(1 - progress))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { progress = 0 }
            // The first frame has to be drawn before the sparks fly out.
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.55)) { progress = 1 }
            }
        }
    }
}
