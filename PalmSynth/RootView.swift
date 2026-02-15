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
    @State private var bassHoldDb: Float = 0.0
    @State private var rightPinchLatched: Bool = false
    @State private var lastPalmY: Float = 0.5
    @State private var leftPinchLatched: Bool = false
 

    
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
        .fixedSize(horizontal: true, vertical: true) // ✅ prevents “half-screen” expansion
        
        
    }
    
    
    
    // hand controls are here
    private func applyHandControls(_ hands: [HandPose]) {

        let left  = hands.first(where: { $0.id == 0 })
        let right = hands.first(where: { $0.id == 1 })

        // Pinch hysteresis thresholds (normalized by view width)
        // Smaller pinchNorm = tighter pinch
        let pinchOn: Float  = 0.070
        let pinchOff: Float = 0.095

        // -----------------------------
        // LEFT HAND: VOLUME by PINCH (latched)
        // -----------------------------
        if let left, viewSize.width > 1 {

            let pinchNorm = Float(left.pinchDistancePx / max(1, viewSize.width))

            // Latch logic (hysteresis)
            if !leftPinchLatched && pinchNorm < pinchOn {
                leftPinchLatched = true
            } else if leftPinchLatched && pinchNorm > pinchOff {
                leftPinchLatched = false
            }

            if leftPinchLatched {
                // Map pinch to volume:
                // Tight pinch -> louder, open pinch -> quieter
                let vol = map(pinchNorm,
                              inMin: 0.020, inMax: 0.100,
                              outMin: 1.0, outMax: 0.0)

                // Optional curve for nicer feel + smoothing
                let target = curve(vol)
                holdVolume = smooth(holdVolume, clamp(target, 0, 1), alpha: 0.24)

                smoothedVolume = holdVolume
                audio.setVolume(smoothedVolume)
            } else {
                // Hold last value steady when not pinching
                smoothedVolume = holdVolume
            }
        }

        // -----------------------------
        // RIGHT HAND: BASS by PINCH (latched)
        // -----------------------------
        if let right, viewSize.width > 1 {

            let pinchNorm = Float(right.pinchDistancePx / max(1, viewSize.width))

            // Latch logic (hysteresis)
            if !rightPinchLatched && pinchNorm < pinchOn {
                rightPinchLatched = true
            } else if rightPinchLatched && pinchNorm > pinchOff {
                rightPinchLatched = false
            }

            if rightPinchLatched {
                // Tight pinch -> more bass, open pinch -> less bass
                let bassDb = map(pinchNorm,
                                 inMin: 0.020, inMax: 0.090,
                                 outMin: 12.0, outMax: -10.0)

                smoothedBassDb = smooth(smoothedBassDb, bassDb, alpha: 0.18)
                audio.setBassGainDb(smoothedBassDb)
            }
        }
    }

    
    // MARK: - Math helpers
    
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
    
    // Dead zone around the current value to avoid jitter changes.
    // This assumes x is already 0..1.
    private func applyDeadZone(_ x: Float, deadZone: Float) -> Float {
        // squash a small area around each value (simple and effective)
        // if you want deadzone around a fixed center, do that instead
        return round(x / deadZone) * deadZone
    }
    
    private func curve(_ x: Float) -> Float {
        pow(clamp(x, 0, 1), 0.65)
    }
}
