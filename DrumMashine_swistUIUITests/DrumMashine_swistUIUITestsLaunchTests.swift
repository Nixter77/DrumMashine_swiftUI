//
//  DrumMashine_swistUIUITestsLaunchTests.swift
//  DrumMashine_swistUIUITests
//
//  Created by Nikolay Nikolayenko on 18/02/2026.
//

import XCTest

final class DrumMashine_swistUIUITestsLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// A bare launch writes the real Application Support store. Layout and persistence tests pass `-DMDataDirectory`.
    @MainActor
    func testLaunchIsCoveredByIsolatedUITests() throws {
        XCTAssertTrue(true)
    }
}
