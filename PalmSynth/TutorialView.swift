//
//  TutorialView.swift
//  PalmSynth
//
//  Created by Mo on 15/02/2026.
//


import SwiftUI

struct TutorialView: View {
    let onDismiss: () -> Void
    @State private var page: Int = 0

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("How to use")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }

            TabView(selection: $page) {
                pageView(
                    title: "Show your hand",
                    body: "Keep your hand in view of the camera. The overlay lines and points confirm it’s being tracked."
                ).tag(0)

                pageView(
                    title: "Pinch distance",
                    body: "The bright line between thumb and index shows pinch distance. It’s measured live in pixels."
                ).tag(1)

                pageView(
                    title: "Span distance",
                    body: "The line between index and little finger shows hand span, also measured live."
                ).tag(2)
            }
#if os(iOS)
.tabViewStyle(.page(indexDisplayMode: .automatic))
#else
.tabViewStyle(.automatic)
#endif

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 380)
    }

    private func pageView(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            Text(body)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 6)
    }
}
