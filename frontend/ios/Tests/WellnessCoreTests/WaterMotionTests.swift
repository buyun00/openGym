import XCTest
@testable import WellnessCore

final class WaterMotionTests: XCTestCase {
    func testNaturalRipplesAdvanceWithoutSensorSamples() {
        for fps in [15.0, 30.0, 60.0] {
            var water = WaterDynamics()
            water.setProgress(0.5, animated: false)
            let before = WaterSurface(depths: water.frame.depths, phase: water.frame.phase)
            for _ in 0..<Int(fps) { water.advance(dt: 1 / fps) }
            let after = WaterSurface(depths: water.frame.depths, phase: water.frame.phase)
            XCTAssertEqual(water.frame.phase, 1, accuracy: 0.000001)
            XCTAssertEqual(water.frame.level, 0.5, accuracy: 0.000001)
            XCTAssertNotEqual(before.waterline(at: 0.3), after.waterline(at: 0.3))
        }
    }

    func testGravityDirectionInEachInterfaceOrientation() {
        let readings: [(WaterScreenOrientation, Double, Double)] = [
            (.portrait, 0.4, -0.8), (.portraitUpsideDown, -0.4, 0.8),
            (.landscapeLeft, 0.8, 0.4), (.landscapeRight, -0.8, -0.4)
        ]
        for (orientation, x, y) in readings {
            let sample = WaterMotionSample(gravityX: x, gravityY: y, accelerationX: 0, accelerationY: 0)
            let force = sample.projected(for: orientation)
            XCTAssertEqual(force.gravityX, 0.4, accuracy: 0.000001)
            XCTAssertEqual(force.gravityDown, 0.8, accuracy: 0.000001)
        }
        let shallow = WaterMotionSample(gravityX: 0.3, gravityY: -0.05, accelerationX: 0, accelerationY: 0)
        XCTAssertEqual(shallow.projected(for: .portrait).gravityX, 0.3)
    }

    func testImpulseStartsAtWallsInsteadOfPivotingTheWholeSurface() {
        var fluid = WaterFluid()
        fluid.reset(fill: 0.5)
        fluid.advance(dt: 1 / 30.0, forcing: WaterForcing(accelerationX: -1))
        XCTAssertGreaterThan(fluid.depths.last!, 0.5)
        XCTAssertLessThan(fluid.depths.first!, 0.5)
        XCTAssertEqual(fluid.depths[32], 0.5, accuracy: 0.000001)
        for _ in 0..<3 { fluid.advance(dt: 1 / 30.0, forcing: WaterForcing(accelerationX: -1)) }
        let depths = fluid.depths
        let deviation = depths.enumerated().map { index, depth in
            abs(depth - (depths[0] + (depths.last! - depths[0]) * Double(index) / Double(depths.count - 1)))
        }.max()!
        XCTAssertGreaterThan(deviation, 0.01, "A travelling wave must not be a single tilted line")
    }

    func testLocalizedCrestTravelsAndReflectsFromWall() {
        var fluid = WaterFluid()
        fluid.reset(fill: 0.5)
        fluid.disturb(at: 0.24, amount: 0.06)
        let initial = fluid.depths
        for _ in 0..<21 { fluid.advance(dt: 1 / 30.0, forcing: WaterForcing()) }
        let atWall = fluid.depths
        XCTAssertGreaterThan(atWall.last!, 0.51)
        XCTAssertGreaterThan(atWall.last!, initial.last!)
        for _ in 0..<9 { fluid.advance(dt: 1 / 30.0, forcing: WaterForcing()) }
        let returning = fluid.depths
        let peak = returning.indices.max { returning[$0] < returning[$1] }!
        XCTAssertLessThan(peak, WaterFluid.cellCount - 5, "The wall crest should travel back inside")
        XCTAssertGreaterThan(returning[peak], returning.last!)
    }

    func testWavesKeepMovingAfterReleaseThenDamp() {
        var fluid = WaterFluid()
        fluid.reset(fill: 0.5)
        for _ in 0..<4 { fluid.advance(dt: 1 / 30.0, forcing: WaterForcing(accelerationX: -1)) }
        let released = fluid.depths
        for _ in 0..<20 { fluid.advance(dt: 1 / 30.0, forcing: WaterForcing()) }
        XCTAssertGreaterThan(zip(released, fluid.depths).map { abs($0.0 - $0.1) }.max()!, 0.01)
        for _ in 0..<300 { fluid.advance(dt: 1 / 30.0, forcing: WaterForcing()) }
        XCTAssertLessThan(fluid.depths.map { abs($0 - 0.5) }.max()!, 0.001)
    }

    func testDisplayFrameRateDoesNotChangeWaveMotion() {
        var outcomes: [[Double]] = []
        for fps in [15, 30, 60] {
            var fluid = WaterFluid()
            fluid.reset(fill: 0.5)
            for _ in 0..<fps { fluid.advance(dt: 1 / Double(fps), forcing: WaterForcing(accelerationX: -0.6)) }
            outcomes.append(fluid.depths)
        }
        XCTAssertLessThan(zip(outcomes.first!, outcomes.last!).map { abs($0.0 - $0.1) }.max()!, 0.004)
    }

    func testAddingWaterAnimatesLevelAndCreatesLocalizedWaves() {
        var water = WaterDynamics()
        water.setProgress(0.25, animated: false)
        water.setProgress(0.75, animated: true)
        water.advance(dt: 1 / 30.0)
        XCTAssertGreaterThan(water.frame.level, 0.25)
        XCTAssertLessThan(water.frame.level, 0.75)
        XCTAssertGreaterThan(water.frame.depths.max()! - water.frame.depths.min()!, 0.005)
        for _ in 0..<300 { water.advance(dt: 1 / 30.0) }
        XCTAssertEqual(water.frame.level, 0.75, accuracy: 0.00001)
        XCTAssertEqual(water.frame.depths.reduce(0, +) / Double(WaterFluid.cellCount), water.frame.level, accuracy: 0.0000001)
    }

    func testViewportChangePreservesWaterVolumeAndProfile() {
        var water = WaterDynamics()
        water.setProgress(0.5, animated: false)
        for _ in 0..<10 { water.advance(dt: 1 / 30.0, forcing: WaterForcing(gravityX: 0.4)) }
        let before = water.frame.depths
        water.setAspectRatio(2)
        for (left, right) in zip(before, water.frame.depths) { XCTAssertEqual(left, right, accuracy: 0.0000001) }
    }

    func testVerticalJoltMakesLocalWavesWithoutChangingVolume() {
        var water = WaterDynamics()
        water.setProgress(0.5, animated: false)
        water.advance(dt: 1 / 30.0, forcing: WaterForcing(accelerationDown: -1))
        XCTAssertGreaterThan(water.frame.depths.max()! - water.frame.depths.min()!, 0.001)
        XCTAssertEqual(water.frame.depths.reduce(0, +) / Double(WaterFluid.cellCount), 0.5, accuracy: 0.0000001)
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
        water.advance(dt: 1 / 30.0, forcing: WaterForcing(gravityX: 0.6))
        water.settle()
        XCTAssertTrue(water.frame.depths.allSatisfy { $0 == 0.5 })
        XCTAssertTrue(water.frame.velocities.allSatisfy { $0 == 0 })
        water.advance(dt: 1 / 30.0, forcing: WaterForcing(gravityX: -0.6))
        XCTAssertGreaterThan(water.frame.phase, 0)
        XCTAssertGreaterThan(water.frame.depths.first!, water.frame.depths.last!)
    }

    func testLongResumeDeltaAndInvalidInputsRemainFinite() {
        var water = WaterDynamics()
        water.setProgress(0.5, animated: false)
        water.advance(dt: 60, forcing: WaterForcing(gravityX: 0.6))
        XCTAssertEqual(water.frame.phase, 0.1, accuracy: 0.000001)
        let before = water.frame
        water.advance(dt: .nan)
        water.advance(dt: -1)
        XCTAssertEqual(water.frame, before)
        water.advance(dt: 1 / 30.0, forcing: WaterForcing(gravityX: .nan, accelerationX: .infinity))
        XCTAssertTrue(water.frame.depths.allSatisfy { $0.isFinite })
        XCTAssertTrue(water.frame.velocities.allSatisfy { $0.isFinite })
    }
}
