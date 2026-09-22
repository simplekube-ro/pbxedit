import XCTest
@testable import PBXOps

/// Task 2.1: the path glob matcher of design D3.
final class GlobTests: XCTestCase {
    private func matches(_ pattern: String, _ path: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        do {
            return try PathGlob(pattern).matches(path)
        } catch {
            XCTFail("\(pattern) does not compile: \(error)", file: file, line: line)
            return false
        }
    }

    func testStarMatchesWithinOneSegment() {
        XCTAssertTrue(matches("App/*.swift", "App/Foo.swift"))
        XCTAssertTrue(matches("App/*", "App/Foo.swift"))
        XCTAssertFalse(matches("App/*.swift", "App/Views/Foo.swift"), "* never crosses a slash")
        XCTAssertTrue(matches("App/*/Foo.swift", "App/Views/Foo.swift"))
        XCTAssertFalse(matches("App/*/Foo.swift", "App/Foo.swift"), "* matches exactly one segment, possibly empty text")
        XCTAssertTrue(matches("*Tests/*.swift", "AppTests/FooTests.swift"))
        XCTAssertTrue(matches("*", "Foo.swift"))
        XCTAssertFalse(matches("*", "App/Foo.swift"))
    }

    func testDoubleStarMatchesAcrossSegmentsIncludingNone() {
        XCTAssertTrue(matches("App/**", "App/Foo.swift"))
        XCTAssertTrue(matches("App/**", "App/Views/Deep/Foo.swift"))
        XCTAssertFalse(matches("App/**", "AppTests/Foo.swift"))
        XCTAssertTrue(matches("**/Generated/**", "App/Generated/User.swift"))
        XCTAssertTrue(matches("**/Generated/**", "Generated/User.swift"), "leading ** matches zero segments")
        XCTAssertTrue(matches("**/Generated/**", "A/B/Generated/C/D.swift"))
        XCTAssertTrue(matches("**/Generated/**", "App/Generated"), "trailing ** matches zero segments too (spec: zero or more whole segments)")
        XCTAssertTrue(matches("App/**/Foo.swift", "App/Foo.swift"), "** in the middle matches zero segments")
        XCTAssertTrue(matches("App/**/Foo.swift", "App/Views/Sub/Foo.swift"))
        XCTAssertTrue(matches("**", "Foo.swift"))
        XCTAssertTrue(matches("**", "App/Views/Foo.swift"))
        XCTAssertTrue(matches("**/*.swift", "Foo.swift"))
        XCTAssertFalse(matches("**/*.swift", "Foo.m"))
    }

    func testQuestionMarkMatchesOneCharacter() {
        XCTAssertTrue(matches("App/TV?.swift", "App/TV1.swift"))
        XCTAssertFalse(matches("App/TV?.swift", "App/TV10.swift"))
        XCTAssertFalse(matches("App/TV?.swift", "App/TV.swift"))
        XCTAssertFalse(matches("App/?/x", "App//x"))
    }

    func testPatternsAreAnchoredAtBothEnds() {
        XCTAssertFalse(matches("Views/Foo.swift", "App/Views/Foo.swift"), "anchored at the start")
        XCTAssertFalse(matches("App/Views", "App/Views/Foo.swift"), "anchored at the end")
        XCTAssertTrue(matches("App/Views/Foo.swift", "App/Views/Foo.swift"))
        XCTAssertFalse(matches("App", "Application"))
        XCTAssertTrue(matches("App/Views", "App/Views"))
    }

    func testMatchingIsCaseSensitive() {
        XCTAssertFalse(matches("app/**", "App/Foo.swift"))
    }

    func testUnsupportedSyntaxIsRejected() {
        for pattern in ["App/[ab].swift", "App/{a,b}.swift", "**.swift", "App/**Foo", "/App/**", "App/", "App//Views", ""] {
            XCTAssertThrowsError(try PathGlob(pattern), pattern) { error in
                XCTAssertTrue("\(error)".contains(pattern.isEmpty ? "empty" : pattern) || "\(error)".contains("segment"), "\(pattern): \(error)")
            }
        }
    }

    func testThePatternIsKept() throws {
        XCTAssertEqual(try PathGlob("App/**").pattern, "App/**")
    }
}
