//
//  VisualSceneManager.swift

import Foundation
import Combine
import SceneKit
import QuartzCore

#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

final class VisualSceneManager: ObservableObject {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let root = SCNNode()
    private let orb = SCNNode()
    private let ring = SCNNode()

    init() { setupScene() }

    func apply(signals: ControlSignals, gestureEvents: GestureEvents) {
        let intensity = CGFloat(signals.intensity)
        let openness = CGFloat(signals.openness)

        orb.geometry?.firstMaterial?.emission.intensity = 0.2 + intensity * 1.1
        ring.geometry?.firstMaterial?.emission.intensity = 0.5 + intensity * 0.8

        let scale = 1.0 + openness * 0.25
        ring.scale = SCNVector3(scale, scale, scale)
    }

    private func setupScene() {
        scene.rootNode.addChildNode(root)

        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(cameraNode)

        let orbGeo = SCNSphere(radius: 0.9)
        orbGeo.firstMaterial?.diffuse.contents = PlatformColor(white: 0.10, alpha: 1.0)
        orbGeo.firstMaterial?.emission.contents = PlatformColor(white: 0.95, alpha: 1.0)
        orbGeo.firstMaterial?.emission.intensity = 0.3
        orb.geometry = orbGeo
        root.addChildNode(orb)

        let ringGeo = SCNTorus(ringRadius: 1.4, pipeRadius: 0.06)
        ringGeo.firstMaterial?.diffuse.contents = PlatformColor(white: 0.08, alpha: 1.0)
        ringGeo.firstMaterial?.emission.contents = PlatformColor(white: 0.95, alpha: 1.0)
        ringGeo.firstMaterial?.emission.intensity = 0.6
        ring.geometry = ringGeo
        root.addChildNode(ring)
    }
}
