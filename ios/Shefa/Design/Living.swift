import SwiftUI

extension Artwork {
    /// A lighter relative of the first color, for the lit corner of a surface.
    var glow: Color { start.mix(with: .white, by: 0.2) }

    /// A deeper relative of the second color, for the far corner.
    var deep: Color { end.mix(with: .black, by: 0.28) }

    /// The color halfway between the two.
    var middle: Color { start.mix(with: end, by: 0.5) }
}

/// A gradient that is alive: its colors drift slowly, like the artwork behind
/// a song that is playing.
struct LivingGradient: View {
    let artwork: Artwork
    /// Shifts the motion, so neighbouring surfaces never move in step.
    var seed: Double = 0
    /// One flat color along the top, for a surface that continues upward.
    var flatTop = false
    /// A card inside a long page rests while it is scrolled out of sight.
    var restsOffscreen = false
    @State private var isOnScreen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Standing still also saves the battery when the phone asks for it.
        if reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled {
            mesh(at: seed * 9)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: restsOffscreen && !isOnScreen)) { timeline in
                mesh(at: timeline.date.timeIntervalSinceReferenceDate * 0.5 + seed * 9)
            }
            .onScrollVisibilityChange(threshold: 0.02) { isVisible in
                isOnScreen = isVisible
            }
        }
    }

    private func mesh(at time: Double) -> MeshGradient {
        func wave(_ speed: Double, _ shift: Double) -> Float {
            Float(sin(time * speed + shift))
        }
        let topX: Float = 0.5 + 0.14 * wave(0.9, 0.0)
        let leftY: Float = 0.5 + 0.14 * wave(0.7, 1.3)
        let midX: Float = 0.5 + 0.2 * wave(0.8, 2.1)
        let midY: Float = 0.5 + 0.18 * wave(0.6, 4.2)
        let rightY: Float = 0.5 + 0.14 * wave(0.75, 3.4)
        let bottomX: Float = 0.5 + 0.14 * wave(0.65, 5.0)
        let points: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(topX, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, leftY), SIMD2<Float>(midX, midY), SIMD2<Float>(1, rightY),
            SIMD2<Float>(0, 1), SIMD2<Float>(bottomX, 1), SIMD2<Float>(1, 1),
        ]
        let first: Color = flatTop ? artwork.start : artwork.glow
        let third: Color = flatTop ? artwork.start : artwork.middle
        let colors: [Color] = [
            first, artwork.start, third,
            artwork.start, artwork.middle, artwork.end,
            artwork.middle, artwork.end, artwork.deep,
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors,
                            background: artwork.end, smoothsColors: true, colorSpace: .perceptual)
    }
}

/// The surface of a colorful card: a living gradient, a lit edge, a shadow in
/// the card's own color, and a light that crosses it when its screen opens.
struct LivingCard: ViewModifier {
    let artwork: Artwork
    var radius: CGFloat = 28
    var seed: Double = 0
    /// A large faded symbol in the far corner, like the print on an album cover.
    var watermark: String?
    /// Small tiles keep a still gradient; only the main cards move.
    var isMoving = true
    @Environment(\.layoutDirection) private var direction

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape
                        .fill(artwork.end)
                        .shadow(color: artwork.end.opacity(0.4), radius: isMoving ? 18 : 10, y: isMoving ? 11 : 6)
                    Group {
                        if isMoving {
                            LivingGradient(artwork: artwork, seed: seed, restsOffscreen: true)
                        } else {
                            artwork.gradient
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let watermark {
                            Image(systemName: watermark)
                                .font(.system(size: radius > 24 ? 110 : 84, weight: .bold))
                                .foregroundStyle(.white.opacity(0.13))
                                .rotationEffect(.degrees(-14))
                                // It hangs a little over the far corner.
                                .offset(x: direction == .rightToLeft ? -16 : 16, y: 22)
                                .accessibilityHidden(true)
                        }
                    }
                    .modifier(Shine(delay: 0.4 + seed.truncatingRemainder(dividingBy: 1) * 0.5))
                    .clipShape(shape)
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
            }
    }
}

extension View {
    /// Puts the view on a colorful card. See `LivingCard`.
    func livingCard(_ artwork: Artwork, radius: CGFloat = 28, seed: Double = 0,
                    watermark: String? = nil, isMoving: Bool = true) -> some View {
        modifier(LivingCard(artwork: artwork, radius: radius, seed: seed,
                            watermark: watermark, isMoving: isMoving))
    }
}

/// The ground of a main screen, with a soft wash of the screen's own color
/// behind its title.
struct AmbientGround: View {
    let artwork: Artwork
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // On black a wash turns into a colored lamp, so it stays faint there.
        let strength: Double = scheme == .dark ? 0.2 : 0.24
        ZStack(alignment: .top) {
            Theme.ground
            ZStack {
                RadialGradient(colors: [artwork.start.opacity(strength), artwork.start.opacity(0)],
                               center: .topLeading, startRadius: 0, endRadius: 430)
                RadialGradient(colors: [artwork.end.opacity(strength * 0.7), artwork.end.opacity(0)],
                               center: .topTrailing, startRadius: 0, endRadius: 360)
            }
            .frame(height: 470)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.6), value: artwork)
        .accessibilityHidden(true)
    }
}

/// The colorful top of a screen that opens "in color". It belongs to the
/// scrolling content and reaches up behind the navigation bar.
struct StageBackdrop: View {
    let artwork: Artwork
    var height: CGFloat = 430

    /// How far the color continues above the content, for a pull downward.
    private static let reach: CGFloat = 900
    /// Room for the status bar and the navigation bar.
    private static let bar: CGFloat = 140

    var body: some View {
        VStack(spacing: 0) {
            artwork.start
                .frame(height: StageBackdrop.reach)
            LivingGradient(artwork: artwork, flatTop: true)
                .frame(height: height + StageBackdrop.bar)
                .mask {
                    LinearGradient(stops: [
                        Gradient.Stop(color: .black, location: 0),
                        Gradient.Stop(color: .black, location: 0.6),
                        Gradient.Stop(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
        }
        .offset(y: -(StageBackdrop.reach + StageBackdrop.bar))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A wave of liquid inside a vessel; `level` runs from 0, empty, to 1, full.
struct Wave: Shape {
    var level: Double
    var phase: Double
    var strength: Double = 0.04

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let clamped = min(max(level, 0), 1)
        let surface = rect.maxY - rect.height * CGFloat(clamped)
        // An empty vessel is still; the waves grow with the first drops.
        let calm = CGFloat(min(clamped * 8, 1))
        let amplitude = rect.height * CGFloat(strength) * calm
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x <= rect.maxX {
            let relative = Double((x - rect.minX) / max(rect.width, 1))
            let lift = CGFloat(sin(relative * 2 * Double.pi + phase))
            path.addLine(to: CGPoint(x: x, y: surface + amplitude * lift))
            x += 2
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A round vessel that fills up as a savings goal gets closer.
struct LiquidOrb: View {
    let share: Double
    @Environment(\.arrived) private var arrived
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let level: Double = arrived ? min(max(share, 0), 1) : 0
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(.white.opacity(0.16))
                Wave(level: level, phase: time * 1.3, strength: 0.05)
                    .fill(.white.opacity(0.26))
                Wave(level: level, phase: time * 1.9 + 2.2, strength: 0.035)
                    .fill(.white.opacity(0.4))
            }
            .animation(.smooth(duration: 1.3).delay(0.15), value: arrived)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Steady pseudo-random numbers, so a drawing looks the same on every frame.
enum Noise {
    static func unit(_ value: Double) -> Double {
        let raw = sin(value * 12.9898) * 43758.5453
        return raw - raw.rounded(.down)
    }
}

/// The colors of the sky at one moment of the day.
struct Sky {
    let artwork: Artwork
    let isNight: Bool

    /// `share` runs from 0 at sunrise to 1 at sunset; far outside that it is night.
    init(share: Double) {
        if share < -0.07 || share > 1.07 {
            artwork = Artwork(0x312E81, 0x0B1026)
            isNight = true
        } else if share < 0.1 {
            // Dawn.
            artwork = Artwork(0xEA580C, 0xBE185D)
            isNight = false
        } else if share < 0.78 {
            artwork = Sky.day
            isNight = false
        } else if share < 0.93 {
            // The golden hour.
            artwork = Artwork(0xEA580C, 0xDB2777)
            isNight = false
        } else {
            // Dusk.
            artwork = Artwork(0xBE185D, 0x4C1D95)
            isNight = false
        }
    }

    /// The plain blue of midday, also used for days other than today.
    static let day = Artwork(0x0284C7, 0x2563EB)

    /// A day that is not today is shown under a midday sky.
    static let midday = Sky(share: 0.4)

    /// The sky over a city right now.
    static func now(_ date: Date = .now) -> Sky {
        Sky(share: Zmanim(day: date).dayShare(at: date))
    }
}

/// A still field of stars that slowly twinkle.
struct StarField: View {
    var count = 54
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for index in 0..<count {
                    let seed = Double(index) + 1
                    let x = CGFloat(Noise.unit(seed * 1.3)) * size.width
                    let y = CGFloat(Noise.unit(seed * 2.9)) * size.height
                    let radius = CGFloat(0.6 + Noise.unit(seed * 4.7) * 1.2)
                    let pace = 0.5 + Noise.unit(seed * 6.1)
                    let twinkle = 0.3 + 0.7 * (0.5 + 0.5 * sin(time * pace + seed))
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The whole sky behind a screen: its colors, and at night its stars.
struct SkyBackdrop: View {
    let sky: Sky

    var body: some View {
        ZStack {
            LivingGradient(artwork: sky.artwork)
            if sky.isNight {
                StarField(count: 90)
            }
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.3)],
                           startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
