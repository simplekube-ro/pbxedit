import Foundation
import XCTest

/// Task 1.1: the executable exists and prints usage.
final class UsageTests: XCTestCase {
    func testHelpPrintsUsage() throws {
        let result = try pbxedit(["--help"])
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("USAGE: pbxedit"), result.stdout)
    }
}
