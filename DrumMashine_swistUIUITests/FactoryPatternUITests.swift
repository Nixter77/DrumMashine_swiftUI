import XCTest

/// Opens PATTERNS and loads Boom Bap. The data directory stays under the app-container tmp.
final class FactoryPatternUITests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let root = realUserHome()
            .appendingPathComponent("Library/Containers/Home.DrumMashine-swistUI/Data/tmp", isDirectory: true)
        directory = root.appendingPathComponent("DrumMachinePatterns-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testLoadBoomBapFromPatternsPage() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-DMDataDirectory", directory.path,
            "-DMWindowSize", "1100x720"
        ]
        app.launch()

        let play = hittable(app, identifier: "transport.play")
        XCTAssertTrue(play.waitForExistence(timeout: 60))
        let toggle = hittable(app, identifier: "library.toggle")
        toggle.click()

        let panel = app.descendants(matching: .any)["library.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "library did not open")
        let patternsTab = app.descendants(matching: .any)["library.page.patterns"]
        XCTAssertTrue(patternsTab.waitForExistence(timeout: 15), "missing library.page.patterns")
        XCTAssertTrue(patternsTab.isHittable, "patterns tab offscreen \(patternsTab.frame)")
        // A click on a background window only activates it. Bring the app forward first.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let list = app.descendants(matching: .any)["pattern.factory.list"]
        let tabPoint = patternsTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        tabPoint.click()
        if !list.waitForExistence(timeout: 2) {
            tabPoint.click()
        }
        XCTAssertTrue(list.waitForExistence(timeout: 10), "patterns page did not open. labels=\(visibleLabels(app))")

        let boomBap = reveal(app, identifier: "pattern.factory.hiphop_boombap", scroller: "pattern.factory.list", horizontal: false)
        boomBap.click()
        let loadedMark = app.descendants(matching: .any)["pattern.factory.loaded.hiphop_boombap"]
        if !loadedMark.waitForExistence(timeout: 3) {
            boomBap.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }

        let bpm = hittable(app, identifier: "transport.bpm")
        XCTAssertTrue(reads("90", element: bpm), "bpm value=\(bpm.value ?? "nil") label=\(bpm.label)")
        let swing = hittable(app, identifier: "transport.swing")
        XCTAssertTrue(reads("55", element: swing), "swing value=\(swing.value ?? "nil") label=\(swing.label)")

        let loaded = app.descendants(matching: .any)["pattern.factory.loaded.hiphop_boombap"]
        XCTAssertTrue(loaded.waitForExistence(timeout: 5))

        let window = windowContaining(app, element: play)
        let playFrame = hittable(app, identifier: "transport.play").frame
        let rowFrame = hittable(app, identifier: "pattern.factory.hiphop_boombap").frame
        XCTAssertTrue(window.frame.insetBy(dx: -2, dy: -2).contains(playFrame), "play \(playFrame) window \(window.frame)")
        XCTAssertTrue(window.frame.insetBy(dx: -2, dy: -2).contains(rowFrame), "boom bap \(rowFrame) window \(window.frame)")
        let sequencer = app.descendants(matching: .any)["seq.panel"]
        let pads = app.descendants(matching: .any)["pads.panel"]
        XCTAssertTrue(sequencer.exists)
        XCTAssertTrue(pads.exists)
        XCTAssertFalse(playFrame.intersects(sequencer.frame))
        XCTAssertFalse(playFrame.intersects(pads.frame))

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "patterns-boom-bap-1100"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func visibleLabels(_ app: XCUIApplication) -> String {
        let labels = app.staticTexts.allElementsBoundByIndex.prefix(25).map(\.label)
        return labels.joined(separator: " | ")
    }

    @MainActor
    private func reads(_ number: String, element: XCUIElement) -> Bool {
        let value = element.value as? String ?? ""
        if value == number || value.hasPrefix(number) { return true }
        let label = element.label.replacingOccurrences(of: "%", with: "")
        return label == number || label.hasPrefix("\(number) ")
    }

    /// Scrolls a tab strip or the pattern list until the control can be clicked.
    /// A drag lands on a tab button and does not move the strip, so this sends scroll events.
    @MainActor
    private func reveal(
        _ app: XCUIApplication,
        identifier: String,
        scroller scrollerID: String,
        horizontal: Bool
    ) -> XCUIElement {
        let target = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(target.waitForExistence(timeout: 15), "missing \(identifier)")
        let scroller = app.descendants(matching: .any)[scrollerID]
        XCTAssertTrue(scroller.waitForExistence(timeout: 5), "missing \(scrollerID)")
        var revealRight: CGFloat = horizontal ? 70 : 0
        var revealDown: CGFloat = horizontal ? 0 : 80
        for _ in 0..<16 {
            if contains(target.frame, in: scroller.frame) && target.isHittable {
                return target
            }
            let before = target.frame
            if horizontal {
                let delta: CGFloat = target.frame.maxX > scroller.frame.maxX + 2 ? revealRight : -revealRight
                scroller.scroll(byDeltaX: delta, deltaY: 0)
                if target.frame.maxX >= before.maxX - 0.5, target.frame.maxX > scroller.frame.maxX {
                    revealRight = -revealRight
                }
            } else {
                let delta: CGFloat = target.frame.maxY > scroller.frame.maxY + 2 ? revealDown : -revealDown
                scroller.scroll(byDeltaX: 0, deltaY: delta)
                if target.frame.maxY >= before.maxY - 0.5, target.frame.maxY > scroller.frame.maxY {
                    revealDown = -revealDown
                }
            }
        }
        XCTAssertTrue(
            contains(target.frame, in: scroller.frame) && target.isHittable,
            "\(identifier) stayed offscreen. frame=\(target.frame) scroller=\(scroller.frame)"
        )
        return target
    }

    private func contains(_ inner: CGRect, in outer: CGRect) -> Bool {
        outer.insetBy(dx: 2, dy: 2).contains(inner)
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
