import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct RootView: View {

    @StateObject private var camera = CameraManager()
    @StateObject private var tracker = HandTracker()
    @StateObject private var audio = AudioEngineManager()

    @State private var viewSize: CGSize = .zero
    @State private var showFilePicker = false

    @State private var smoothedVolume: Float = 0.5
    @State private var smoothedBassDb: Float = 0.0
    @State private var holdVolume: Float = 0.5

    var body: some View {
        ZStack {
            // Camera + Overlay share transform
            ZStack {
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()

                HandOverlay(
                    hands: tracker.hands,
                    trackingOK: tracker.trackingOK
                )
                .scaleEffect(0.88)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            .rotationEffect(.degrees(90))
            .scaleEffect(x: 1, y: -1)
            .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) {
            hud
                .padding(.top, 12)
                .padding(.leading, 12)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    audio.load(url: url)
                }
            case .failure(let err):
                print("File picker error:", err)
            }
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
                tracker.process(pixelBuffer: pixelBuffer,
                                orientation: orientation,
                                viewSize: viewSize)
            }

            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else { return }
                DispatchQueue.main.async {
                    camera.configure()
                    camera.start()
                }
            }
        }
        .onReceive(tracker.$hands) { hands in
            applyHandControls(hands)
        }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(spacing: 12) {
                Button("Choose Audio") { showFilePicker = true }

                Button(audio.isPlaying ? "Pause" : "Play") {
                    audio.isPlaying ? audio.pause() : audio.play()
                }
                .disabled(!audio.isLoaded)

                Text(audio.loadedFileName)
                    .lineLimit(1)
                    .font(.system(size: 12))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("frames: \(camera.frameCount)")
                Text("hands: \(tracker.hands.count)")
                Text("trackingOK: \(tracker.trackingOK.description)")
                Text(String(format: "volume: %.2f", smoothedVolume))
                Text(String(format: "bass: %.1f dB", smoothedBassDb))

                if !tracker.lastVisionError.isEmpty {
                    Text("error: \(tracker.lastVisionError)")
                        .foregroundStyle(.red)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(10)
        .background(.ultraThinMaterial)     // ✅ now only behind HUD, not half your screen
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // LEFT: pinch-gated volume (more responsive)
    // RIGHT: span bass (as before)
    private func applyHandControls(_ hands: [HandPose]) {

        let left  = hands.first(where: { $0.id == 0 })
        let right = hands.first(where: { $0.id == 1 })

        if let left {
            let pinchNorm = Float(left.pinchDistancePx / max(1, viewSize.width))
            let isPinching = pinchNorm < 0.055

            let wristY = Float(jointY(left, "wrist") ?? 0.5)
            let wristVol = curve(map(wristY, inMin: 0.10, inMax: 0.90, outMin: 0.0, outMax: 1.0))
            let pinchVol = curve(map(pinchNorm, inMin: 0.015, inMax: 0.060, outMin: 0.0, outMax: 1.0))

            let target = clamp(0.75 * wristVol + 0.25 * pinchVol, 0, 1)

            if isPinching {
                holdVolume = smooth(holdVolume, target, alpha: 0.30) // snappier
                smoothedVolume = holdVolume
                audio.setVolume(smoothedVolume)
            } else {
                smoothedVolume = holdVolume
            }
        }

        if let right, viewSize.width > 1 {
            let spanNorm = Float(right.spanDistancePx / max(1, viewSize.width))
            let bassDb = map(spanNorm, inMin: 0.06, inMax: 0.30, outMin: -10, outMax: 12)

            smoothedBassDb = smooth(smoothedBassDb, bassDb, alpha: 0.12)
            audio.setBassGainDb(smoothedBassDb)
        }
    }

    private func jointY(_ hand: HandPose, _ jointId: String) -> CGFloat? {
        hand.landmarks.first(where: { $0.id == jointId })?.point.y
    }

    private func smooth(_ current: Float, _ target: Float, alpha: Float) -> Float {
        current + alpha * (target - current)
    }

    private func clamp(_ x: Float, _ lo: Float, _ hi: Float) -> Float {
        min(max(x, lo), hi)
    }

    private func map(_ x: Float, inMin: Float, inMax: Float, outMin: Float, outMax: Float) -> Float {
        if inMax - inMin == 0 { return outMin }
        let t = clamp((x - inMin) / (inMax - inMin), 0, 1)
        return outMin + t * (outMax - outMin)
    }

    private func curve(_ x: Float) -> Float {
        pow(clamp(x, 0, 1), 0.65)
    }
}
