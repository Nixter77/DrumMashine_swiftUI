import XCTest

/// Launch, edit, quit, launch again. The store folder is inside the app container so the sandbox can write it.
final class PersistenceRelaunchUITests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The runner is sandboxed and cannot create this folder. The path stays inside the app
        // container, and PersistenceStore creates it when the app launches.
        let root = realUserHome()
            .appendingPathComponent("Library/Containers/Home.DrumMashine-swistUI/Data/tmp", isDirectory: true)
        directory = root.appendingPathComponent("DrumMachineUI-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testBPMAndStepsSurviveTerminate() throws {
        let app = launch()
        raiseBPM(in: app, times: 13)
        let kick = step(app, track: 0, index: 0)
        let snare = step(app, track: 1, index: 4)
        kick.click()
        snare.click()
        Thread.sleep(forTimeInterval: 1)
        app.terminate()

        let restarted = launch()
        XCTAssertEqual(bpmText(restarted), "133")
        XCTAssertEqual(step(restarted, track: 0, index: 0).value as? String, "on")
        XCTAssertEqual(step(restarted, track: 1, index: 4).value as? String, "on")
    }

    @MainActor
    func testStepSurvivesCommandQWithoutWaiting() throws {
        let app = launch()
        let kick = step(app, track: 0, index: 0)
        kick.click()
        app.typeKey("q", modifierFlags: .command)

        let restarted = launch()
        XCTAssertEqual(step(restarted, track: 0, index: 0).value as? String, "on")
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-DMDataDirectory", directory.path]
        app.launch()
        XCTAssertTrue(app.buttons["transport.bpm.plus"].waitForExistence(timeout: 60))
        app.activate()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, app.windows.firstMatch.frame.width < 1400 {
            Thread.sleep(forTimeInterval: 0.1)
        }
        return app
    }

    @MainActor
    private func raiseBPM(in app: XCUIApplication, times: Int) {
        let plus = hittable(app, identifier: "transport.bpm.plus")
        for _ in 0..<times {
            plus.click()
            Thread.sleep(forTimeInterval: 0.05)
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, bpmText(app) != "133" {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(bpmText(app), "133")
    }

    @MainActor
    private func bpmText(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)["transport.bpm"]
        if let value = element.value as? String, !value.isEmpty, value != "BPM" {
            return value
        }
        return element.label
    }

    @MainActor
    private func step(_ app: XCUIApplication, track: Int, index: Int) -> XCUIElement {
        let element = hittable(app, identifier: "seq.step.\(track).\(index)")
        XCTAssertTrue(element.waitForExistence(timeout: 20), "missing seq.step.\(track).\(index)")
        return element
    }

    /// ViewThatFits can leave a second, non-hittable copy in the tree. Click the one on screen.
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
}

/// UI test runners live in their own container. Strip that suffix to reach the real user home.
private func realUserHome() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if let range = home.range(of: "/Library/Containers/") {
        return URL(fileURLWithPath: String(home[..<range.lowerBound]), isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
}
