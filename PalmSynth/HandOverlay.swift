import SwiftUI

struct HandOverlay: View {
    let hands: [HandPose]
    let trackingOK: Bool

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard !hands.isEmpty else {
                    drawStatus(&context, size: size, text: "NO HAND")
                    return
                }

                for hand in hands {
                    drawHand(&context, size: size, hand: hand)
                }

                drawStatus(&context, size: size, text: trackingOK ? "TRACKING" : "NO HAND")
            }
        }
        .allowsHitTesting(false)
    }

    private func drawHand(_ context: inout GraphicsContext, size: CGSize, hand: HandPose) {
        let points = hand.landmarks
        let pointMap = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0.point) })
        let confMap  = Dictionary(uniqueKeysWithValues: points.map { ($0.id, CGFloat($0.confidence)) })

        func toScreen(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
        }

        let curl = computeCurl(pointMap)

        func bone(_ a: String, _ b: String, baseWidth: CGFloat = 3, depthBoost: CGFloat = 0.0) {
            guard let paN = pointMap[a], let pbN = pointMap[b] else { return }
            let pa = toScreen(paN)
            let pb = toScreen(pbN)

            let ca = confMap[a] ?? 0.0
            let cb = confMap[b] ?? 0.0
            let c = min(ca, cb)
            let opacity = clamp(0.12 + 0.88 * c, 0.0, 1.0)

            let width = baseWidth * (1.0 + 0.65 * depthBoost)

            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)

            context.stroke(path, with: .color(.white.opacity(opacity * 0.22)), lineWidth: width * 3.2)
            context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: width)
        }

        // Palm
        bone("wrist", "indexMCP", baseWidth: 4)
        bone("wrist", "middleMCP", baseWidth: 4)
        bone("wrist", "ringMCP", baseWidth: 4)
        bone("wrist", "littleMCP", baseWidth: 4)

        bone("indexMCP", "middleMCP", baseWidth: 3)
        bone("middleMCP", "ringMCP", baseWidth: 3)
        bone("ringMCP", "littleMCP", baseWidth: 3)

        // Thumb
        bone("thumbCMC", "thumbMP", baseWidth: 3, depthBoost: curl.thumb * 0.4)
        bone("thumbMP", "thumbIP", baseWidth: 3, depthBoost: curl.thumb * 0.6)
        bone("thumbIP", "thumbTip", baseWidth: 3, depthBoost: curl.thumb * 1.0)

        // Index
        bone("indexMCP", "indexPIP", baseWidth: 3, depthBoost: curl.index * 0.3)
        bone("indexPIP", "indexDIP", baseWidth: 3, depthBoost: curl.index * 0.7)
        bone("indexDIP", "indexTip", baseWidth: 3, depthBoost: curl.index * 1.0)

        // Middle
        bone("middleMCP", "middlePIP", baseWidth: 3, depthBoost: curl.middle * 0.3)
        bone("middlePIP", "middleDIP", baseWidth: 3, depthBoost: curl.middle * 0.7)
        bone("middleDIP", "middleTip", baseWidth: 3, depthBoost: curl.middle * 1.0)

        // Ring
        bone("ringMCP", "ringPIP", baseWidth: 3, depthBoost: curl.ring * 0.3)
        bone("ringPIP", "ringDIP", baseWidth: 3, depthBoost: curl.ring * 0.7)
        bone("ringDIP", "ringTip", baseWidth: 3, depthBoost: curl.ring * 1.0)

        // Little
        bone("littleMCP", "littlePIP", baseWidth: 3, depthBoost: curl.little * 0.3)
        bone("littlePIP", "littleDIP", baseWidth: 3, depthBoost: curl.little * 0.7)
        bone("littleDIP", "littleTip", baseWidth: 3, depthBoost: curl.little * 1.0)

        // Dots
        for lm in points {
            let p = toScreen(lm.point)
            let conf = CGFloat(lm.confidence)
            let opacity = clamp(0.10 + 0.90 * conf, 0.0, 1.0)

            let depth = depthForJoint(lm.id, curl: curl)
            let r: CGFloat = 5.5 * (1.0 + 0.75 * depth)

            let rect = CGRect(x: p.x - r/2, y: p.y - r/2, width: r, height: r)

            context.fill(Path(ellipseIn: rect.insetBy(dx: -r*0.7, dy: -r*0.7)),
                         with: .color(.white.opacity(opacity * 0.14)))

            context.fill(Path(ellipseIn: rect),
                         with: .color(.white.opacity(opacity)))
        }
    }

    private func drawStatus(_ context: inout GraphicsContext, size: CGSize, text: String) {
        context.draw(
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white),
            at: CGPoint(x: 70, y: 20)
        )
    }

    private struct CurlPack {
        var thumb: CGFloat
        var index: CGFloat
        var middle: CGFloat
        var ring: CGFloat
        var little: CGFloat
    }

    private func computeCurl(_ m: [String: CGPoint]) -> CurlPack {
        func curlFor(mcp: String, pip: String, tip: String) -> CGFloat {
            guard let a = m[mcp], let b = m[pip], let c = m[tip] else { return 0 }
            let ab = hypot(a.x - b.x, a.y - b.y)
            let bc = hypot(b.x - c.x, b.y - c.y)
            guard ab > 0.0001 else { return 0 }
            let ratio = bc / ab
            let curled = 1.0 - clamp((ratio - 0.2) / 1.2, 0.0, 1.0)
            return clamp(curled, 0.0, 1.0)
        }

        func curlThumb() -> CGFloat {
            guard let mp = m["thumbMP"], let ip = m["thumbIP"], let tip = m["thumbTip"] else { return 0 }
            let ab = hypot(mp.x - ip.x, mp.y - ip.y)
            let bc = hypot(ip.x - tip.x, ip.y - tip.y)
            guard ab > 0.0001 else { return 0 }
            let ratio = bc / ab
            let curled = 1.0 - clamp((ratio - 0.2) / 1.2, 0.0, 1.0)
            return clamp(curled, 0.0, 1.0)
        }

        return CurlPack(
            thumb:  curlThumb(),
            index:  curlFor(mcp: "indexMCP",  pip: "indexPIP",  tip: "indexTip"),
            middle: curlFor(mcp: "middleMCP", pip: "middlePIP", tip: "middleTip"),
            ring:   curlFor(mcp: "ringMCP",   pip: "ringPIP",   tip: "ringTip"),
            little: curlFor(mcp: "littleMCP", pip: "littlePIP", tip: "littleTip")
        )
    }

    private func depthForJoint(_ id: String, curl: CurlPack) -> CGFloat {
        if id.contains("thumb") {
            if id == "thumbTip" { return curl.thumb }
            if id == "thumbIP"  { return curl.thumb * 0.7 }
            return curl.thumb * 0.2
        }
        if id.contains("index") {
            if id == "indexTip" { return curl.index }
            if id == "indexDIP" { return curl.index * 0.7 }
            return curl.index * 0.2
        }
        if id.contains("middle") {
            if id == "middleTip" { return curl.middle }
            if id == "middleDIP" { return curl.middle * 0.7 }
            return curl.middle * 0.2
        }
        if id.contains("ring") {
            if id == "ringTip" { return curl.ring }
            if id == "ringDIP" { return curl.ring * 0.7 }
            return curl.ring * 0.2
        }
        if id.contains("little") {
            if id == "littleTip" { return curl.little }
            if id == "littleDIP" { return curl.little * 0.7 }
            return curl.little * 0.2
        }
        return 0
    }

    private func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(x, lo), hi)
    }
}
