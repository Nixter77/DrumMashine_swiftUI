import XCTest

/// Layout checks. The template launch tests are gone: a launch without `-DMDataDirectory` would write the real store.
final class DrumMashine_swistUIUITests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let root = realUserHome()
            .appendingPathComponent("Library/Containers/Home.DrumMashine-swistUI/Data/tmp", isDirectory: true)
        directory = root.appendingPathComponent("DrumMachineUI-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testLayoutAtMinimumSize() throws {
        try assertLayout(width: 1100, height: 720)
        try assertLayout(width: 1440, height: 900)
    }

    @MainActor
    private func assertLayout(width: CGFloat, height: CGFloat) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DMDataDirectory", directory.path,
            "-DMWindowSize", "\(Int(width))x\(Int(height))"
        ]
        app.launch()
        let play = hittable(app, identifier: "transport.play")
        XCTAssertTrue(play.waitForExistence(timeout: 60))
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, abs(windowContaining(app, element: play).frame.width - width) > 40 {
            Thread.sleep(forTimeInterval: 0.1)
        }
        let window = windowContaining(app, element: play)
        // The title bar makes the frame taller than the content. The width stays near the request.
        XCTAssertGreaterThanOrEqual(window.frame.width, width - 8, "window \(window.frame)")
        XCTAssertLessThan(window.frame.width, width + 80, "window \(window.frame)")
        XCTAssertGreaterThanOrEqual(window.frame.height, height - 8, "window \(window.frame)")
        let playFrame = play.frame
        XCTAssertTrue(window.frame.insetBy(dx: -1, dy: -1).contains(playFrame), "play \(playFrame) window \(window.frame)")
        let sequencer = app.descendants(matching: .any)["seq.panel"]
        let pads = app.descendants(matching: .any)["pads.panel"]
        XCTAssertTrue(sequencer.waitForExistence(timeout: 5))
        XCTAssertTrue(pads.waitForExistence(timeout: 5))
        XCTAssertFalse(playFrame.intersects(sequencer.frame), "play overlaps sequencer")
        XCTAssertFalse(playFrame.intersects(pads.frame), "play overlaps pads")
        let slot = hittable(app, identifier: "pattern.slot.D")
        XCTAssertTrue(slot.isHittable, "pattern.slot.D frame \(slot.frame)")
        app.terminate()
    }

    @MainActor
    private func hittable(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 20), "missing \(identifier)")
        for index in 0..<query.count {
            let element = query.element(boundBy: index)
            if element.exists && element.isHittable {
                return element
            }
        }
        let fallback = query.firstMatch
        XCTFail("\(identifier) is not hittable. frame=\(fallback.frame) window=\(app.windows.firstMatch.frame)")
        return fallback
    }

    @MainActor
    private func windowContaining(_ app: XCUIApplication, element: XCUIElement) -> XCUIElement {
        let frame = element.frame
        for index in 0..<app.windows.count {
            let window = app.windows.element(boundBy: index)
            if window.exists && window.frame.intersects(frame) {
                return window
            }
        }
        return app.windows.firstMatch
    }
}

/// UI test runners live in their own container. Strip that suffix to reach the real user home.
private func realUserHome() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if let range = home.range(of: "/Library/Containers/") {
        return URL(fileURLWithPath: String(home[..<range.lowerBound]), isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
}
