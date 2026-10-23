import Foundation

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
