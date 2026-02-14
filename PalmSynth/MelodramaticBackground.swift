//
//  MelodramaticBackground.swift
//  PalmSynth
//
//  Created by Mo on 15/02/2026.
//


import SwiftUI

struct MelodramaticBackground: View {
    @Binding var glow: Bool
    @Binding var drift: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(white: 0.06), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .offset(x: drift ? 120 : -120, y: drift ? -60 : 80)
                .blur(radius: glow ? 40 : 60)
                .opacity(glow ? 0.9 : 0.6)
                .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: glow)
                .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: drift)
        }
        .onAppear {
            glow = true
            drift = true
        }
    }
}
