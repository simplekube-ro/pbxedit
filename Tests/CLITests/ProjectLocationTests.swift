import Foundation
import XCTest

/// Task 7.2: spec — Project location.
final class ProjectLocationTests: XCTestCase {
    func testTheSingleProjectInTheCurrentDirectoryIsUsed() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let result = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, "0 errors, 0 warnings\n")
    }

    // Spec: Project location — Two projects in the directory.
    func testTwoProjectsInTheDirectoryIsAUsageError() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        _ = try project.addProject(named: "Tools", try Fixtures.load("model/app.pbxproj"))
        let result = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains("App.xcodeproj"), result.stderr)
        XCTAssertTrue(result.stderr.contains("Tools.xcodeproj"), result.stderr)
        XCTAssertTrue(result.stderr.contains("--project"), result.stderr)
        XCTAssertEqual(result.stdout, "")
    }

    func testNoProjectInTheDirectoryIsAUsageError() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("pbxedit-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let result = try pbxedit(["lint"], in: empty)
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains("no .xcodeproj"), result.stderr)
        XCTAssertTrue(result.stderr.contains("--project"), result.stderr)
    }

    func testProjectOptionAcceptsTheDirectoryOrTheFile() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        XCTAssertEqual(try pbxedit(["lint", "--project", project.xcodeproj.path]).status, 0)
        XCTAssertEqual(try pbxedit(["lint", "--project", project.pbxproj.path]).status, 0)
        let relative = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(relative.status, 0, relative.stderr)
        let notAProject = try pbxedit(["lint", "--project", project.root.path])
        XCTAssertEqual(notAProject.status, 2)
        XCTAssertTrue(notAProject.stderr.contains("project.pbxproj"), notAProject.stderr)
    }
}
