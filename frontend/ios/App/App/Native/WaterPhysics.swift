import Foundation

struct WaterFrame: Equatable {
    var level = 0.0
    var tilt = 0.0
    var swell = 0.0
    var phase = 0.0
}

enum WaterScreenOrientation {
    case portrait, portraitUpsideDown, landscapeLeft, landscapeRight

    func project(x: Double, y: Double) -> (x: Double, y: Double) {
        switch self {
        case .portrait: return (x, -y)
        case .portraitUpsideDown: return (-x, y)
        case .landscapeLeft: return (y, x)
        case .landscapeRight: return (-y, -x)
        }
    }
}

struct WaterMotionSample: Sendable {
    var gravityX: Double
    var gravityY: Double
    var accelerationX: Double
    var accelerationY: Double

    func projected(for orientation: WaterScreenOrientation) -> (slope: Double, acceleration: Double) {
        guard gravityX.isFinite, gravityY.isFinite, accelerationX.isFinite, accelerationY.isFinite else {
            return (0, 0)
        }
        let gravity = orientation.project(x: gravityX, y: gravityY)
        let force = orientation.project(x: accelerationX, y: accelerationY)
        // Fade near a perfectly flat phone, without the old hard y > 0.15 cutoff
        // that discarded sideways tilt when the phone was held at a shallow angle.
        let strength = min(1, hypot(gravity.x, gravity.y) / 0.18)
        let slope = -gravity.x / max(0.18, abs(gravity.y))
        return (max(-1.6, min(1.6, slope)) * strength, max(-1, min(1, force.x)))
    }
}

enum WaterPlayback {
    static func framesPerSecond(active: Bool, reduceMotion: Bool, lowPower: Bool,
                                thermallyLimited: Bool, critical: Bool) -> Int {
        guard active, !reduceMotion, !critical else { return 0 }
        return lowPower || thermallyLimited ? 15 : 30
    }
}

// The display clock advances this state even before a sensor sample arrives.
// Kept independent of UIKit/Core Motion so the real animation math can be tested.
struct WaterDynamics {
    private(set) var frame = WaterFrame()
    private var targetLevel = 0.0
    private var initialized = false
    private var fillSpring = WaterSpring(response: 1.8, dampingRatio: 1)
    private var tiltSpring = WaterSpring(response: 1.55, dampingRatio: 0.43)
    private var swellSpring = WaterSpring(response: 1.1, dampingRatio: 0.32)

    mutating func setProgress(_ value: Double, animated: Bool) {
        let next = min(1, max(0, value.isFinite ? value : 0))
        if !initialized || !animated {
            fillSpring.value = next
            fillSpring.velocity = 0
            frame.level = next
            initialized = true
        } else if next > targetLevel {
            swellSpring.velocity += min(0.12, (next - targetLevel) * 0.45)
        }
        targetLevel = next
    }

    mutating func settle() {
        fillSpring.value = targetLevel
        fillSpring.velocity = 0
        tiltSpring.value = 0
        tiltSpring.velocity = 0
        swellSpring.value = 0
        swellSpring.velocity = 0
        frame = WaterFrame(level: targetLevel)
    }

    mutating func advance(dt: Double, slope: Double = 0, acceleration: Double = 0) {
        guard dt.isFinite, dt > 0 else { return }
        let step = min(0.1, dt)
        fillSpring.advance(to: targetLevel, dt: step)
        tiltSpring.advance(to: slope.isFinite ? slope : 0, dt: step)
        swellSpring.advance(to: acceleration.isFinite ? -acceleration * 0.035 : 0, dt: step)
        frame.level = min(1, max(0, fillSpring.value))
        frame.tilt = max(-2, min(2, tiltSpring.value))
        frame.swell = max(-0.07, min(0.07, swellSpring.value))
        // All temporal frequencies in the shader repeat after 20π seconds.
        frame.phase = (frame.phase + step).truncatingRemainder(dividingBy: 20 * .pi)
    }
}

// Scalar adaptation of Wave's SpringInterpolatable.swift and Spring.swift.
// Copyright (c) 2022 Janum Trivedi. MIT; see WaterThirdPartyNotices.txt.
// Fixed substeps, limits and the fluid surface below are openGym additions.
struct WaterSpring {
    var value: Double = 0
    var velocity: Double = 0
    var response: Double
    var dampingRatio: Double

    mutating func advance(to target: Double, dt: Double) {
        guard dt > 0, dt.isFinite, target.isFinite else { return }
        let count = max(1, Int(ceil(min(dt, 0.1) * 120)))
        let step = min(dt, 0.1) / Double(count)
        let stiffness = pow(2 * Double.pi / response, 2)
        let damping = 4 * Double.pi * dampingRatio / response
        for _ in 0..<count {
            let displacement = value - target
            let springForce = -stiffness * displacement
            let dampingForce = damping * velocity
            let acceleration = springForce - dampingForce
            velocity += acceleration * step
            value += velocity * step
        }
    }
}

struct WaterSurface {
    var fill: Double
    var slope: Double
    var swell: Double
    var ripple: Double
    var phase: Double

    func displacement(at x: Double) -> Double {
        slope * (x - 0.5) + swell * cos(.pi * x) +
        ripple * sin(4 * .pi * x + phase * 1.7) +
        ripple * 0.45 * cos(7 * .pi * x - phase * 1.2)
    }

    func area(base: Double, samples: Int = 128) -> Double {
        var sum = 0.0
        for index in 0...samples {
            let depth = min(1, max(0, 1 - base - displacement(at: Double(index) / Double(samples))))
            sum += depth * ((index == 0 || index == samples) ? 0.5 : 1)
        }
        return sum / Double(samples)
    }

    // Solve the clipped cross-section, including steep tilt and the nearly empty/full cases.
    // Moving the waterline alone would otherwise create or destroy visible water at the edges.
    var base: Double {
        let bound = abs(slope) / 2 + abs(swell) + abs(ripple) * 1.45
        if fill <= 0 { return 2 + bound }
        if fill >= 1 { return -1 - bound }
        var low = -bound
        var high = 1 + bound
        let samples = 128
        let offsets = (0...samples).map { displacement(at: Double($0) / Double(samples)) }
        for _ in 0..<22 {
            let middle = (low + high) / 2
            var area = 0.0
            for index in 0...samples {
                area += min(1, max(0, 1 - middle - offsets[index])) * ((index == 0 || index == samples) ? 0.5 : 1)
            }
            if area / Double(samples) > fill { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }
}
