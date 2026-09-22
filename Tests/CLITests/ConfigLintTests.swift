import Foundation
import XCTest

/// Tasks 5.1 and 5.2: what `.pbxedit.yml` does to `pbxedit lint` — the
/// baseline default and path exemptions.
final class ConfigLintTests: XCTestCase {
    // Spec: Lint baseline default — Configured baseline.
    func testTheConfiguredBaselineIsTheDefaultAndNoBaselineDisablesIt() throws {
        let project = try TemporaryProject(try LintCommandTests.twoM3OneS5())
        XCTAssertEqual(try pbxedit(["lint", "--write-baseline", ".pbxedit-baseline.json"], in: project.root).status, 0)
        let plain = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(plain.status, 1, "without a configuration the baseline is not used: \(plain.stdout)")
        try project.write(".pbxedit.yml", "lint:\n  baseline: .pbxedit-baseline.json\n")
        let configured = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(configured.status, 0, configured.stderr)
        XCTAssertEqual(configured.stdout, "0 errors, 0 warnings, 3 baselined\n")
        // The path is relative to the configuration's directory, not the current one.
        let fromBelow = try pbxedit(["lint", "--project", "../App.xcodeproj"], in: project.xcodeproj)
        XCTAssertEqual(fromBelow.status, 0, fromBelow.stderr)
        XCTAssertEqual(fromBelow.stdout, "0 errors, 0 warnings, 3 baselined\n")
        let disabled = try pbxedit(["lint", "--no-baseline"], in: project.root)
        XCTAssertEqual(disabled.status, 1, disabled.stderr)
        XCTAssertTrue(disabled.stdout.hasSuffix("2 errors, 1 warning\n"), disabled.stdout)
        let json = try pbxedit(["lint", "--json"], in: project.root)
        let object = try jsonObject(json)
        XCTAssertEqual(object["summary"] as? [String: Int], ["errors": 0, "warnings": 0, "baselined": 3, "resolved": 0, "exempt": 0])
        // An explicit --baseline wins; --write-baseline does not read the configured one.
        try project.write("other.json", "{ \"schemaVersion\": 1, \"entries\": [] }\n")
        let explicit = try pbxedit(["lint", "--baseline", "other.json"], in: project.root)
        XCTAssertEqual(explicit.status, 1, explicit.stdout)
        XCTAssertTrue(explicit.stdout.hasSuffix("2 errors, 1 warning\n"), explicit.stdout)
        let rewritten = try pbxedit(["lint", "--write-baseline", "other.json"], in: project.root)
        XCTAssertEqual(rewritten.status, 0, rewritten.stderr)
        XCTAssertTrue(rewritten.stdout.contains("2 errors, 1 warning\n"), rewritten.stdout)
        XCTAssertTrue(rewritten.stdout.contains("(3 entries)"), rewritten.stdout)
        // A configured baseline that does not exist is the same usage error as --baseline.
        try project.write(".pbxedit.yml", "lint:\n  baseline: missing.json\n")
        let missing = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(missing.status, 2)
        XCTAssertTrue(missing.stderr.contains("missing.json"), missing.stderr)
        XCTAssertTrue(missing.stderr.contains("--write-baseline"), missing.stderr)
        XCTAssertEqual(try pbxedit(["lint", "--no-baseline"], in: project.root).status, 1, "--no-baseline never reads it")
    }

    // Spec: Path exemptions — Orphans under a directory stay out of groups.
    func testAnExemptFindingIsSuppressedAndCounted() throws {
        let project = try TemporaryProject(fixture: "rules/m3-orphan.pbxproj")
        try project.write(".pbxedit.yml", "lint:\n  exempt:\n    M3: [\"AppTests/Views/**\"]\n")
        let result = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, "0 errors, 0 warnings, 1 exempt\n")
        let json = try pbxedit(["lint", "--json"], in: project.root)
        let object = try jsonObject(json)
        XCTAssertEqual((object["findings"] as? [Any])?.count, 0)
        XCTAssertEqual(object["summary"] as? [String: Int], ["errors": 0, "warnings": 0, "baselined": 0, "resolved": 0, "exempt": 1])
        // A non-matching glob leaves the finding reported, and the count at zero is not printed.
        try project.write(".pbxedit.yml", "lint:\n  exempt:\n    M3: [\"App/**\"]\n")
        let kept = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(kept.status, 1)
        XCTAssertTrue(kept.stdout.hasPrefix("error M3 AB12 AppTests/Views/FooTests.swift: "), kept.stdout)
        XCTAssertTrue(kept.stdout.hasSuffix("1 error, 0 warnings\n"), kept.stdout)
        // Exemptions apply before the baseline, and a written baseline omits exempt findings.
        let mixed = try TemporaryProject(try LintCommandTests.twoM3OneS5())
        try mixed.write(".pbxedit.yml", "lint:\n  baseline: .pbxedit-baseline.json\n  exempt:\n    M3: [\"AppTests/**\"]\n")
        let written = try pbxedit(["lint", "--write-baseline", ".pbxedit-baseline.json"], in: mixed.root)
        XCTAssertEqual(written.status, 0, written.stderr)
        XCTAssertTrue(written.stdout.contains("1 error, 1 warning, 1 exempt\n"), written.stdout)
        XCTAssertTrue(written.stdout.contains("(2 entries)"), written.stdout)
        XCTAssertFalse(try String(contentsOf: mixed.root.appendingPathComponent(".pbxedit-baseline.json"), encoding: .utf8).contains("AB12"))
        let checked = try pbxedit(["lint"], in: mixed.root)
        XCTAssertEqual(checked.status, 0, checked.stderr)
        XCTAssertEqual(checked.stdout, "0 errors, 0 warnings, 2 baselined, 1 exempt\n")
    }

    func testExemptionsReachTheDiskRulesAndM6() throws {
        let project = try TemporaryProject(fixture: "rules/m3-orphan.pbxproj")
        try project.write(".pbxedit.yml", "lint:\n  exempt:\n    M3: [\"**\"]\n    D1: [\"AppTests/**\"]\n")
        let result = try pbxedit(["lint", "--disk"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, "0 errors, 0 warnings, 2 exempt\n")
        let shared = try TemporaryProject(fixture: "rules/m6-wrong-target.pbxproj")
        let before = try pbxedit(["lint", "--strict"], in: shared.root)
        XCTAssertEqual(before.status, 1, before.stdout)
        let m6Line = try XCTUnwrap(before.stdout.split(separator: "\n").first { $0.hasPrefix("warning M6 ") })
        let subject = try XCTUnwrap(m6Line.split(separator: " ").dropFirst(3).first.map(String.init))
        let path = subject.hasSuffix(":") ? String(subject.dropLast()) : subject
        try shared.write(".pbxedit.yml", "lint:\n  exempt:\n    M6: [\"\(path)\"]\n")
        let after = try pbxedit(["lint", "--strict"], in: shared.root)
        XCTAssertEqual(after.status, 0, after.stdout)
        XCTAssertTrue(after.stdout.hasSuffix(" exempt\n"), after.stdout)
    }
}
