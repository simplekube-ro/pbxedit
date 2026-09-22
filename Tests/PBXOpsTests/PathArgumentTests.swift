import Foundation
import XCTest
@testable import PBXOps

/// Task 1.1: path arguments (spec: Path arguments; design D1).
final class PathArgumentTests: XCTestCase {
    private let root = "/Users/me/Projects/App"

    // Spec: Path arguments — Run from a subdirectory.
    func testRelativeFromASubdirectory() throws {
        XCTAssertEqual(try PathArgument.resolve("Foo.swift", cwd: root + "/App/Views", sourceRoot: root), "App/Views/Foo.swift")
        XCTAssertEqual(try PathArgument.resolve("Views/Foo.swift", cwd: root + "/App", sourceRoot: root), "App/Views/Foo.swift")
    }

    func testRelativeFromTheSourceRoot() throws {
        XCTAssertEqual(try PathArgument.resolve("App/Views/Foo.swift", cwd: root, sourceRoot: root), "App/Views/Foo.swift")
    }

    func testAbsolute() throws {
        XCTAssertEqual(try PathArgument.resolve(root + "/App/Foo.swift", cwd: "/elsewhere", sourceRoot: root), "App/Foo.swift")
    }

    func testDotAndDotDotSegmentsAreNormalizedLexically() throws {
        XCTAssertEqual(try PathArgument.resolve("./Foo.swift", cwd: root + "/App", sourceRoot: root), "App/Foo.swift")
        XCTAssertEqual(try PathArgument.resolve("../Shared/Bar.swift", cwd: root + "/App/Views", sourceRoot: root), "App/Shared/Bar.swift")
        XCTAssertEqual(try PathArgument.resolve("App//Views/./../Views/Foo.swift/", cwd: root, sourceRoot: root), "App/Views/Foo.swift")
        XCTAssertEqual(try PathArgument.resolve("Foo.swift", cwd: root + "/App/", sourceRoot: root + "/"), "App/Foo.swift", "trailing slashes on the directories do not matter")
    }

    // Spec: Path arguments — Outside the source root.
    func testOutsideTheSourceRootIsAnError() {
        XCTAssertThrowsError(try PathArgument.resolve("../../Other/Foo.swift", cwd: root + "/App", sourceRoot: root)) { error in
            XCTAssertEqual(error as? PathArgumentError, .outsideSourceRoot(path: "/Users/me/Projects/Other/Foo.swift", sourceRoot: root))
        }
        XCTAssertThrowsError(try PathArgument.resolve("/tmp/Foo.swift", cwd: root, sourceRoot: root))
        // A sibling directory whose name merely starts with the root's name is outside too.
        XCTAssertThrowsError(try PathArgument.resolve(root + "Extra/Foo.swift", cwd: "/", sourceRoot: root))
    }

    func testTheSourceRootItselfIsAnError() {
        XCTAssertThrowsError(try PathArgument.resolve(".", cwd: root, sourceRoot: root)) { error in
            XCTAssertEqual(error as? PathArgumentError, .isSourceRoot(sourceRoot: root))
        }
        XCTAssertThrowsError(try PathArgument.resolve("..", cwd: root + "/App", sourceRoot: root))
    }

    func testErrorsAreDescribedWithBothPaths() {
        let outside = PathArgumentError.outsideSourceRoot(path: "/x/Foo.swift", sourceRoot: root)
        XCTAssertTrue(outside.description.contains("/x/Foo.swift"), outside.description)
        XCTAssertTrue(outside.description.contains(root), outside.description)
        XCTAssertTrue(PathArgumentError.isSourceRoot(sourceRoot: root).description.contains(root))
    }
}
