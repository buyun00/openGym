import Combine
import CoreMotion
import OSLog
import UIKit

@MainActor
final class WaterMotion: NSObject, ObservableObject {
    // Publish one coherent snapshot per display frame. GeometryReader and the
    // shader must both receive invalidations even when no sensor is available.
    @Published private(set) var frame = WaterFrame()

    private let motion = CMMotionManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "openGym", category: "WaterMotion")
    private var displayLink: CADisplayLink?
    private var proxy: DisplayLinkProxy?
    private var previousTimestamp: CFTimeInterval = 0
    private var dynamics = WaterDynamics()
    private var sample: WaterMotionSample?
    private var sensorGeneration = 0
    private var framesPerSecond = 30

    func setProgress(_ value: Double) {
        dynamics.setProgress(value, animated: displayLink != nil)
        frame = dynamics.frame
    }

    func setViewport(_ size: CGSize) {
        guard size.height > 0 else { return }
        dynamics.setAspectRatio(Double(size.width / size.height))
        frame = dynamics.frame
    }

    func configure(active: Bool, reduceMotion: Bool) {
        let thermal = ProcessInfo.processInfo.thermalState
        let fps = WaterPlayback.framesPerSecond(active: active, reduceMotion: reduceMotion,
                                                lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                                thermallyLimited: thermal == .serious, critical: thermal == .critical)
        guard fps > 0 else {
            stop()
            dynamics.settle()
            frame = dynamics.frame
            return
        }
        framesPerSecond = fps
        motion.deviceMotionUpdateInterval = 1 / Double(fps)
        motion.accelerometerUpdateInterval = 1 / Double(fps)
        let rate = Float(fps)
        if let displayLink {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
            return
        }

        previousTimestamp = 0
        let proxy = DisplayLinkProxy(owner: self)
        self.proxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        displayLink = link
        link.add(to: .main, forMode: .common)
        logger.info("Water display clock started at \(fps) fps")
        startSensors()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
        sensorGeneration &+= 1
        motion.stopDeviceMotionUpdates()
        motion.stopAccelerometerUpdates()
        sample = nil
        previousTimestamp = 0
    }

    private func startSensors() {
        let generation = sensorGeneration
        guard motion.isDeviceMotionAvailable else {
            startAccelerometer(generation: generation)
            return
        }
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            let next = data.map {
                WaterMotionSample(gravityX: $0.gravity.x, gravityY: $0.gravity.y,
                                  accelerationX: $0.userAcceleration.x, accelerationY: $0.userAcceleration.y)
            }
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.displayLink != nil, self.sensorGeneration == generation else { return }
                if let next {
                    if self.sample == nil { self.logger.info("Water received its first device-motion sample") }
                    self.sample = next
                } else if let message {
                    self.logger.error("Water device-motion error: \(message, privacy: .public)")
                    self.motion.stopDeviceMotionUpdates()
                    self.startAccelerometer(generation: generation)
                }
            }
        }
    }

    private func startAccelerometer(generation: Int) {
        guard generation == sensorGeneration, displayLink != nil else { return }
        guard motion.isAccelerometerAvailable else {
            logger.info("Water has no motion stream; the display clock keeps natural ripples moving")
            return
        }
        guard !motion.isAccelerometerActive else { return }
        // Discard fused-motion callbacks already queued before switching streams.
        sensorGeneration &+= 1
        let fallbackGeneration = sensorGeneration
        sample = nil
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            let x = data?.acceleration.x
            let y = data?.acceleration.y
            let message = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.displayLink != nil, self.sensorGeneration == fallbackGeneration else { return }
                if let x, let y {
                    // Separate slow gravity from the faster shake signal on devices
                    // where fused device motion is unavailable.
                    let gravityX = self.sample.map { $0.gravityX + (x - $0.gravityX) * 0.12 } ?? x
                    let gravityY = self.sample.map { $0.gravityY + (y - $0.gravityY) * 0.12 } ?? y
                    if self.sample == nil { self.logger.info("Water received its first accelerometer sample") }
                    self.sample = WaterMotionSample(gravityX: gravityX, gravityY: gravityY,
                                                    accelerationX: x - gravityX, accelerationY: y - gravityY)
                } else if let message {
                    self.logger.error("Water accelerometer error: \(message, privacy: .public)")
                    self.motion.stopAccelerometerUpdates()
                    self.sample = nil
                }
            }
        }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard let displayLink, displayLink === link else { return }
        if previousTimestamp == 0 { logger.info("Water display clock delivered its first frame") }
        let dt = previousTimestamp == 0 ? 1 / Double(framesPerSecond) : link.timestamp - previousTimestamp
        previousTimestamp = link.timestamp
        let input = sample?.projected(for: screenOrientation) ?? WaterForcing()
        dynamics.advance(dt: dt, forcing: input)
        frame = dynamics.frame
    }

    private var screenOrientation: WaterScreenOrientation {
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation ?? .portrait
        switch orientation {
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
}

@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var owner: WaterMotion?
    init(owner: WaterMotion) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
        if let owner { owner.tick(link) } else { link.invalidate() }
    }
}
