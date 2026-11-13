import SwiftUI

/// A button that gently presses in under the finger and springs back.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.965 : 1)
                .opacity(configuration.isPressed ? 0.88 : 1)
                .animation(.spring(duration: 0.25, bounce: 0.35), value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// Makes a tab's content glide in softly each time the tab is opened, so
/// moving between areas never feels like a hard cut.
struct TabEntrance: ViewModifier {
    let isActive: Bool
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isShown || reduceMotion ? 1 : 0.97)
            .offset(y: isShown || reduceMotion ? 0 : 14)
            .onAppear { reveal(isActive) }
            .onChange(of: isActive) { _, value in reveal(value) }
    }

    private func reveal(_ active: Bool) {
        if active {
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) { isShown = true }
        } else {
            isShown = false
        }
    }
}

extension View {
    func tabEntrance(_ isActive: Bool) -> some View {
        modifier(TabEntrance(isActive: isActive))
    }
}

extension AnyTransition {
    /// One section of a screen giving way to another: the new one rises in
    /// softly while the old one fades.
    static var sectionSwap: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 16)).combined(with: .scale(scale: 0.985)),
                    removal: .opacity)
    }
}

extension Animation {
    static var section: Animation { .spring(duration: 0.42, bounce: 0.18) }
}
