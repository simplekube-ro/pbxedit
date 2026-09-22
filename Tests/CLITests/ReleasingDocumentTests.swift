import Foundation
import XCTest

/// release-distribution task 6.2: the Release checklist scenario —
/// `docs/RELEASING.md` lists the version bump, the manual Xcode
/// open-and-save check with a place to record the Xcode version, the tag
/// command, and the post-release verification of the Homebrew formula.
final class ReleasingDocumentTests: XCTestCase {
    static let document = Fixtures.directory
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // the repository
        .appendingPathComponent("docs/RELEASING.md")

    private func text() throws -> String {
        String(decoding: try Data(contentsOf: Self.document), as: UTF8.self)
    }

    func testTheFourChecklistItemsAreSections() throws {
        let headings = try text().split(separator: "\n").filter { $0.hasPrefix("#") }.map { String($0) }
        for expected in ["## 1. Bump the version", "## 2. Manual Xcode open-and-save check", "## 3. Tag", "## 4. Verify the Homebrew formula"] {
            XCTAssertTrue(headings.contains(expected), "missing heading \(expected.debugDescription) in \(headings)")
        }
    }

    func testTheManualCheckRecordsTheXcodeVersionAndCoversEveryMutatingCommand() throws {
        let text = try text()
        XCTAssertTrue(text.contains("Xcode version used:"), "no field for the Xcode version")
        XCTAssertTrue(text.contains("xcodebuild -version"))
        for command in ["add", "move", "remove", "lint --fix"] {
            XCTAssertTrue(text.contains("# pbxedit \(command)"), "the manual check does not exercise \(command)")
        }
        XCTAssertTrue(text.contains("git diff --exit-code"), "the check must expect no diff after Xcode saves")
    }

    func testTheProcedureNamesTheVersionFileTheTagCommandAndTheFormula() throws {
        let text = try text()
        XCTAssertTrue(text.contains("Sources/pbxedit/Version.swift"))
        XCTAssertTrue(text.contains("static let base = \""))
        XCTAssertTrue(text.contains("git tag -a v"))
        XCTAssertTrue(text.contains("git push origin v"))
        XCTAssertTrue(text.contains("brew install"))
        XCTAssertTrue(text.contains("brew test"))
        XCTAssertTrue(text.contains("pbxedit --version"))
        XCTAssertTrue(text.contains("shasum -a 256"))
    }
}
