import Foundation

struct WaterFrame: Equatable {
    var level = 0.0
    var phase = 0.0
    var depths = Array(repeating: 0.0, count: WaterFluid.cellCount)
    var velocities = Array(repeating: 0.0, count: WaterFluid.cellCount)
    var foam = Array(repeating: 0.0, count: WaterFluid.cellCount)
}

struct WaterForcing {
    var gravityX = 0.0
    var gravityDown = 1.0
    var accelerationX = 0.0
    var accelerationDown = 0.0
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

    func projected(for orientation: WaterScreenOrientation) -> WaterForcing {
        guard gravityX.isFinite, gravityY.isFinite, accelerationX.isFinite, accelerationY.isFinite else {
            return WaterForcing()
        }
        let gravity = orientation.project(x: gravityX, y: gravityY)
        let force = orientation.project(x: accelerationX, y: accelerationY)
        // Feed forces into the fluid. There is no global surface angle or pivot.
        return WaterForcing(gravityX: gravity.x, gravityDown: gravity.y,
                            accelerationX: force.x, accelerationDown: force.y)
    }
}

enum WaterPlayback {
    static func framesPerSecond(active: Bool, reduceMotion: Bool, lowPower: Bool,
                                thermallyLimited: Bool, critical: Bool) -> Int {
        guard active, !reduceMotion, !critical else { return 0 }
        return lowPower || thermallyLimited ? 15 : 30
    }
}

// A conservative 1D shallow-water cross-section, not a rotated plane.
// Each cell carries depth h and momentum hu. Rusanov fluxes move volume between
// adjacent cells; reflecting walls send travelling crests back through the tank.
// Equations/reference: clawpack.org/riemann_book/html/Shallow_water.html
struct WaterFluid {
    static let cellCount = 64
    private(set) var height = 2.15
    private var fill = 0.0
    private var h = Array(repeating: 0.0, count: WaterFluid.cellCount)
    private var q = Array(repeating: 0.0, count: WaterFluid.cellCount)
    private(set) var foam = Array(repeating: 0.0, count: WaterFluid.cellCount)

    var depths: [Double] { h.map { $0 / height } }
    var velocities: [Double] { zip(h, q).map { $0.0 > 0.00001 ? $0.1 / $0.0 : 0 } }

    mutating func setAspectRatio(_ widthOverHeight: Double) {
        guard widthOverHeight.isFinite, widthOverHeight > 0 else { return }
        let next = min(3.5, max(0.5, 1 / widthOverHeight))
        let scale = next / height
        h = h.map { $0 * scale }
        q = q.map { $0 * scale }
        height = next
    }

    mutating func reset(fill value: Double) {
        fill = min(1, max(0, value.isFinite ? value : 0))
        h = Array(repeating: fill * height, count: Self.cellCount)
        q = Array(repeating: 0, count: Self.cellCount)
        foam = Array(repeating: 0, count: Self.cellCount)
    }

    mutating func setFill(_ value: Double) {
        fill = min(1, max(0, value.isFinite ? value : 0))
        if fill <= 0 || fill >= 1 { reset(fill: fill) } else { conserveVolume() }
    }

    // A localized, zero-volume disturbance, used for pouring and vertical jolts.
    mutating func disturb(at position: Double, amount: Double) {
        guard fill > 0, fill < 1, amount.isFinite, position.isFinite else { return }
        let center = min(1, max(0, position))
        let amplitude = min(0.08, max(-0.08, amount)) * height
        let bump = (0..<Self.cellCount).map { index -> Double in
            let distance = (Double(index) + 0.5) / Double(Self.cellCount) - center
            return exp(-distance * distance / 0.008)
        }
        let mean = bump.reduce(0, +) / Double(Self.cellCount)
        for index in h.indices { h[index] += amplitude * (bump[index] - mean) }
        conserveVolume()
    }

    mutating func advance(dt: Double, forcing: WaterForcing) {
        guard dt.isFinite, dt > 0, fill > 0, fill < 1 else { return }
        func finite(_ value: Double, fallback: Double = 0) -> Double { value.isFinite ? value : fallback }
        let gravity = 0.9 * min(2, max(0.25, abs(finite(forcing.gravityDown, fallback: 1)) - finite(forcing.accelerationDown) * 0.6))
        let force = 0.9 * min(2.4, max(-2.4, finite(forcing.gravityX) - finite(forcing.accelerationX) * 1.35))
        let dx = 1 / Double(Self.cellCount)
        var remaining = min(dt, 0.1)
        while remaining > 0.000000001 {
            var speed = 0.01
            for index in h.indices {
                let velocity = h[index] > 0.00001 ? q[index] / h[index] : 0
                speed = max(speed, abs(velocity) + sqrt(gravity * max(0, h[index])))
            }
            // CFL-limited substeps keep the solver stable across 15/30/60 Hz,
            // quick shakes, shallow water, and delayed display callbacks.
            let step = min(remaining, min(1 / 120.0, 0.42 * dx / (speed + abs(force) / 120)))
            for index in q.indices { q[index] += h[index] * force * step * 0.5 }
            var massFlux = Array(repeating: 0.0, count: Self.cellCount + 1)
            var momentumFlux = massFlux
            for edge in 0...Self.cellCount {
                let left = max(0, edge - 1)
                let right = min(Self.cellCount - 1, edge)
                let leftH = h[left], rightH = h[right]
                let leftQ = edge == 0 ? -q[left] : q[left]
                let rightQ = edge == Self.cellCount ? -q[right] : q[right]
                let leftV = leftH > 0.00001 ? leftQ / leftH : 0
                let rightV = rightH > 0.00001 ? rightQ / rightH : 0
                let signal = max(abs(leftV) + sqrt(gravity * leftH), abs(rightV) + sqrt(gravity * rightH))
                massFlux[edge] = (leftQ + rightQ - signal * (rightH - leftH)) * 0.5
                momentumFlux[edge] = (leftQ * leftV + rightQ * rightV
                    + 0.5 * gravity * (leftH * leftH + rightH * rightH)
                    - signal * (rightQ - leftQ)) * 0.5
            }
            for index in h.indices {
                h[index] -= step / dx * (massFlux[index + 1] - massFlux[index])
                q[index] -= step / dx * (momentumFlux[index + 1] - momentumFlux[index])
                q[index] = (q[index] + max(0, h[index]) * force * step * 0.5) * exp(-0.95 * step)
                if h[index] > height {
                    foam[index] = min(1, foam[index] + (h[index] - height) * 8)
                    q[index] *= 0.35
                }
            }
            conserveVolume()
            remaining -= step
        }
        let velocity = velocities
        for index in foam.indices {
            let left = index == 0 ? -velocity[index] : velocity[index - 1]
            let right = index == Self.cellCount - 1 ? -velocity[index] : velocity[index + 1]
            let compression = max(0, (left - right) / (2 * dx) - 0.4)
            foam[index] = min(1, foam[index] * exp(-2.2 * min(dt, 0.1)) + compression * min(dt, 0.1) * 0.16)
        }
    }

    private mutating func conserveVolume() {
        for index in h.indices { h[index] = min(height, max(0, h[index])) }
        let difference = fill * height * Double(Self.cellCount) - h.reduce(0, +)
        if abs(difference) > 0.000000000001 {
            let room = h.map { difference > 0 ? height - $0 : $0 }
            let total = room.reduce(0, +)
            if total > 0 {
                for index in h.indices { h[index] += difference * room[index] / total }
            }
        }
        for index in q.indices {
            h[index] = min(height, max(0, h[index]))
            q[index] = h[index] < 0.00001 ? 0 : min(2.4 * h[index], max(-2.4 * h[index], q[index]))
        }
    }
}

struct WaterDynamics {
    private(set) var frame = WaterFrame()
    private var targetLevel = 0.0
    private var initialized = false
    private var fillSpring = WaterSpring(response: 1.8, dampingRatio: 1)
    private var fluid = WaterFluid()
    private var previousVerticalAcceleration = 0.0

    mutating func setAspectRatio(_ value: Double) {
        fluid.setAspectRatio(value)
        publish()
    }

    mutating func setProgress(_ value: Double, animated: Bool) {
        let next = min(1, max(0, value.isFinite ? value : 0))
        if !initialized || !animated {
            fillSpring.value = next
            fillSpring.velocity = 0
            fluid.reset(fill: next)
            initialized = true
        } else if next > targetLevel {
            fluid.disturb(at: 0.32, amount: min(0.06, (next - targetLevel) * 0.25))
        }
        targetLevel = next
        publish()
    }

    mutating func settle() {
        fillSpring.value = targetLevel
        fillSpring.velocity = 0
        fluid.reset(fill: targetLevel)
        previousVerticalAcceleration = 0
        frame.phase = 0
        publish()
    }

    mutating func advance(dt: Double, forcing: WaterForcing = WaterForcing()) {
        guard dt.isFinite, dt > 0 else { return }
        let step = min(0.1, dt)
        fillSpring.advance(to: targetLevel, dt: step)
        fluid.setFill(fillSpring.value)
        let vertical = forcing.accelerationDown.isFinite ? forcing.accelerationDown : 0
        let jolt = abs(vertical - previousVerticalAcceleration)
        if jolt > 0.5 {
            fluid.disturb(at: 0.5, amount: min(0.025, jolt * 0.01))
        }
        previousVerticalAcceleration = vertical
        fluid.advance(dt: step, forcing: forcing)
        frame.phase = (frame.phase + step).truncatingRemainder(dividingBy: 20 * .pi)
        publish()
    }

    private mutating func publish() {
        frame.level = min(1, max(0, fillSpring.value))
        frame.depths = fluid.depths
        frame.velocities = fluid.velocities
        frame.foam = fluid.foam
    }
}

// Scalar adaptation of Wave's SpringInterpolatable.swift and Spring.swift.
// Copyright (c) 2022 Janum Trivedi. MIT; see WaterThirdPartyNotices.txt.
// Used only to ease recorded volume changes; never rotates the fluid surface.
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
            let acceleration = -stiffness * (value - target) - damping * velocity
            velocity += acceleration * step
            value += velocity * step
        }
    }
}

struct WaterSurface {
    var depths: [Double]
    var ripple: Double = 0.0018
    var phase: Double = 0

    var fill: Double { depths.isEmpty ? 0 : depths.reduce(0, +) / Double(depths.count) }
    var rippleAmplitude: Double {
        min(ripple, max(0, min(depths.min() ?? 0, 1 - (depths.max() ?? 1)) * 0.25))
    }

    func waterline(at x: Double) -> Double {
        if fill <= 0 { return 2 }
        if fill >= 1 { return -1 }
        let position = min(Double(depths.count - 1), max(0, x * Double(depths.count) - 0.5))
        let left = Int(position)
        let right = min(depths.count - 1, left + 1)
        let depth = depths[left] + (depths[right] - depths[left]) * (position - Double(left))
        // Zero-mean micro-ripples; the large waves come exclusively from the solver.
        return 1 - depth + rippleAmplitude * (cos(4 * .pi * x) * sin(phase * 1.7)
                                             + 0.4 * cos(8 * .pi * x) * sin(phase * 1.1))
    }

    func area(samples: Int = 128) -> Double {
        var sum = 0.0
        for index in 0...samples {
            let depth = min(1, max(0, 1 - waterline(at: Double(index) / Double(samples))))
            sum += depth * ((index == 0 || index == samples) ? 0.5 : 1)
        }
        return sum / Double(samples)
    }
}
