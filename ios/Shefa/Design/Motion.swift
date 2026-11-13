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
/// moving between areas never feels like a hard cut, and tells the pictures
/// inside to draw themselves again.
struct TabEntrance: ViewModifier {
    let isActive: Bool
    /// Content starts visible, so nothing can ever stay hidden; only a
    /// switch between tabs plays the entrance.
    @State private var isShown = true
    /// See `EnvironmentValues.arrived`.
    @State private var arrived = true
    @State private var lastPlayed = Date.distantPast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @MainActor private static var hasLaunched = false

    func body(content: Content) -> some View {
        content
            .environment(\.arrived, arrived)
            .opacity(isShown ? 1 : 0)
            .offset(y: isShown || reduceMotion ? 0 : 10)
            .onAppear {
                if Self.hasLaunched {
                    if isActive { play() }
                } else if isActive {
                    open()
                }
                Self.hasLaunched = true
            }
            .onChange(of: isActive) { _, value in
                if value { play() }
            }
    }

    private func play() {
        // A tab seen for the first time reports both "appeared" and "became
        // active"; the entrance must run once, or the screen visibly jumps.
        guard Date.now.timeIntervalSince(lastPlayed) > 0.6 else { return }
        lastPlayed = .now
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            isShown = false
            arrived = false
        }
        // The hidden state has to be drawn once before the glide in starts.
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.32)) {
                isShown = true
                arrived = true
            }
        }
    }

    /// The first screen after launch waits behind the opening curtain and
    /// draws its pictures as the curtain lifts.
    private func open() {
        lastPlayed = .now
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { arrived = false }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Launch.curtain))
            arrived = true
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
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }
}

extension Animation {
    static var section: Animation { .smooth(duration: 0.34) }
}
