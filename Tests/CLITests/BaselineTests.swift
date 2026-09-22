import Foundation
import XCTest

/// Task 7.4: spec — Baseline.
final class BaselineTests: XCTestCase {
    private func baselineURL(_ project: TemporaryProject) -> URL {
        project.root.appendingPathComponent(".pbxedit-baseline.json")
    }

    // Spec: Baseline — Adopting on a damaged project (two M3s stand in for 655).
    func testWriteBaselineThenBaselineIsClean() throws {
        let project = try TemporaryProject(try LintCommandTests.twoM3OneS5())
        let baseline = baselineURL(project)
        let written = try pbxedit(["lint", "--write-baseline", baseline.path, "--project", project.xcodeproj.path])
        XCTAssertEqual(written.status, 0, "writing a baseline exits 0 whatever the findings: \(written.stderr)")
        XCTAssertTrue(written.stdout.contains("2 errors, 1 warning"), written.stdout)
        XCTAssertTrue(written.stdout.contains("baseline written: \(baseline.path) (3 entries)"), written.stdout)

        // Design D6: sorted by rule then object, one entry per line.
        let text = try String(contentsOf: baseline, encoding: .utf8)
        XCTAssertEqual(text, """
            {
              "schemaVersion": 1,
              "entries": [
                { "rule": "M3", "object": "AB12" },
                { "rule": "M3", "object": "AB13" },
                { "rule": "S5", "object": "AB13" }
              ]
            }

            """)

        let checked = try pbxedit(["lint", "--baseline", baseline.path, "--project", project.xcodeproj.path])
        XCTAssertEqual(checked.status, 0, checked.stderr)
        XCTAssertEqual(checked.stdout, "0 errors, 0 warnings, 3 baselined\n")

        let json = try pbxedit(["lint", "--json", "--baseline", baseline.path, "--project", project.xcodeproj.path])
        XCTAssertEqual(json.status, 0, json.stderr)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.stdout.utf8)) as? [String: Any])
        XCTAssertEqual((object["findings"] as? [Any])?.count, 0)
        XCTAssertEqual(object["summary"] as? [String: Int], ["errors": 0, "warnings": 0, "baselined": 3, "resolved": 0])
    }

    // Spec: Baseline — New damage after adoption.
    func testNewDamageAfterAdoptionIsReported() throws {
        let project = try TemporaryProject(try LintCommandTests.twoM3OneS5())
        let baseline = baselineURL(project)
        XCTAssertEqual(try pbxedit(["lint", "--write-baseline", baseline.path, "--project", project.xcodeproj.path]).status, 0)
        // One more ungrouped reference.
        var source = String(decoding: try project.bytes(), as: UTF8.self)
        let marker = "/* End PBXFileReference section */"
        source = source.replacingOccurrences(
            of: marker,
            with: "\t\tAB14 /* New.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = New.swift; sourceTree = SOURCE_ROOT; };\n" + marker)
        try Data(source.utf8).write(to: project.pbxproj)
        let result = try pbxedit(["lint", "--baseline", baseline.path, "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 1)
        let lines = result.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2, result.stdout)
        XCTAssertTrue(lines[0].hasPrefix("error M3 AB14 New.swift: "), lines[0])
        XCTAssertEqual(lines[1], "1 error, 0 warnings, 3 baselined")
    }

    func testResolvedEntriesAreListed() throws {
        let project = try TemporaryProject(try LintCommandTests.twoM3OneS5())
        let baseline = baselineURL(project)
        XCTAssertEqual(try pbxedit(["lint", "--write-baseline", baseline.path, "--project", project.xcodeproj.path]).status, 0)
        // Repair one orphan by putting it into the Products group.
        var source = String(decoding: try project.bytes(), as: UTF8.self)
        source = source.replacingOccurrences(of: "\t\t\t\tAF01 /* App.app */,\n", with: "\t\t\t\tAF01 /* App.app */,\n\t\t\t\tAB12 /* FooTests.swift */,\n")
        try Data(source.utf8).write(to: project.pbxproj)
        let result = try pbxedit(["lint", "--baseline", baseline.path, "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, "resolved M3 AB12: no longer reported; remove it from the baseline\n0 errors, 0 warnings, 2 baselined, 1 resolved\n")
        let json = try pbxedit(["lint", "--json", "--baseline", baseline.path, "--project", project.xcodeproj.path])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.stdout.utf8)) as? [String: Any])
        XCTAssertEqual(object["resolved"] as? [[String: String]], [["rule": "M3", "object": "AB12"]])
        XCTAssertEqual(object["summary"] as? [String: Int], ["errors": 0, "warnings": 0, "baselined": 2, "resolved": 1])
    }

    // Spec: Baseline — Missing baseline file.
    func testMissingBaselineFileIsAUsageError() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let result = try pbxedit(["lint", "--baseline", baselineURL(project).path, "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains(".pbxedit-baseline.json"), result.stderr)
        XCTAssertTrue(result.stderr.contains("--write-baseline"), result.stderr)
        XCTAssertEqual(result.stdout, "")
    }

    func testAMalformedBaselineIsAUsageError() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let baseline = baselineURL(project)
        try Data("{ \"schemaVersion\": 99, \"entries\": [] }".utf8).write(to: baseline)
        let result = try pbxedit(["lint", "--baseline", baseline.path, "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains("schemaVersion"), result.stderr)
        try Data("not json".utf8).write(to: baseline)
        XCTAssertEqual(try pbxedit(["lint", "--baseline", baseline.path, "--project", project.xcodeproj.path]).status, 2)
    }

    func testBaselineKeysAFindingWithoutAnObjectOnItsPath() throws {
        // An S5 outside `objects` has no object; D6 keys it on its path.
        let source = "{ archiveVersion = \"1\"; objects = { P1 = {isa = PBXProject; mainGroup = G1; }; G1 = {isa = PBXGroup; children = (); }; }; rootObject = P1; }\n"
        let project = try TemporaryProject(Array(source.utf8))
        let baseline = baselineURL(project)
        XCTAssertEqual(try pbxedit(["lint", "--write-baseline", baseline.path, "--project", project.xcodeproj.path]).status, 0)
        XCTAssertTrue(try String(contentsOf: baseline, encoding: .utf8).contains("{ \"rule\": \"S5\", \"object\": \"archiveVersion\" }"))
        let result = try pbxedit(["lint", "--strict", "--baseline", baseline.path, "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, "0 errors, 0 warnings, 1 baselined\n")
    }

    func testLintNeverEditsTheProjectEvenWhenWritingABaseline() throws {
        let project = try TemporaryProject(try LintCommandTests.twoM3OneS5())
        let before = try project.bytes()
        _ = try pbxedit(["lint", "--write-baseline", baselineURL(project).path, "--project", project.xcodeproj.path])
        XCTAssertEqual(try project.bytes(), before)
    }
}
