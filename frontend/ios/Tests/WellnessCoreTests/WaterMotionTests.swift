import XCTest
@testable import WellnessCore

final class WaterMotionTests: XCTestCase {
    func testNaturalRipplesAdvanceWithoutSensorSamples() {
        for fps in [15.0, 30.0, 60.0] {
            var water = WaterDynamics()
            water.setProgress(0.5, animated: false)
            let before = WaterSurface(fill: 0.5, slope: 0, swell: 0, ripple: 0.0025, phase: water.frame.phase)
            for _ in 0..<Int(fps) { water.advance(dt: 1 / fps) }
            let after = WaterSurface(fill: water.frame.level, slope: water.frame.tilt,
                                     swell: water.frame.swell, ripple: 0.0025, phase: water.frame.phase)
            XCTAssertEqual(water.frame.phase, 1, accuracy: 0.000001)
            XCTAssertEqual(water.frame.level, 0.5, accuracy: 0.000001)
            XCTAssertNotEqual(before.displacement(at: 0.3), after.displacement(at: 0.3))
        }
    }

    func testGravityDirectionInEachInterfaceOrientation() {
        // The same physical screen-right tilt in all four screen orientations.
        let readings: [(WaterScreenOrientation, Double, Double)] = [
            (.portrait, 0.4, -0.8), (.portraitUpsideDown, -0.4, 0.8),
            (.landscapeLeft, 0.8, 0.4), (.landscapeRight, -0.8, -0.4)
        ]
        for (orientation, x, y) in readings {
            let sample = WaterMotionSample(gravityX: x, gravityY: y, accelerationX: 0, accelerationY: 0)
            XCTAssertEqual(sample.projected(for: orientation).slope, -0.5, accuracy: 0.000001)
        }
        let opposite = WaterMotionSample(gravityX: -0.4, gravityY: -0.8, accelerationX: 0, accelerationY: 0)
        XCTAssertEqual(opposite.projected(for: .portrait).slope, 0.5, accuracy: 0.000001)
    }

    func testShallowAngleDoesNotDiscardSidewaysTilt() {
        let tilted = WaterMotionSample(gravityX: 0.3, gravityY: -0.05, accelerationX: 0, accelerationY: 0)
        XCTAssertLessThan(tilted.projected(for: .portrait).slope, -1)
        let flat = WaterMotionSample(gravityX: 0, gravityY: 0, accelerationX: 0, accelerationY: 0)
        XCTAssertEqual(flat.projected(for: .portrait).slope, 0)
        let noisy = WaterMotionSample(gravityX: 0.001, gravityY: -0.001, accelerationX: 0, accelerationY: 0)
        XCTAssertLessThan(abs(noisy.projected(for: .portrait).slope), 0.001)
    }

    func testTiltAndShakeRespondThenSettle() {
        var water = WaterDynamics()
        water.setProgress(0.5, animated: false)
        for _ in 0..<30 { water.advance(dt: 1 / 30.0, slope: 0.6, acceleration: 0.8) }
        XCTAssertGreaterThan(water.frame.tilt, 0.1)
        XCTAssertLessThan(water.frame.swell, -0.001)
        let surface = WaterSurface(fill: water.frame.level, slope: water.frame.tilt,
                                   swell: water.frame.swell, ripple: 0.0025, phase: water.frame.phase)
        XCTAssertEqual(surface.area(base: surface.base, samples: 8192), 0.5, accuracy: 0.0002)
        for _ in 0..<300 { water.advance(dt: 1 / 30.0) }
        XCTAssertEqual(water.frame.tilt, 0, accuracy: 0.00001)
        XCTAssertEqual(water.frame.swell, 0, accuracy: 0.00001)
    }

    func testAddingWaterAnimatesLevelAndCreatesSwell() {
        var water = WaterDynamics()
        water.setProgress(0.25, animated: false)
        water.setProgress(0.75, animated: true)
        water.advance(dt: 1 / 30.0)
        XCTAssertGreaterThan(water.frame.level, 0.25)
        XCTAssertLessThan(water.frame.level, 0.75)
        XCTAssertGreaterThan(water.frame.swell, 0)
        for _ in 0..<300 { water.advance(dt: 1 / 30.0) }
        XCTAssertEqual(water.frame.level, 0.75, accuracy: 0.00001)
    }

    func testPausePolicyAndResumeKeepAnimationAvailable() {
        func fps(active: Bool = true, reduceMotion: Bool = false, lowPower: Bool = false,
                 hot: Bool = false, critical: Bool = false) -> Int {
            WaterPlayback.framesPerSecond(active: active, reduceMotion: reduceMotion, lowPower: lowPower,
                                           thermallyLimited: hot, critical: critical)
        }
        XCTAssertEqual(fps(), 30)
        XCTAssertEqual(fps(lowPower: true), 15)
        XCTAssertEqual(fps(hot: true), 15)
        XCTAssertEqual(fps(active: false), 0)
        XCTAssertEqual(fps(reduceMotion: true), 0)
        XCTAssertEqual(fps(critical: true), 0)
        var water = WaterDynamics()
        water.setProgress(0.5, animated: false)
        water.advance(dt: 1 / 30.0, slope: 0.6)
        water.settle()
        XCTAssertEqual(water.frame, WaterFrame(level: 0.5))
        water.advance(dt: 1 / 30.0, slope: -0.6)
        XCTAssertGreaterThan(water.frame.phase, 0)
        XCTAssertLessThan(water.frame.tilt, 0)
    }

    func testLongResumeDeltaAndInvalidInputsRemainFinite() {
        var water = WaterDynamics()
        water.setProgress(0.5, animated: false)
        water.advance(dt: 60, slope: 0.6)
        XCTAssertEqual(water.frame.phase, 0.1, accuracy: 0.000001)
        let before = water.frame
        water.advance(dt: .nan)
        water.advance(dt: -1)
        XCTAssertEqual(water.frame, before)
        water.advance(dt: 1 / 30.0, slope: .nan, acceleration: .infinity)
        XCTAssertTrue(water.frame.tilt.isFinite)
        XCTAssertTrue(water.frame.swell.isFinite)
    }
}
