import Foundation
import XCTest

/// merge-command tasks 8.2–8.3: `pbxedit merge` end to end, against the
/// built binary and the committed fixtures under `Tests/Fixtures/merge/`.
final class MergeCommandTests: XCTestCase {
    static let jsonKeys: Set<String> = [
        "schemaVersion", "status", "modified", "dryRun", "output", "inputs", "units", "hunks", "checks", "owed", "findings", "template",
        "diff", "error",
    ]

    /// A source root holding the three inputs of `scenario` as `b.pbxproj`,
    /// `o.pbxproj` and `t.pbxproj`, and — unless `project` is false — an
    /// `App.xcodeproj` whose `project.pbxproj` is ours.
    private func workspace(_ scenario: String, project: Bool = true) throws -> TemporaryProject {
        let ours = try Fixtures.load("merge/\(scenario)/ours.pbxproj")
        let workspace = try TemporaryProject(ours)
        if !project { try FileManager.default.removeItem(at: workspace.xcodeproj) }
        for (name, file) in [("b", "base"), ("o", "ours"), ("t", "theirs")] {
            try Data(try Fixtures.load("merge/\(scenario)/\(file).pbxproj")).write(to: workspace.root.appendingPathComponent("\(name).pbxproj"))
        }
        return workspace
    }

    private func inputs(_ workspace: TemporaryProject) throws -> [[UInt8]] {
        try ["b", "o", "t"].map { Array(try Data(contentsOf: workspace.root.appendingPathComponent("\($0).pbxproj"))) }
    }

    private func entries(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    // Spec: Default output is the project file.
    func testTheDefaultOutputIsTheProjectFile() throws {
        let workspace = try workspace("both-add")
        let before = try inputs(workspace)
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--project", "App.xcodeproj"], in: workspace.root)
        XCTAssertEqual(result.status, 0, result.stdout + result.stderr)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: modified\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("(replayed): App/Services/New.swift"), result.stdout)
        let merged = String(decoding: try workspace.bytes(), as: UTF8.self)
        XCTAssertTrue(merged.contains("/* New.swift in Sources */") && merged.contains("/* Bar.swift in Sources */"))
        XCTAssertTrue(merged.contains("platformFilter = ios;"))
        XCTAssertEqual(try inputs(workspace), before, "the inputs are only read")
        XCTAssertEqual(try entries(workspace.root), ["App.xcodeproj", "b.pbxproj", "o.pbxproj", "t.pbxproj"])
        XCTAssertEqual(try workspace.leftovers(), [])
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: workspace.root)
        XCTAssertEqual(lint.status, 0, lint.stdout)
    }

    func testTheProjectIsFoundInTheCurrentDirectory() throws {
        let workspace = try workspace("rename")
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 0, result.stdout + result.stderr)
        XCTAssertTrue(String(decoding: try workspace.bytes(), as: UTF8.self).contains("path = Foo.swift"))
    }

    // Spec: Explicit output.
    func testAnExplicitOutput() throws {
        let workspace = try workspace("both-add", project: false)
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--output", "merged.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 0, result.stdout + result.stderr)
        XCTAssertTrue(result.stdout.hasSuffix("merged.pbxproj: modified\n"), result.stdout)
        let merged = String(decoding: try Data(contentsOf: workspace.root.appendingPathComponent("merged.pbxproj")), as: UTF8.self)
        XCTAssertTrue(merged.contains("/* New.swift in Sources */"))
    }

    // Spec: Nowhere to write.
    func testNowhereToWrite() throws {
        let workspace = try workspace("both-add", project: false)
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("--output") && result.stderr.contains("--project"), result.stderr)
        XCTAssertEqual(try entries(workspace.root), ["b.pbxproj", "o.pbxproj", "t.pbxproj"])
    }

    /// Review finding: a broken `.pbxedit.yml` is reported as itself, not
    /// as nowhere to write the merge.
    func testABrokenConfigurationIsNotNowhereToWrite() throws {
        let workspace = try workspace("both-add")
        try workspace.write(".pbxedit.yml", "lint: [\n")
        let before = try workspace.bytes()
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 2)
        XCTAssertFalse(result.stderr.contains("nowhere to write"), result.stderr)
        XCTAssertTrue(result.stderr.contains(".pbxedit.yml"), result.stderr)
        XCTAssertEqual(try workspace.bytes(), before)
    }

    /// Design D12: an explicit `--config` binds its paths to a project's
    /// source root, so with `--output` and no project to find it is refused,
    /// and the error says why rather than only "pass --project".
    func testAnExplicitConfigurationNeedsAProjectEvenWithAnOutput() throws {
        let workspace = try workspace("both-add", project: false)
        try workspace.write("ci.yml", "lint:\n  exempt:\n    M3: [\"App/**\"]\n")
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--output", "merged.pbxproj", "--config", "ci.yml"],
                                 in: workspace.root)
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains("--config binds its paths to a project's source root"), result.stderr)
        XCTAssertEqual(try entries(workspace.root), ["b.pbxproj", "ci.yml", "o.pbxproj", "t.pbxproj"])
    }

    func testAnUnreadableInputIsAUsageError() throws {
        let workspace = try workspace("both-add")
        let before = try workspace.bytes()
        let result = try pbxedit(["merge", "b.pbxproj", "missing.pbxproj", "t.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.stderr.contains("missing.pbxproj"), result.stderr)
        XCTAssertEqual(try workspace.bytes(), before)
    }

    // Exit codes 0, 1, 2 and 3 on the fixtures.
    func testExitCodes() throws {
        for (scenario, code) in [("both-add", Int32(0)), ("conflicting-setting", 3), ("settings-residual", 3), ("theirs-adds-target", 2)] {
            let workspace = try workspace(scenario)
            let before = try workspace.bytes()
            let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
            XCTAssertEqual(result.status, code, "\(scenario): \(result.stdout)\(result.stderr)")
            if code != 0 {
                XCTAssertEqual(try workspace.bytes(), before, "\(scenario): nothing written")
                XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: not modified\n"), "\(scenario): \(result.stdout)")
            }
        }
        let adds = try workspace("theirs-adds-target")
        let unsupported = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: adds.root)
        XCTAssertTrue(unsupported.stderr.contains("Widget"), unsupported.stderr)

        // Exit 1: decided either way, check F fails; nothing is written.
        let workspace = try workspace("phase-removed")
        let before = try workspace.bytes()
        let open = try pbxedit(["merge", "--json", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        XCTAssertEqual(open.status, 3)
        try decide(open, hunks: "theirs", into: workspace.root.appendingPathComponent("decisions.json"))
        let failed = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--decisions", "decisions.json"], in: workspace.root)
        XCTAssertEqual(failed.status, 1, failed.stdout + failed.stderr)
        XCTAssertTrue(failed.stdout.contains("check F"), failed.stdout)
        XCTAssertTrue(failed.stdout.contains("AA0000000000000000000270"), failed.stdout)
        XCTAssertTrue(failed.stdout.hasSuffix("project.pbxproj: not modified\n"), failed.stdout)
        XCTAssertEqual(try workspace.bytes(), before)
    }

    // Spec: Dry run.
    func testDryRun() throws {
        let workspace = try workspace("both-add")
        let before = try workspace.bytes()
        let result = try pbxedit(["merge", "--dry-run", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 0, result.stdout + result.stderr)
        XCTAssertTrue(result.stdout.contains("\n+\t\t"), "a unified diff: \(result.stdout)")
        XCTAssertTrue(result.stdout.contains("New.swift"))
        XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: not modified (dry run)\n"), result.stdout)
        XCTAssertEqual(try workspace.bytes(), before)
        let conflicting = try self.workspace("conflicting-setting")
        let decisions = try pbxedit(["merge", "--dry-run", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: conflicting.root)
        XCTAssertEqual(decisions.status, 3, "the code the real run would have")
    }

    // Spec: JSON on decisions needed.
    func testJSONOnDecisionsNeeded() throws {
        let workspace = try workspace("conflicting-setting")
        let result = try pbxedit(["merge", "--json", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 3, result.stderr)
        let object = try jsonObject(result)
        XCTAssertEqual(Set(object.keys), MergeCommandTests.jsonKeys)
        XCTAssertEqual(object["status"] as? String, "decisionsNeeded")
        XCTAssertEqual(object["modified"] as? Bool, false)
        XCTAssertEqual(object["dryRun"] as? Bool, false)
        XCTAssertTrue(object["diff"] is NSNull)
        XCTAssertTrue(object["error"] is NSNull)
        let hunks = try XCTUnwrap(object["hunks"] as? [[String: Any]])
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0]["choices"] as? [String], ["ours", "theirs"])
        XCTAssertTrue(hunks[0]["decision"] is NSNull)
        let governed = try XCTUnwrap(hunks[0]["governed"] as? [[String: Any]])
        XCTAssertEqual(governed.first?["object"] as? String, "1000000000000000000000A1")
        XCTAssertEqual(governed.first?["keyPath"] as? String, "buildSettings.SWIFT_VERSION")
        XCTAssertEqual(governed.first?["base"] as? String, "6.0")
        XCTAssertEqual(governed.first?["ours"] as? String, "5.10")
        XCTAssertEqual(governed.first?["theirs"] as? String, "6.2")
        let key = try XCTUnwrap(hunks[0]["key"] as? String)
        let template = try XCTUnwrap(object["template"] as? [String: Any])
        let templateHunks = try XCTUnwrap(template["hunks"] as? [String: Any])
        XCTAssertEqual(Array(templateHunks.keys), [key])
        XCTAssertTrue(templateHunks[key] is NSNull)
        let inputs = try XCTUnwrap(template["inputs"] as? [String: String])
        XCTAssertEqual(inputs.keys.sorted(), ["base", "ours", "theirs"])
        XCTAssertEqual(inputs["base"]?.count, 64)
        let checks = try XCTUnwrap(object["checks"] as? [Any])
        XCTAssertEqual(checks.count, 0, "no check runs before the decisions")
    }

    func testTheTextReportCarriesTheTemplate() throws {
        let workspace = try workspace("conflicting-setting")
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 3)
        XCTAssertTrue(result.stdout.contains("1000000000000000000000A1 buildSettings.SWIFT_VERSION: base 6.0, ours 5.10, theirs 6.2"), result.stdout)
        XCTAssertTrue(result.stdout.contains("```json\n{"), result.stdout)
    }

    // Spec: Template and re-run.
    func testDecisionsRoundTripThroughAFile() throws {
        let workspace = try workspace("conflicting-setting")
        let open = try pbxedit(["merge", "--json", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        try decide(open, hunks: "theirs", into: workspace.root.appendingPathComponent("decisions.json"))
        let result = try pbxedit(["merge", "--json", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--decisions", "decisions.json"], in: workspace.root)
        XCTAssertEqual(result.status, 0, result.stdout + result.stderr)
        let object = try jsonObject(result)
        XCTAssertEqual(object["status"] as? String, "merged")
        XCTAssertEqual(object["modified"] as? Bool, true)
        XCTAssertEqual((object["hunks"] as? [[String: Any]])?.first?["decision"] as? String, "theirs")
        XCTAssertEqual((object["checks"] as? [[String: Any]])?.map { $0["check"] as? String }, ["C", "F", "D", "E", "B", "A"])
        XCTAssertTrue(String(decoding: try workspace.bytes(), as: UTF8.self).contains("SWIFT_VERSION = 6.2;"))

        // theirs-membership: exit 0, settings owed.
        let residual = try self.workspace("settings-residual")
        let asked = try pbxedit(["merge", "--json", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: residual.root)
        try decide(asked, units: "theirs-membership", into: residual.root.appendingPathComponent("decisions.json"))
        let owed = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--decisions", "decisions.json"], in: residual.root)
        XCTAssertEqual(owed.status, 0, owed.stdout + owed.stderr)
        XCTAssertTrue(owed.stdout.contains("owed: AppKit/Extra.h"), owed.stdout)
    }

    // Spec: Two decided hunks govern one array (issue #12): the issue's three rows, through the binary.
    func testTwoDecidedHunksOverOneArray() throws {
        for (head, tail, regions) in [("ours", "theirs", "de en Base es"), ("theirs", "theirs", "fr en Base es"), ("theirs", "ours", "fr en Base it")] {
            let workspace = try workspace("shared-array")
            let open = try pbxedit(["merge", "--json", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
            XCTAssertEqual(open.status, 3, open.stdout + open.stderr)
            var template = try XCTUnwrap(try jsonObject(open)["template"] as? [String: Any])
            var choices: [String: String] = [:]
            for hunk in try XCTUnwrap(try jsonObject(open)["hunks"] as? [[String: Any]]) {
                let key = try XCTUnwrap(hunk["key"] as? String)
                let ours = hunk["ours"] as? String ?? ""
                choices[key] = ours.contains("de,") ? head : ours.contains("it,") ? tail : "ours"
            }
            XCTAssertEqual(choices.count, 3)
            template["hunks"] = choices
            try JSONSerialization.data(withJSONObject: template).write(to: workspace.root.appendingPathComponent("decisions.json"))
            let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--decisions", "decisions.json"], in: workspace.root)
            XCTAssertEqual(result.status, 0, "\(head)/\(tail): " + result.stdout + result.stderr)
            let expected = "knownRegions = (\n" + regions.split(separator: " ").map { "\t\t\t\t\($0),\n" }.joined() + "\t\t\t);"
            XCTAssertTrue(String(decoding: try workspace.bytes(), as: UTF8.self).contains(expected), "\(head)/\(tail)")
        }
    }

    // Spec: Different insertions into one unordered array (issue #13).
    func testDifferentInsertionsIntoOneUnorderedArrayOfferBoth() throws {
        let workspace = try workspace("both-regions")
        let open = try pbxedit(["merge", "--json", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        XCTAssertEqual(open.status, 3, open.stdout + open.stderr)
        let hunks = try XCTUnwrap(try jsonObject(open)["hunks"] as? [[String: Any]])
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks.first?["choices"] as? [String], ["ours", "theirs", "both"])
        let url = workspace.root.appendingPathComponent("decisions.json")
        try decide(open, hunks: "both", into: url)
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--decisions", "decisions.json"], in: workspace.root)
        XCTAssertEqual(result.status, 0, result.stdout + result.stderr)
        let expected = "knownRegions = (\n" + ["de", "fr", "en", "Base"].map { "\t\t\t\t\($0),\n" }.joined() + "\t\t\t);"
        XCTAssertTrue(String(decoding: try workspace.bytes(), as: UTF8.self).contains(expected))
    }

    // Spec: Stale decisions; Unknown key or refused choice.
    func testStaleAndUnknownDecisions() throws {
        let workspace = try workspace("conflicting-setting")
        let before = try workspace.bytes()
        let open = try pbxedit(["merge", "--json", "b.pbxproj", "o.pbxproj", "t.pbxproj"], in: workspace.root)
        let url = workspace.root.appendingPathComponent("decisions.json")
        try decide(open, hunks: "theirs", into: url)
        let other = try pbxedit(["merge", "b.pbxproj", "t.pbxproj", "o.pbxproj", "--decisions", "decisions.json"], in: workspace.root)
        XCTAssertEqual(other.status, 2)
        XCTAssertTrue(other.stderr.contains("other inputs"), other.stderr)
        try decide(open, hunks: "both", into: url)
        let refused = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--decisions", "decisions.json"], in: workspace.root)
        XCTAssertEqual(refused.status, 2)
        XCTAssertTrue(refused.stderr.contains("both is not offered"), refused.stderr)
        try Data("{\"inputs\": 1}".utf8).write(to: url)
        let malformed = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--decisions", "decisions.json"], in: workspace.root)
        XCTAssertEqual(malformed.status, 2)
        XCTAssertEqual(try workspace.bytes(), before)
    }

    // The `git merge-file` convention: the output is ours itself.
    func testTheOutputMayBeOurs() throws {
        let workspace = try workspace("both-add", project: false)
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "t.pbxproj", "--output", "o.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 0, result.stdout + result.stderr)
        let merged = String(decoding: try Data(contentsOf: workspace.root.appendingPathComponent("o.pbxproj")), as: UTF8.self)
        XCTAssertTrue(merged.contains("/* New.swift in Sources */"))
    }

    // Spec: Nothing to change.
    func testNothingToMerge() throws {
        let workspace = try workspace("both-add")
        let before = try workspace.bytes()
        let result = try pbxedit(["merge", "b.pbxproj", "o.pbxproj", "o.pbxproj"], in: workspace.root)
        XCTAssertEqual(result.status, 0, result.stdout + result.stderr)
        XCTAssertTrue(result.stdout.contains("nothing to merge"), result.stdout)
        XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: not modified\n"), result.stdout)
        XCTAssertEqual(try workspace.bytes(), before)
    }

    func testHelpListsMergeAndExitCodeThree() throws {
        let help = try pbxedit(["--help"])
        XCTAssertEqual(help.status, 0)
        XCTAssertTrue(help.stdout.contains("merge"), help.stdout)
        XCTAssertTrue(help.stdout.contains("3 decisions needed"), help.stdout)
        let mergeHelp = try pbxedit(["merge", "--help"])
        XCTAssertEqual(mergeHelp.status, 0)
        XCTAssertTrue(mergeHelp.stdout.contains("--decisions"), mergeHelp.stdout)
    }

    /// Writes the template of an exit-`3` JSON report with every open unit
    /// and hunk set to the given choice.
    private func decide(_ open: RunResult, units: String? = nil, hunks: String? = nil, into url: URL) throws {
        var template = try XCTUnwrap(try jsonObject(open)["template"] as? [String: Any])
        if let units, let keys = (template["units"] as? [String: Any])?.keys { template["units"] = Dictionary(uniqueKeysWithValues: keys.map { ($0, units) }) }
        if let hunks, let keys = (template["hunks"] as? [String: Any])?.keys { template["hunks"] = Dictionary(uniqueKeysWithValues: keys.map { ($0, hunks) }) }
        try JSONSerialization.data(withJSONObject: template).write(to: url)
    }
}
