import Foundation
import XCTest

/// Tasks 4.3 and 6.1: what `.pbxedit.yml` does to `pbxedit add`, end to end.
final class ConfigAddTests: XCTestCase {
    // Spec: First file in a new target directory; Precedence (provenance in text and JSON).
    func testARuleSuppliesTheTargetWhereInferenceHasNothingAndIsAttributed() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("Tools/Build.swift")
        let before = try project.bytes()
        let refused = try pbxedit(["add", "Tools/Build.swift"], in: project.root)
        XCTAssertEqual(refused.status, 1, refused.stderr)
        XCTAssertTrue(refused.stderr.contains("--target"), refused.stderr)
        XCTAssertEqual(try project.bytes(), before)
        try project.write(".pbxedit.yml", "rules:\n  - match: \"Tools/**\"\n    targets: [AppKit]\n")
        let result = try pbxedit(["add", "--json", "Tools/Build.swift"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        let object = try jsonObject(result)
        XCTAssertEqual(object["modified"] as? Bool, true)
        let decisions = try XCTUnwrap(object["decisions"] as? [[String: Any]])
        let targets = try XCTUnwrap(decisions.first { $0["attribute"] as? String == "targets" })
        XCTAssertEqual(targets["value"] as? String, "AppKit")
        XCTAssertEqual(targets["source"] as? NSDictionary, ["kind": "config", "siblings": NSNull(), "directory": NSNull(), "rule": 1, "glob": "Tools/**"] as NSDictionary)
        let filters = try XCTUnwrap(decisions.first { $0["attribute"] as? String == "platformFilters" })
        XCTAssertEqual(filters["source"] as? NSDictionary, ["kind": "inferred", "siblings": 0, "directory": "Tools", "rule": NSNull(), "glob": NSNull()] as NSDictionary)
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual((results[0]["memberships"] as? [[String: Any]])?.compactMap { ($0["target"] as? [String: String])?["name"] }, ["AppKit"])
        XCTAssertEqual(try pbxedit(["lint"], in: project.root).status, 0)
        // The same, in text, from a fresh copy.
        let fresh = try TemporaryProject(fixture: "add/app.pbxproj")
        try fresh.touch("Tools/Build.swift")
        try fresh.write(".pbxedit.yml", "rules:\n  - match: \"Tools/**\"\n    targets: [AppKit]\n")
        let text = try pbxedit(["add", "Tools/Build.swift"], in: fresh.root)
        XCTAssertEqual(text.status, 0, text.stderr)
        XCTAssertTrue(text.stdout.contains("  targets: AppKit (config, rule 1 \"Tools/**\")\n"), text.stdout)
        XCTAssertTrue(text.stdout.contains("  platformFilters: AppKit: none (inferred, no siblings in Tools)\n"), text.stdout)
    }

    // Spec: Configuration resolves disagreement; Attributes come from different rules; Explicitly no filter; Flag wins.
    func testConfiguredAttributesResolveDisagreementsAndFlagsStillWin() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Mixed/New.swift")
        try project.touch("App/Filtered/New.swift")
        try project.touch("App/Views/Bar.swift")
        try project.write(".pbxedit.yml", """
            rules:
              - match: "App/tvOS/**"
                platformFilters: [tvos]
              - match: "App/Mixed/**"
                targets: [App]
              - match: "App/Filtered/**"
                platformFilters: []
              - match: "App/Views/**"
                targets: [App]

            """)
        let mixed = try pbxedit(["add", "App/Mixed/New.swift"], in: project.root)
        XCTAssertEqual(mixed.status, 0, mixed.stderr)
        XCTAssertTrue(mixed.stdout.contains("  targets: App (config, rule 2 \"App/Mixed/**\")\n"), mixed.stdout)
        XCTAssertTrue(mixed.stdout.contains("  platformFilters: App: none (inferred, 1 sibling in App/Mixed)\n"), mixed.stdout)
        XCTAssertFalse(mixed.stdout.contains("note:"), "nothing was inferred for targets, so no note: \(mixed.stdout)")
        let filtered = try pbxedit(["add", "App/Filtered/New.swift"], in: project.root)
        XCTAssertEqual(filtered.status, 0, filtered.stderr)
        XCTAssertTrue(filtered.stdout.contains("  targets: App (inferred, 2 siblings in App/Filtered)\n"), filtered.stdout)
        XCTAssertTrue(filtered.stdout.contains("  platformFilters: App: none (config, rule 3 \"App/Filtered/**\")\n"), filtered.stdout)
        let flagged = try pbxedit(["add", "App/Views/Bar.swift", "--target", "AppTests"], in: project.root)
        XCTAssertEqual(flagged.status, 0, flagged.stderr)
        XCTAssertTrue(flagged.stdout.contains("  targets: AppTests (flag)\n"), flagged.stdout)
        XCTAssertTrue(flagged.stdout.contains("  membership: AppTests (Sources)\n"), flagged.stdout)
        let query = try pbxedit(["query", "App/Filtered/New.swift"], in: project.root)
        XCTAssertTrue(query.stdout.contains("target: App, phase: Sources, build file: "), query.stdout)
        XCTAssertFalse(query.stdout.contains("platforms:"), "explicitly no filter: \(query.stdout)")
        XCTAssertEqual(try pbxedit(["lint"], in: project.root).status, 0)
        // A dry run shows the configured decision before anything is written.
        try project.touch("App/Mixed/Other.swift")
        let before = try project.bytes()
        let dry = try pbxedit(["add", "--dry-run", "App/Mixed/Other.swift"], in: project.root)
        XCTAssertEqual(dry.status, 0, dry.stderr)
        XCTAssertTrue(dry.stdout.contains("  targets: App (config, rule 2 \"App/Mixed/**\")\n"), dry.stdout)
        XCTAssertEqual(try project.bytes(), before)
    }

    // Spec: An M3 exemption governs add — Exempt path (task 6.1; design D6).
    func testAnM3ExemptPathGetsNoGroupChildAndASourceRootReference() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("Tools/Build.swift")
        try project.write(".pbxedit.yml", "rules:\n  - match: \"Tools/**\"\n    targets: [AppKit]\nlint:\n  exempt:\n    M3: [\"Tools/**\"]\n")
        let before = String(decoding: try project.bytes(), as: UTF8.self)
        let result = try pbxedit(["add", "--json", "Tools/Build.swift"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        let object = try jsonObject(result)
        XCTAssertEqual(object["modified"] as? Bool, true)
        let changes = try XCTUnwrap(object["changes"] as? [[String: Any]])
        XCTAssertEqual(changes.map { $0["action"] as? String }, ["createdFileReference", "createdBuildFile", "addedPhaseEntry"], "no group created or modified")
        let decisions = try XCTUnwrap(object["decisions"] as? [[String: Any]])
        let location = try XCTUnwrap(decisions.first { $0["attribute"] as? String == "location" })
        XCTAssertEqual(location["source"] as? NSDictionary, ["kind": "exemption", "siblings": NSNull(), "directory": NSNull(), "rule": NSNull(), "glob": "Tools/**"] as NSDictionary)
        XCTAssertEqual(location["value"] as? String, "path = Tools/Build.swift; sourceTree = SOURCE_ROOT; in no group")
        let after = String(decoding: try project.bytes(), as: UTF8.self)
        XCTAssertTrue(after.contains("name = Build.swift; path = Tools/Build.swift; sourceTree = SOURCE_ROOT;"), after)
        let diff = lineDiffLines(before, after)
        XCTAssertFalse(diff.contains { $0.contains("isa = PBXGroup") || $0.contains("children") }, "no group line changed: \(diff)")
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual((results[0]["groups"] as? [String])?.count, 0)
        XCTAssertEqual((results[0]["memberships"] as? [[String: Any]])?.count, 1)
        // lint with the same configuration is clean; without the exemption, the orphan is the only finding.
        XCTAssertEqual(try pbxedit(["lint"], in: project.root).status, 0)
        try project.write("plain.yml", "{}\n")
        let plain = try pbxedit(["lint", "--config", "plain.yml"], in: project.root)
        XCTAssertEqual(plain.status, 1, plain.stderr)
        XCTAssertTrue(plain.stdout.hasPrefix("error M3 "), plain.stdout)
        XCTAssertTrue(plain.stdout.hasSuffix("1 error, 0 warnings\n"), plain.stdout)
        // The text form names the exemption, and a re-add reuses the ungrouped reference without grouping it.
        let again = try pbxedit(["add", "Tools/Build.swift"], in: project.root)
        XCTAssertEqual(again.status, 0, again.stderr)
        XCTAssertTrue(again.stdout.contains("  location: in no group (config, exempt M3 \"Tools/**\")\n"), again.stdout)
        XCTAssertFalse(again.stdout.contains("added child"), again.stdout)
        XCTAssertTrue(again.stdout.hasSuffix("project.pbxproj: not modified\n"), again.stdout)
        let plutil = Process()
        plutil.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        plutil.arguments = ["-lint", project.pbxproj.path]
        try plutil.run()
        plutil.waitUntilExit()
        XCTAssertEqual(plutil.terminationStatus, 0)
    }

    private func lineDiffLines(_ before: String, _ after: String) -> [String] {
        let old = Set(before.split(separator: "\n"))
        return after.split(separator: "\n").filter { !old.contains($0) }.map(String.init)
    }
}
