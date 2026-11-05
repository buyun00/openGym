import XCTest

final class WidgetNavigationUITests: XCTestCase {
    @MainActor
    func testWaterWidgetColdLaunch() {
        let app = XCUIApplication(bundleIdentifier: "org.lin0.lingym")
        app.launch()
        app.terminate()
        XCUIDevice.shared.system.open(URL(string: "lingym://water")!)
        XCTAssertTrue(app.navigationBars["喝水"].waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "water-widget-cold-launch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testWaterWidgetResumesAndSupportsExistingWidgets() {
        let app = XCUIApplication(bundleIdentifier: "org.lin0.lingym")
        app.launch()
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.system.open(URL(string: "lingym://water")!)
        XCTAssertTrue(app.navigationBars["喝水"].waitForExistence(timeout: 20))
        app.tabBars.buttons["计划"].tap()
        XCUIDevice.shared.press(.home)
        // Widgets installed before this release still use the original scheme.
        XCUIDevice.shared.system.open(URL(string: "opengym://water")!)
        XCTAssertTrue(app.navigationBars["喝水"].waitForExistence(timeout: 20))
    }
}
