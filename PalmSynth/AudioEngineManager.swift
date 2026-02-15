import Foundation
import Combine
import AVFoundation

final class AudioEngineManager: ObservableObject {

    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var loadedFileName: String = "None"

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 1)

    private var audioFile: AVAudioFile?
    private var loopEnabled: Bool = true

    // Security-scoped access (sandbox)
    private var scopedURL: URL?

    init() {
        setupEngine()
    }

    deinit {
        stopSecurityScope()
    }

    private func setupEngine() {
        let band = eq.bands[0]
        band.filterType = .lowShelf
        band.frequency = 120
        band.bandwidth = 1.0
        band.gain = 0
        band.bypass = false

        engine.attach(player)
        engine.attach(eq)

        engine.connect(player, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)

        engine.mainMixerNode.outputVolume = 0.5

        do {
            try engine.start()
        } catch {
            print("Audio engine start failed:", error)
        }
    }

    // MARK: - Public

    func load(url: URL) {
        stop()

        stopSecurityScope()
        startSecurityScope(url)

        loadedFileName = url.lastPathComponent

        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            isLoaded = true
            scheduleAndPlay()
        } catch {
            print("AVAudioFile failed to open:", error)
            audioFile = nil
            isLoaded = false
            loadedFileName = "None"
        }
    }

    func play() {
        guard isLoaded else { return }
        ensureEngineRunning()
        if !player.isPlaying { player.play() }
        isPlaying = true
    }

    func pause() {
        if player.isPlaying { player.pause() }
        isPlaying = false
    }

    func stop() {
        if player.isPlaying { player.stop() }
        isPlaying = false
        audioFile = nil
        isLoaded = false
    }

    func setVolume(_ v: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1, v))
    }

    func setBassGainDb(_ bassGainDb: Float) {
        eq.bands[0].gain = max(-24, min(24, bassGainDb))
    }

    // MARK: - Internals

    private func scheduleAndPlay() {
        guard let file = audioFile else { return }

        player.stop()

        // Schedule whole file, then loop
        player.scheduleFile(file, at: nil) { [weak self] in
            guard let self else { return }
            guard self.loopEnabled else { return }
            DispatchQueue.main.async {
                self.scheduleAndPlay()
            }
        }

        ensureEngineRunning()

        if !player.isPlaying {
            player.play()
        }

        isPlaying = true
        print("Playing:", loadedFileName)
    }

    private func ensureEngineRunning() {
        if !engine.isRunning {
            do { try engine.start() }
            catch { print("Engine start error:", error) }
        }
    }

    // MARK: - Security Scoped

    private func startSecurityScope(_ url: URL) {
        // Only matters in sandbox. If not sandboxed, harmless.
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
            print("✅ Security-scoped access granted")
        } else {
            scopedURL = nil
            print("⚠️ Could not start security-scoped access (may still work if not sandboxed)")
        }
    }

    private func stopSecurityScope() {
        if let u = scopedURL {
            u.stopAccessingSecurityScopedResource()
            scopedURL = nil
            print("🛑 Security-scoped access stopped")
        }
    }
}
