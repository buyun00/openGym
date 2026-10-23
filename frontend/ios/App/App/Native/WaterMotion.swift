import CoreMotion
import Observation
import UIKit

@MainActor
@Observable
final class WaterMotion: NSObject {
    private(set) var level = 0.0
    private(set) var tilt = 0.0
    private(set) var swell = 0.0
    private(set) var phase = 0.0
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var proxy: DisplayLinkProxy?
    @ObservationIgnored private var previousTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var targetLevel = 0.0
    @ObservationIgnored private var fillSpring = WaterSpring(response: 1.8, dampingRatio: 1)
    @ObservationIgnored private var tiltSpring = WaterSpring(response: 1.55, dampingRatio: 0.43)
    @ObservationIgnored private var swellSpring = WaterSpring(response: 1.1, dampingRatio: 0.32)
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var initialized = false

    func setProgress(_ value: Double) {
        let next = min(1, max(0, value.isFinite ? value : 0))
        if !initialized || !isRunning {
            fillSpring.value = next
            fillSpring.velocity = 0
            level = next
            initialized = true
        } else if next > targetLevel {
            swellSpring.velocity += min(0.12, (next - targetLevel) * 0.45)
        }
        targetLevel = next
    }

    func configure(active: Bool, reduceMotion: Bool, reduceTransparency: Bool) {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let shouldRun = active && !reduceMotion && !reduceTransparency && !lowPower && ProcessInfo.processInfo.thermalState != .serious && ProcessInfo.processInfo.thermalState != .critical
        guard shouldRun != isRunning else { return }
        stop()
        if shouldRun {
            isRunning = true
            motion.deviceMotionUpdateInterval = 1.0 / 30
            if motion.isDeviceMotionAvailable { motion.startDeviceMotionUpdates() }
            let proxy = DisplayLinkProxy(owner: self)
            self.proxy = proxy
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            fillSpring.value = targetLevel
            fillSpring.velocity = 0
            level = targetLevel
            tiltSpring.value = 0
            tiltSpring.velocity = 0
            swellSpring.value = 0
            swellSpring.velocity = 0
            tilt = 0
            swell = 0
            phase = 0
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
        motion.stopDeviceMotionUpdates()
        previousTimestamp = 0
        isRunning = false
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = previousTimestamp == 0 ? 1.0 / 30 : min(0.1, link.timestamp - previousTimestamp)
        previousTimestamp = link.timestamp
        var slope = 0.0
        var acceleration = 0.0
        if let data = motion.deviceMotion {
            let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation ?? .portrait
            let gravity = screenVector(x: data.gravity.x, y: data.gravity.y, orientation: orientation)
            let force = screenVector(x: data.userAcceleration.x, y: data.userAcceleration.y, orientation: orientation)
            // When lying flat, there is no reliable in-plane gravity. Ease back to a level surface.
            if gravity.y > 0.15 { slope = max(-1.6, min(1.6, -gravity.x / gravity.y)) }
            acceleration = max(-1, min(1, force.x))
        }
        fillSpring.advance(to: targetLevel, dt: dt)
        tiltSpring.advance(to: slope, dt: dt)
        swellSpring.advance(to: -acceleration * 0.035, dt: dt)
        level = min(1, max(0, fillSpring.value))
        tilt = max(-2, min(2, tiltSpring.value))
        swell = max(-0.07, min(0.07, swellSpring.value))
        phase += dt
        // All temporal frequencies in the shader repeat after 20π seconds.
        if phase > 20 * .pi { phase -= 20 * .pi }
    }

    private func screenVector(x: Double, y: Double, orientation: UIInterfaceOrientation) -> (x: Double, y: Double) {
        switch orientation {
        case .landscapeLeft: return (y, x)
        case .landscapeRight: return (-y, -x)
        case .portraitUpsideDown: return (-x, y)
        default: return (x, -y)
        }
    }
}

@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var owner: WaterMotion?
    init(owner: WaterMotion) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}
