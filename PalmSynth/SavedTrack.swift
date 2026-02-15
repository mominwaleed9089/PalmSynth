import Foundation
import Combine
import UniformTypeIdentifiers

struct SavedTrack: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var localFilename: String
}

// SynthEngine (stub for macOS demo)
// This compiles on macOS and iOS but does NOT try to manage AVAudioSession on macOS.
final class SynthEngine: ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var hasTrack: Bool = false
    @Published var showPicker: Bool = false
    @Published private(set) var trackName: String = ""

    @Published private(set) var library: [SavedTrack] = []
    @Published private(set) var activeTrackID: UUID? = nil

    let allowedTypes: [UTType] = [.mp3, .mpeg4Audio, .wav, .aiff, .audio]

    func loadPickedFile(url: URL) {
        // For now: just store the display name and mark as “has track”
        trackName = url.lastPathComponent
        hasTrack = true
    }

    func play() { isPlaying = true }
    func stop() { isPlaying = false }
    func togglePlay() { isPlaying ? stop() : play() }
}
