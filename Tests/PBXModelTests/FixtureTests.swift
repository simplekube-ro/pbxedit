import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// Task 1.2: the model fixtures are valid property lists and round-trip.
final class FixtureTests: XCTestCase {
    func testModelFixturesLintAndRoundTrip() throws {
        let files = Fixtures.projectFiles(under: "model")
        XCTAssertEqual(files.map(\.lastPathComponent), ["app.pbxproj", "broken.pbxproj"])
        for url in files {
            let input = Array(try Data(contentsOf: url))
            assertPlutilLints(input, url.lastPathComponent)
            switch SyntaxTree.parse(input) {
            case .failure(let error):
                XCTFail("\(url.lastPathComponent) does not parse: \(error)")
            case .success(let tree):
                XCTAssertTrue(tree.serialize() == input, "\(url.lastPathComponent) does not round-trip")
            }
        }
    }
}
