import XCTest

/// SCENE → Dub turns reverb and delay on and leaves distortion off.
/// The data directory stays under the app-container tmp.
final class EffectSceneUITests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let root = realUserHome()
            .appendingPathComponent("Library/Containers/Home.DrumMashine-swistUI/Data/tmp", isDirectory: true)
        directory = root.appendingPathComponent("DrumMachineEffects-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testSceneDubEnablesReverbAndDelay() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DMDataDirectory", directory.path,
            "-DMWindowSize", "1100x720"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        // The engine replaces the whole window with the loading view until it is ready.
        // One long wait covers that. A second identifier query has come back empty.
        let scene = hittable(app, identifier: "effects.scene")
        let window = windowContaining(app, element: scene)
        XCTAssertTrue(
            window.frame.insetBy(dx: -2, dy: -2).contains(scene.frame),
            "scene menu \(scene.frame) outside \(window.frame)"
        )
        scene.click()

        let dub = app.descendants(matching: .any)["effects.scene.dub"]
        if !dub.waitForExistence(timeout: 3) {
            scene.click()
        }
        XCTAssertTrue(dub.waitForExistence(timeout: 5), "Dub item missing. labels=\(visibleLabels(app))")
        dub.click()

        XCTAssertEqual(power(app, "effect.reverb.power"), "on")
        XCTAssertEqual(power(app, "effect.delay.power"), "on")
        XCTAssertEqual(power(app, "effect.distortion.power"), "off")

        let name = app.descendants(matching: .any)["effects.scene.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(
            name.label,
            "Dub",
            "label=\(name.label) value=\(String(describing: name.value))"
        )
    }

    @MainActor
    private func power(_ app: XCUIApplication, _ identifier: String) -> String {
        let probe = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "missing \(identifier)")
        return probe.label
    }

    @MainActor
    private func visibleLabels(_ app: XCUIApplication) -> String {
        app.staticTexts.allElementsBoundByIndex.prefix(25).map(\.label).joined(separator: " | ")
    }

    @MainActor
    private func hittable(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        let deadline = Date().addingTimeInterval(45)
        var detail = ""
        while Date() < deadline {
            app.activate()
            let element = app.descendants(matching: .any)[identifier]
            if element.waitForExistence(timeout: 2), element.exists, element.isHittable {
                return element
            }
            detail = "exists=\(element.exists) frame=\(element.frame) windows=\(app.windows.count)"
        }
        XCTFail("missing \(identifier). \(detail) debug=\(String(app.debugDescription.prefix(500)))")
        return app.descendants(matching: .any)[identifier]
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
