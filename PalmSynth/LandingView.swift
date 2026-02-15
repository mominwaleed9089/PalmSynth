
import SwiftUI

struct LandingView: View {
    let onHelp: () -> Void
    let onEnter: () -> Void

    @State private var glow = false
    @State private var drift = false

    var body: some View {
        ZStack {
            MelodramaticBackground(glow: $glow, drift: $drift)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    Button(action: onHelp) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding()
                }

                Spacer()

                Text("PalmSynth")
                    .font(.system(size: 44, weight: .bold))
                Text("Hand tracking demo (macOS build)")
                    .foregroundStyle(.secondary)

                Button("Enter") { onEnter() }
                    .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
        }
    }
}
