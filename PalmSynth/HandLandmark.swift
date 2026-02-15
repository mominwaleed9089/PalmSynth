import Foundation
import Combine
import Vision
import CoreGraphics
import ImageIO

// MARK: - Models

struct HandLandmark: Identifiable, Hashable {
    let id: String
    let point: CGPoint          // normalized 0...1
    let confidence: Float       // 0...1
}

struct HandPose: Identifiable {
    let id: Int
    let landmarks: [HandLandmark]
    let confidenceAvg: CGFloat
    let pinchDistancePx: CGFloat
    let spanDistancePx: CGFloat
}

// MARK: - Tracker

final class HandTracker: ObservableObject {

    @Published private(set) var hands: [HandPose] = []
    @Published private(set) var trackingOK: Bool = false

    // DEBUG thing
    @Published private(set) var visionRuns: Int = 0
    @Published private(set) var visionResults: Int = 0
    @Published private(set) var lastVisionError: String = ""

    private let request = VNDetectHumanHandPoseRequest()

    // Smoothing buffers per track
    private var smoothedByTrack: [[String: CGPoint]] = [[:], [:]]

    // Last-good cache per track (for stabilizing problematic joints)
    private var lastGoodByTrack: [[String: CGPoint]] = [[:], [:]]

    // Track state
    private struct TrackState {
        var isActive: Bool = false
        var lastWrist: CGPoint = .zero
        var lastPalm: CGPoint = .zero
        var lastDir: CGPoint = .zero
        var lastSeenTime: CFTimeInterval = 0
    }
    private var tracks: [TrackState] = [TrackState(), TrackState()]

    // Timeouts + matching
    private let trackTimeout: CFTimeInterval = 0.8
    private let maxMatchDistance: CGFloat = 0.30

    // Stabilizer tuning (middle finger)
    private let holdConfidence: Float = 0.22       // below this, hold last good
    private let clampMaxStep: CGFloat = 0.060      // max normalized move/frame for jittery joints

    init() {
        request.maximumHandCount = 2
    }

    func process(pixelBuffer: CVPixelBuffer,
                 orientation: CGImagePropertyOrientation,
                 viewSize: CGSize) {

        DispatchQueue.main.async { self.visionRuns += 1 }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])

        let now = CFAbsoluteTimeGetCurrent()

        do {
            try handler.perform([request])

            let observations = request.results ?? []
            DispatchQueue.main.async { self.visionResults = observations.count }

            // Expire old tracks
            for i in 0..<tracks.count where tracks[i].isActive {
                if now - tracks[i].lastSeenTime > trackTimeout {
                    tracks[i].isActive = false
                    smoothedByTrack[i].removeAll()
                    lastGoodByTrack[i].removeAll()
                }
            }

            guard !observations.isEmpty else {
                DispatchQueue.main.async {
                    self.hands = []
                    self.trackingOK = false
                }
                return
            }

            let detections: [Detection] = observations.prefix(2).compactMap { obs in
                guard let sig = signature(for: obs) else { return nil }
                return Detection(obs: obs, wrist: sig.wrist, palm: sig.palm, dir: sig.dir)
            }

            guard !detections.isEmpty else {
                DispatchQueue.main.async {
                    self.hands = []
                    self.trackingOK = false
                }
                return
            }

            let assignments = assign(detections: detections)

            var built: [HandPose] = []

            for (trackId, det) in assignments {
                // Update track state
                tracks[trackId].isActive = true
                tracks[trackId].lastWrist = det.wrist
                tracks[trackId].lastPalm = det.palm
                tracks[trackId].lastDir = det.dir
                tracks[trackId].lastSeenTime = now

                let raw = buildRawPoints(from: det.obs)
                let smoothPts = smooth(raw, trackId: trackId)
                let stabilized = stabilizeMiddleFinger(smoothPts, trackId: trackId)

                let avgConf: CGFloat = {
                    let vals = stabilized.map { CGFloat($0.confidence) }
                    guard !vals.isEmpty else { return 0 }
                    return vals.reduce(0, +) / CGFloat(vals.count)
                }()

                let (pinch, span) = computeDistances(points: stabilized, viewSize: viewSize)

                built.append(
                    HandPose(
                        id: trackId,
                        landmarks: stabilized,
                        confidenceAvg: avgConf,
                        pinchDistancePx: pinch,
                        spanDistancePx: span
                    )
                )
            }

            built.sort { $0.id < $1.id }

            DispatchQueue.main.async {
                self.hands = built
                self.trackingOK = !built.isEmpty
            }

        } catch {
            DispatchQueue.main.async {
                self.lastVisionError = "\(error)"
                self.hands = []
                self.trackingOK = false
            }
        }
    }

    // MARK: - Detection Signature

    private struct Detection {
        let obs: VNHumanHandPoseObservation
        let wrist: CGPoint
        let palm: CGPoint
        let dir: CGPoint
    }

    private func signature(for obs: VNHumanHandPoseObservation)
    -> (wrist: CGPoint, palm: CGPoint, dir: CGPoint)? {

        guard let wristPt = try? obs.recognizedPoint(.wrist),
              wristPt.confidence >= 0.10 else { return nil }

        // Palm proxy: average MCPs
        let mcpJoints: [VNHumanHandPoseObservation.JointName] =
            [.indexMCP, .middleMCP, .ringMCP, .littleMCP]

        var sum = CGPoint.zero
        var count: CGFloat = 0

        for j in mcpJoints {
            if let p = try? obs.recognizedPoint(j), p.confidence >= 0.10 {
                sum.x += p.location.x
                sum.y += p.location.y
                count += 1
            }
        }

        let palm = (count > 0)
            ? CGPoint(x: sum.x / count, y: sum.y / count)
            : wristPt.location

        // Direction cue: indexMCP - wrist
        var dir = CGPoint.zero
        if let index = try? obs.recognizedPoint(.indexMCP),
           index.confidence >= 0.10 {
            dir = CGPoint(
                x: index.location.x - wristPt.location.x,
                y: index.location.y - wristPt.location.y
            )
        }

        return (wristPt.location, palm, dir)
    }

    // MARK: - Assignment (2-hand “mini Hungarian”)

    private func assign(detections dets: [Detection]) -> [(Int, Detection)] {
        if dets.count == 1 {
            let best = bestTrack(for: dets[0])
            return [(best, dets[0])]
        }

        let d0 = dets[0]
        let d1 = dets[1]

        let costA = matchCost(trackId: 0, det: d0) + matchCost(trackId: 1, det: d1)
        let costB = matchCost(trackId: 1, det: d0) + matchCost(trackId: 0, det: d1)

        let pairs: [(Int, Detection)] = (costA <= costB) ? [(0, d0), (1, d1)] : [(1, d0), (0, d1)]

        // If a pairing is insanely far, fall back to nearest
        return pairs.map { (tid, det) in
            let c = matchCost(trackId: tid, det: det)
            if c > maxMatchDistance * 3 {
                return (bestTrack(for: det), det)
            }
            return (tid, det)
        }
    }

    private func bestTrack(for det: Detection) -> Int {
        let c0 = matchCost(trackId: 0, det: det)
        let c1 = matchCost(trackId: 1, det: det)

        if tracks[0].isActive && tracks[1].isActive {
            return c0 <= c1 ? 0 : 1
        }
        if tracks[0].isActive && !tracks[1].isActive { return (c0 <= maxMatchDistance) ? 0 : 1 }
        if tracks[1].isActive && !tracks[0].isActive { return (c1 <= maxMatchDistance) ? 1 : 0 }

        return 0
    }

    private func matchCost(trackId: Int, det: Detection) -> CGFloat {
        guard tracks[trackId].isActive else { return 0.05 }

        let w = distance(tracks[trackId].lastWrist, det.wrist)
        let p = distance(tracks[trackId].lastPalm, det.palm)
        let d = distance(tracks[trackId].lastDir, det.dir)

        return (0.55 * w) + (0.30 * p) + (0.15 * d)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    // MARK: - Landmarks

    private func buildRawPoints(from obs: VNHumanHandPoseObservation) -> [HandLandmark] {
        func lm(_ joint: VNHumanHandPoseObservation.JointName,
                _ id: String,
                minConf: Float = 0.12) -> HandLandmark? {
            guard let p = try? obs.recognizedPoint(joint),
                  p.confidence >= minConf else { return nil }
            return HandLandmark(id: id, point: p.location, confidence: p.confidence)
        }

        let items: [HandLandmark?] = [
            lm(.wrist, "wrist"),

            lm(.thumbCMC, "thumbCMC"), lm(.thumbMP, "thumbMP"), lm(.thumbIP, "thumbIP"), lm(.thumbTip, "thumbTip"),

            lm(.indexMCP, "indexMCP"), lm(.indexPIP, "indexPIP"), lm(.indexDIP, "indexDIP"), lm(.indexTip, "indexTip"),

            lm(.middleMCP, "middleMCP"), lm(.middlePIP, "middlePIP"), lm(.middleDIP, "middleDIP"), lm(.middleTip, "middleTip"),

            lm(.ringMCP, "ringMCP"), lm(.ringPIP, "ringPIP"), lm(.ringDIP, "ringDIP"), lm(.ringTip, "ringTip"),

            lm(.littleMCP, "littleMCP"), lm(.littlePIP, "littlePIP"), lm(.littleDIP, "littleDIP"), lm(.littleTip, "littleTip"),
        ]

        return items.compactMap { $0 }
    }

    // MARK: - Adaptive Smoothing (confidence-gated)

    private func smooth(_ points: [HandLandmark], trackId: Int) -> [HandLandmark] {
        points.map { lm in
            let prev = smoothedByTrack[trackId][lm.id]

            let conf = CGFloat(lm.confidence)
            let a = clamp(0.08 + 0.30 * conf, 0.08, 0.28)  // low conf => smoother

            let p: CGPoint
            if let prev {
                p = CGPoint(
                    x: prev.x + a * (lm.point.x - prev.x),
                    y: prev.y + a * (lm.point.y - prev.y)
                )
            } else {
                p = lm.point
            }

            smoothedByTrack[trackId][lm.id] = p
            return HandLandmark(id: lm.id, point: p, confidence: lm.confidence)
        }
    }

    // MARK: - Middle Finger Stabilizer (right-hand issues)

    private func stabilizeMiddleFinger(_ pts: [HandLandmark], trackId: Int) -> [HandLandmark] {
        var out = pts
        var map = Dictionary(uniqueKeysWithValues: out.map { ($0.id, $0) })

        func get(_ id: String) -> HandLandmark? { map[id] }
        func set(_ lm: HandLandmark) { map[lm.id] = lm }

        let mcpID = "middleMCP"
        let pipID = "middlePIP"
        let dipID = "middleDIP"
        let tipID = "middleTip"

        guard let mcp = get(mcpID), let tip = get(tipID) else { return out }

        // 1) HOLD last good if confidence drops
        for id in [pipID, dipID] {
            if let lm = get(id),
               lm.confidence < holdConfidence,
               let last = lastGoodByTrack[trackId][id] {
                set(HandLandmark(id: id, point: last, confidence: lm.confidence))
            }
        }

        // Refresh after holds
        let pip = get(pipID)
        let dip = get(dipID)

        // 2) INTERPOLATE if missing/weak
        if pip == nil || (pip!.confidence < holdConfidence) {
            let p = lerp(mcp.point, tip.point, 0.35)
            set(HandLandmark(id: pipID, point: p, confidence: pip?.confidence ?? 0))
        }
        if dip == nil || (dip!.confidence < holdConfidence) {
            let p = lerp(mcp.point, tip.point, 0.70)
            set(HandLandmark(id: dipID, point: p, confidence: dip?.confidence ?? 0))
        }

        // 3) CLAMP sudden spikes
        for id in [pipID, dipID] {
            guard let lm = get(id) else { continue }
            if let last = lastGoodByTrack[trackId][id] {
                let dx = lm.point.x - last.x
                let dy = lm.point.y - last.y
                let dist = hypot(dx, dy)
                if dist > clampMaxStep {
                    let s = clampMaxStep / dist
                    let clamped = CGPoint(x: last.x + dx * s, y: last.y + dy * s)
                    set(HandLandmark(id: id, point: clamped, confidence: lm.confidence))
                }
            }
        }

        // Update last-good cache (only when reasonably confident)
        for id in [pipID, dipID, tipID] {
            if let lm = get(id), lm.confidence >= holdConfidence {
                lastGoodByTrack[trackId][id] = lm.point
            }
        }

        // Preserve original order
        out = out.map { lm in map[lm.id] ?? lm }
        return out
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(x, lo), hi)
    }

    // MARK: - Distances (optional)

    private func computeDistances(points: [HandLandmark], viewSize: CGSize) -> (CGFloat, CGFloat) {
        let map = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0.point) })

        func toScreen(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * viewSize.width, y: (1 - p.y) * viewSize.height)
        }

        var pinch: CGFloat = 0
        if let t = map["thumbTip"], let i = map["indexTip"] {
            let a = toScreen(t), b = toScreen(i)
            pinch = hypot(a.x - b.x, a.y - b.y)
        }

        var span: CGFloat = 0
        if let i = map["indexTip"], let l = map["littleTip"] {
            let a = toScreen(i), b = toScreen(l)
            span = hypot(a.x - b.x, a.y - b.y)
        }

        return (pinch, span)
    }
}
