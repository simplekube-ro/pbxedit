import Foundation
import XCTest

/// Task 7.1: `pbxedit lint` end to end, against the built binary.
final class LintCommandTests: XCTestCase {
    /// `rules/m3-orphan.pbxproj` plus a second orphan whose bare hyphen is an
    /// S5: two M3 errors and one S5 warning (spec: Human output).
    static func twoM3OneS5() throws -> [UInt8] {
        let source = String(decoding: try Fixtures.load("rules/m3-orphan.pbxproj"), as: UTF8.self)
        let marker = "/* End PBXFileReference section */"
        let extra = "\t\tAB13 /* Bar-Baz.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Bar-Baz.swift; sourceTree = SOURCE_ROOT; };\n"
        guard let range = source.range(of: marker) else { throw NSError(domain: "fixture", code: 1) }
        return Array(source.replacingCharacters(in: range, with: extra + marker).utf8)
    }

    func testHumanOutput() throws {
        let project = try TemporaryProject(try LintCommandTests.twoM3OneS5())
        let before = try project.bytes()
        let result = try pbxedit(["lint", "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 1, result.stderr)
        let lines = result.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4, result.stdout)
        XCTAssertTrue(lines[0].hasPrefix("error M3 AB12 AppTests/Views/FooTests.swift: "), lines[0])
        XCTAssertTrue(lines[1].hasPrefix("error M3 AB13 Bar-Baz.swift: "), lines[1])
        XCTAssertTrue(lines[2].hasPrefix("warning S5 AB13 Bar-Baz.swift: "), lines[2])
        XCTAssertEqual(lines[3], "2 errors, 1 warning")
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(try project.bytes(), before, "lint never edits")
    }

    func testJSONOutput() throws {
        let project = try TemporaryProject(try LintCommandTests.twoM3OneS5())
        let result = try pbxedit(["lint", "--json", "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 1, result.stderr)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any], result.stdout)
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "project", "findings", "summary", "resolved"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual((object["project"] as? String)?.hasSuffix("App.xcodeproj/project.pbxproj"), true)
        let findings = try XCTUnwrap(object["findings"] as? [[String: Any]])
        XCTAssertEqual(findings.count, 3)
        for finding in findings {
            XCTAssertEqual(Set(finding.keys), ["rule", "severity", "object", "path", "related", "message"])
        }
        XCTAssertEqual(findings.map { $0["rule"] as? String }, ["M3", "M3", "S5"])
        XCTAssertEqual(findings.map { $0["severity"] as? String }, ["error", "error", "warning"])
        XCTAssertEqual(findings[0]["object"] as? String, "AB12")
        XCTAssertEqual(findings[0]["path"] as? String, "AppTests/Views/FooTests.swift")
        XCTAssertEqual(findings[0]["related"] as? [String], [])
        let summary = try XCTUnwrap(object["summary"] as? [String: Int])
        XCTAssertEqual(summary, ["errors": 2, "warnings": 1, "baselined": 0, "resolved": 0])
        XCTAssertEqual(object["resolved"] as? [[String: String]], [])
        XCTAssertEqual(result.stderr, "")
    }

    func testJSONHasNullForAbsentObjectAndPath() throws {
        // An S5 outside `objects` has no object; the key is still present, as null.
        let source = "{ archiveVersion = \"1\"; objects = { P1 = {isa = PBXProject; mainGroup = G1; }; G1 = {isa = PBXGroup; children = (); }; }; rootObject = P1; }\n"
        let project = try TemporaryProject(Array(source.utf8))
        let result = try pbxedit(["lint", "--json", "--project", project.pbxproj.path])
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("\"object\" : null"), result.stdout)
    }

    // Spec: Exit codes.
    func testExitCodeIsZeroOnACleanProject() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let result = try pbxedit(["lint", "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, "0 errors, 0 warnings\n")
    }

    // Spec: Exit codes — Warnings only.
    func testWarningsOnlyExitZeroUnlessStrict() throws {
        let project = try TemporaryProject(fixture: "rules/s5-bare-hyphen.pbxproj")
        let lenient = try pbxedit(["lint", "--project", project.xcodeproj.path])
        XCTAssertEqual(lenient.status, 0, lenient.stderr)
        XCTAssertTrue(lenient.stdout.hasSuffix("0 errors, 1 warning\n"), lenient.stdout)
        let strict = try pbxedit(["lint", "--strict", "--project", project.xcodeproj.path])
        XCTAssertEqual(strict.status, 1, strict.stderr)
    }

    func testAnUnparseableProjectIsAnS1AndExitsOne() throws {
        let project = try TemporaryProject(fixture: "rules/s1-unterminated-comment.pbxproj")
        let result = try pbxedit(["lint", "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 1, result.stderr)
        XCTAssertTrue(result.stdout.hasPrefix("error S1 : the project file does not parse: 3:14"), result.stdout)
    }

    func testUsageErrorsExitTwo() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let unknownFlag = try pbxedit(["lint", "--no-such-flag", "--project", project.xcodeproj.path])
        XCTAssertEqual(unknownFlag.status, 2)
        XCTAssertTrue(unknownFlag.stderr.contains("--no-such-flag"), unknownFlag.stderr)
        let missing = try pbxedit(["lint", "--project", project.root.appendingPathComponent("Nope.xcodeproj").path])
        XCTAssertEqual(missing.status, 2)
        XCTAssertTrue(missing.stderr.contains("Nope.xcodeproj"), missing.stderr)
        XCTAssertEqual(missing.stdout, "")
        let missingJSON = try pbxedit(["lint", "--json", "--project", project.root.appendingPathComponent("Nope.xcodeproj").path])
        XCTAssertEqual(missingJSON.status, 2)
        XCTAssertTrue(missingJSON.stderr.contains("\"error\""), missingJSON.stderr)
        XCTAssertEqual(missingJSON.stdout, "")
    }

    func testDiskFlagEnablesD1() throws {
        let project = try TemporaryProject(fixture: "rules/m3-orphan.pbxproj")
        let without = try pbxedit(["lint", "--project", project.xcodeproj.path])
        XCTAssertFalse(without.stdout.contains("D1"), without.stdout)
        let with = try pbxedit(["lint", "--disk", "--project", project.xcodeproj.path])
        XCTAssertTrue(with.stdout.contains("warning D1 AB12 AppTests/Views/FooTests.swift: "), with.stdout)
        XCTAssertTrue(with.stdout.hasSuffix("1 error, 1 warning\n"), with.stdout)
    }
}
