import SwiftUI

struct PerformanceView: View {
    @ObservedObject var camera: CameraManager
    @ObservedObject var tracker: HandTracker

    @Binding var showTutorial: Bool
    let exitToHome: () -> Void

    @State private var viewSize: CGSize = .zero

    var body: some View {
        ZStack {

            ZStack {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()

                HandOverlay(hands: tracker.hands, trackingOK: tracker.trackingOK)
                    .scaleEffect(0.88)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .rotationEffect(.degrees(90))
            .scaleEffect(x: 1, y: -1)
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Back") { exitToHome() }
                    Spacer()
                    Button("Help") { showTutorial = true }
                }
                .padding()
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("frames: \(camera.frameCount)")
                Text("hands: \(tracker.hands.count)")
                Text("visionRuns: \(tracker.visionRuns)")
                Text("visionResults: \(tracker.visionResults)")
                Text("trackingOK: \(tracker.trackingOK.description)")
                if !tracker.lastVisionError.isEmpty {
                    Text("error: \(tracker.lastVisionError)")
                        .foregroundStyle(.red)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 12)
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewSize = geo.size }
                    .onChange(of: geo.size) { _, new in viewSize = new }
            }
        )
        .onAppear {
            camera.onFrame = { pixelBuffer, orientation in
                tracker.process(pixelBuffer: pixelBuffer, orientation: orientation, viewSize: viewSize)
            }
        }
    }
}
