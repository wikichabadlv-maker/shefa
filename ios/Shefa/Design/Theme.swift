import SwiftUI

/// Colors and shapes shared by every screen. Light and dark values follow the
/// approved design: a clean ground, bold type and one vivid "artwork" card.
enum Theme {
    static let accent = Color("Accent", bundle: nil, light: 0x047857, dark: 0x34D399)
    static let ground = Color("Ground", bundle: nil, light: 0xF5F6F8, dark: 0x000000)
    static let card = Color("Card", bundle: nil, light: 0xFFFFFF, dark: 0x1C1C1E)
    static let chip = Color("Chip", bundle: nil, light: 0xEBECF0, dark: 0x2C2C2E)
    static let amberGround = Color("AmberGround", bundle: nil, light: 0xFEF3C7, dark: 0x4A3A10)
    static let amberInk = Color("AmberInk", bundle: nil, light: 0x92400E, dark: 0xFDE68A)

    static let emerald = Artwork(0x047857, 0x0F766E)
    static let amber = Artwork(0xD97706, 0x92400E)
    static let blue = Artwork(0x2563EB, 0x1E3A8A)
    static let violet = Artwork(0x7C3AED, 0x4C1D95)
    static let pink = Artwork(0xDB2777, 0x9D174D)
    static let green = Artwork(0x10B981, 0x047857)

    static let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
}

/// A two-color gradient used for the colorful "album cover" squares and cards.
struct Artwork: Hashable {
    let start: Color
    let end: Color

    init(_ start: UInt32, _ end: UInt32) {
        self.start = Color(hex: start)
        self.end = Color(hex: end)
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A color that changes with the light or dark appearance.
    init(_ name: String, bundle: Bundle?, light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

extension View {
    /// The standard white card with a soft shadow.
    func cardSurface() -> some View {
        self
            .background(Theme.card, in: Theme.cardShape)
            .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
            .scrollTransition(.animated(.spring(duration: 0.4)).threshold(.visible(0.08))) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.55)
                    .scaleEffect(phase.isIdentity ? 1 : 0.965)
            }
    }
}
