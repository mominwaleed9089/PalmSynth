//
//  ControlSignals.swift
//  PalmSynth
//
//  Created by Mo on 15/02/2026.
//


import Foundation
import CoreGraphics

struct ControlSignals {
    /// 0...1
    var intensity: Float = 0.0
    /// 0...1
    var openness: Float = 0.0
    var isPinching: Bool = false
}

struct GestureEvents {
    var didTriggerIntro: Bool = false
}

final class Smoother {
    private var value: Float = 0
    func step(_ x: Float, alpha: Float = 0.15) -> Float {
        value = value * (1 - alpha) + x * alpha
        return value
    }
}

extension Float {
    func clamped(_ lo: Float, _ hi: Float) -> Float {
        Swift.min(Swift.max(self, lo), hi)
    }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, lo), hi)
    }
}
