import SwiftUI

/// The opening curtain: the app's color and name for a moment, lifting to
/// show the first screen while its pictures draw themselves.
struct Splash: View {
    @State private var isSet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // The same color as the launch screen, so the two join without a seam.
            Color(hex: 0x047857)
            LivingGradient(artwork: Theme.emerald)
                .opacity(isSet ? 1 : 0)
                .animation(.easeOut(duration: 0.4), value: isSet)
            VStack(spacing: 0) {
                Text("שפע")
                    .font(.system(size: 78, weight: .heavy))
                Text("של עשייה")
                    .font(.system(size: 22, weight: .semibold))
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .scaleEffect(isSet || reduceMotion ? 1 : 0.92)
            .opacity(isSet ? 1 : 0)
            .animation(.smooth(duration: 0.45), value: isSet)
        }
        .ignoresSafeArea()
        .onAppear { isSet = true }
        .accessibilityHidden(true)
    }
}
