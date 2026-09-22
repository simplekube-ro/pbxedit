import Foundation
import XCTest
import PBXSyntax
import PBXModel

/// Tasks 6.1, 6.2 and 7.1: `pbxedit lint --fix` end to end, against the
/// built binary, on `Tests/Fixtures/repair/app.pbxproj` (19 errors: 10
/// repairable, 5 of a fixable rule that are not, 4 S2 of which 3 vanish with
/// the objects they were on).
final class LintFixCommandTests: XCTestCase {
    private static let jsonKeys: Set<String> = [
        "schemaVersion", "project", "modified", "dryRun", "repaired", "remaining", "resolved", "summary", "diff", "error",
    ]
    private static let deleted: Set<String> = ["BB0000000000000000000404", "BB0000000000000000000405"]

    // Spec: Reporting and exit code — Partial repair; Idempotence — Second run.
    func testTheReportListsRepairsThenRemainingFindingsWithReasonsAndTheSecondRunWritesNothing() throws {
        let project = try TemporaryProject(fixture: "repair/app.pbxproj")
        let before = try project.bytes()
        let result = try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, "errors remain: \(result.stderr)")
        XCTAssertEqual(result.stderr, "")
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let repaired = lines.filter { $0.hasPrefix("repaired ") }
        XCTAssertEqual(repaired.count, 10, result.stdout)
        XCTAssertEqual(repaired.map { $0.split(separator: " ")[1] }, ["M2", "M2", "M1", "M1", "M3", "M3", "M3", "M3", "M3", "M3"])
        XCTAssertTrue(result.stdout.hasPrefix("repaired M2 BB0000000000000000000405: build file BB0000000000000000000405 in build phase CC0000000000000000000001 (Sources) has a 'fileRef' AA0000000000000000000998 that does not resolve\n  removed phase entry from CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)\n  deleted object BB0000000000000000000405: build file whose file does not resolve\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("repaired M1 BB0000000000000000000400 App/Services/Rate2.swift: build file BB0000000000000000000400 (App/Services/Rate2.swift) is listed in no build phase\n  targets: App (inferred, 3 siblings in App/Services)\n  added phase entry to CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)\n  note: 1 of 3 siblings in App/Services is also a member of AppExtension; pbxedit add App/Services/Rate2.swift --target AppExtension adds it there too\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("repaired M3 AA0000000000000000000406 App/Views/Baz.swift: file reference AA0000000000000000000406 (App/Views/Baz.swift) has no parent group\n  added child to group AA0000000000000000000003: child of group Views (AA0000000000000000000003)\n"), result.stdout)
        // Remaining findings come after every repair, in lint's order, with the reasons beneath the fixable-rule ones.
        let lastRepair = try XCTUnwrap(lines.lastIndex { $0.hasPrefix("repaired ") })
        let firstRemaining = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("error ") })
        XCTAssertGreaterThan(firstRemaining, lastRepair)
        XCTAssertEqual(lines.filter { $0.hasPrefix("error ") }.count, 6, result.stdout)
        XCTAssertTrue(result.stdout.contains("error M1 BB0000000000000000000401 App/Mixed/Mixed3.swift: build file BB0000000000000000000401 (App/Mixed/Mixed3.swift) is listed in no build phase\n  not fixable: the siblings in App/Mixed have no target in common: App (1), AppExtension (1)\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("error M3 AA0000000000000000000410 App/Legacy/Old.swift: file reference AA0000000000000000000410 (App/Legacy/Old.swift) has no parent group\n  not fixable: its <group>-relative path App/Legacy/Old.swift would resolve to App/Legacy/App/Legacy/Old.swift under the group for App/Legacy; pbxedit remove App/Legacy/Old.swift, then pbxedit add App/Legacy/Old.swift, re-spells it\n"), result.stdout)
        XCTAssertEqual(lines[firstRemaining], "error S2 AA0000000000000000000007 : group AA0000000000000000000007 () refers to DEAD0002 in 'children', which does not exist", "errors in lint's order: S2 first")
        XCTAssertTrue(result.stdout.hasSuffix("  not fixable: a child of 2 groups, AA0000000000000000000015 and AA0000000000000000000016; which one is right is a human decision\n6 errors, 0 warnings, 10 repaired, 5 not fixable\nproject.pbxproj: modified\n"), result.stdout)
        XCTAssertNotEqual(try project.bytes(), before)
        XCTAssertEqual(try project.leftovers(), [])
        // What lint says afterwards is what the repair reported as remaining.
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(lint.status, 1)
        XCTAssertTrue(lint.stdout.hasSuffix("6 errors, 0 warnings\n"), lint.stdout)
        let query = try pbxedit(["query", "App/Services/Rate2.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertTrue(query.stdout.contains("target: App, phase: Sources, build file: BB0000000000000000000400"), query.stdout)
        // Second run: nothing to do, nothing written.
        let repairedBytes = try project.bytes()
        let again = try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(again.status, 1)
        XCTAssertTrue(again.stdout.hasSuffix("6 errors, 0 warnings, 0 repaired, 5 not fixable\nproject.pbxproj: not modified\n"), again.stdout)
        XCTAssertEqual(try project.bytes(), repairedBytes)
    }

    // Spec: Dry run — Preview before adoption; the exit code is the real run's.
    func testADryRunPrintsTheReportAndDiffAndWritesNothing() throws {
        let project = try TemporaryProject(fixture: "repair/app.pbxproj")
        let before = try project.bytes()
        let result = try pbxedit(["lint", "--fix", "--dry-run", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, result.stderr)
        XCTAssertTrue(result.stdout.contains("\n6 errors, 0 warnings, 10 repaired, 5 not fixable\n--- a/project.pbxproj\n+++ b/project.pbxproj\n@@ "), result.stdout)
        XCTAssertTrue(result.stdout.contains("\n+\t\t\t\tAA0000000000000000000406 /* Baz.swift */,\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\n-\t\t\t\tDEAD0001 /* Gone.swift in Sources */,\n"), result.stdout)
        XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: not modified (dry run)\n"), result.stdout)
        XCTAssertEqual(try project.bytes(), before)
        XCTAssertEqual(try project.leftovers(), [])
        let json = try pbxedit(["lint", "--fix", "--dry-run", "--json", "--project", "App.xcodeproj"], in: project.root)
        let object = try jsonObject(json)
        XCTAssertEqual(object["modified"] as? Bool, false)
        XCTAssertEqual(object["dryRun"] as? Bool, true)
        XCTAssertTrue((object["diff"] as? String)?.hasPrefix("--- a/project.pbxproj") == true)
        XCTAssertEqual(try project.bytes(), before)
        // A project the repair makes clean exits 0, on the dry run as on the real one.
        let orphan = try TemporaryProject(fixture: "rules/m3-orphan.pbxproj")
        let preview = try pbxedit(["lint", "--fix", "--dry-run", "--project", "App.xcodeproj"], in: orphan.root)
        XCTAssertEqual(preview.status, 0, preview.stdout)
        XCTAssertTrue(preview.stdout.contains("\n0 errors, 0 warnings, 1 repaired, 0 not fixable\n"), preview.stdout)
        XCTAssertEqual(try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: orphan.root).status, 0)
        XCTAssertEqual(try pbxedit(["lint", "--project", "App.xcodeproj"], in: orphan.root).stdout, "0 errors, 0 warnings\n")
    }

    // Spec: Reporting and exit code — Flags that do not go together.
    func testFlagsThatDoNotGoTogetherExitTwo() throws {
        let project = try TemporaryProject(fixture: "repair/app.pbxproj")
        let before = try project.bytes()
        let dryRun = try pbxedit(["lint", "--dry-run", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(dryRun.status, 2)
        XCTAssertEqual(dryRun.stdout, "")
        XCTAssertTrue(dryRun.stderr.contains("--fix"), dryRun.stderr)
        let baseline = try pbxedit(["lint", "--fix", "--write-baseline", "b.json", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(baseline.status, 2)
        XCTAssertEqual(baseline.stdout, "")
        XCTAssertTrue(baseline.stderr.contains("--write-baseline"), baseline.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.root.appendingPathComponent("b.json").path))
        XCTAssertEqual(try project.bytes(), before)
    }

    // Design D8: the JSON shape.
    func testTheJSONShape() throws {
        let project = try TemporaryProject(fixture: "repair/app.pbxproj")
        let result = try pbxedit(["lint", "--fix", "--json", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, result.stderr)
        let object = try jsonObject(result)
        XCTAssertEqual(Set(object.keys), Self.jsonKeys)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["modified"] as? Bool, true)
        XCTAssertEqual(object["dryRun"] as? Bool, false)
        XCTAssertTrue(object["diff"] is NSNull)
        XCTAssertTrue(object["error"] is NSNull)
        let repaired = try XCTUnwrap(object["repaired"] as? [[String: Any]])
        XCTAssertEqual(repaired.count, 10)
        for entry in repaired {
            XCTAssertEqual(Set(entry.keys), ["rule", "severity", "object", "path", "related", "message", "decisions", "changes", "notes"])
        }
        let rate2 = try XCTUnwrap(repaired.first { $0["object"] as? String == "BB0000000000000000000400" })
        XCTAssertEqual((rate2["decisions"] as? [[String: Any]])?.map { $0["attribute"] as? String }, ["targets"])
        XCTAssertEqual((rate2["changes"] as? [[String: Any]])?.map { $0["action"] as? String }, ["addedPhaseEntry"])
        XCTAssertEqual((rate2["notes"] as? [String])?.count, 1)
        let remaining = try XCTUnwrap(object["remaining"] as? [[String: Any]])
        XCTAssertEqual(remaining.count, 6)
        for entry in remaining {
            XCTAssertEqual(Set(entry.keys), ["rule", "severity", "object", "path", "related", "message", "reason"])
        }
        XCTAssertEqual(remaining.filter { $0["reason"] is NSNull }.count, 1, "only the S2 has no reason")
        XCTAssertEqual(remaining.map { $0["rule"] as? String }, ["S2", "M1", "M1", "M1", "M3", "M3"])
        XCTAssertEqual(object["summary"] as? [String: Int],
                       ["errors": 6, "warnings": 0, "baselined": 0, "resolved": 0, "exempt": 0, "repaired": 10, "notFixable": 5])
        XCTAssertEqual(object["resolved"] as? [[String: String]], [])
    }

    // A clean project is a no-op with the fix vocabulary.
    func testACleanProjectIsANoOp() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let before = try project.bytes()
        let result = try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, "0 errors, 0 warnings, 0 repaired, 0 not fixable\nproject.pbxproj: not modified\n")
        XCTAssertEqual(try project.bytes(), before)
    }

    // An unparseable project is the S1 finding, as for lint.
    func testAnUnparseableProjectIsAnS1() throws {
        let project = try TemporaryProject(fixture: "rules/s1-unterminated-comment.pbxproj")
        let before = try project.bytes()
        let result = try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, result.stderr)
        XCTAssertTrue(result.stdout.hasPrefix("error S1 : the project file does not parse: 3:14"), result.stdout)
        XCTAssertTrue(result.stdout.hasSuffix("1 error, 0 warnings, 0 repaired, 0 not fixable\nproject.pbxproj: not modified\n"), result.stdout)
        XCTAssertEqual(try project.bytes(), before)
    }

    // Task 6.2 — spec: Object census.
    func testTheObjectCensus() throws {
        let project = try TemporaryProject(fixture: "repair/app.pbxproj")
        let before = try Project.load(try project.bytes())
        let result = try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, result.stderr)
        let after = try Project.load(try project.bytes())
        XCTAssertEqual(after.fileReferences.count, before.fileReferences.count)
        XCTAssertLessThanOrEqual(after.buildFiles.count, before.buildFiles.count)
        XCTAssertEqual(after.buildFiles.count, before.buildFiles.count - Self.deleted.count)
        let beforeIDs = Set(before.objects.map(\.id.rawValue))
        let afterIDs = Set(after.objects.map(\.id.rawValue))
        for id in beforeIDs where !afterIDs.contains(id) {
            XCTAssertTrue(Self.deleted.contains(id), "\(id) vanished but was not a dangling build file")
        }
        for id in afterIDs where !beforeIDs.contains(id) {
            XCTAssertEqual(after.object(ObjectID(id))?.isa, "PBXGroup", "\(id) was created but is not a group")
            XCTAssertEqual(id.count, 24)
        }
        XCTAssertEqual(afterIDs.subtracting(beforeIDs).count, 3, "Features, Tools, Generated")
        for reference in before.fileReferences {
            XCTAssertEqual(after.fileReference(reference.id), reference, "\(reference.id) changed")
        }
    }

    // Task 6.2 — spec: `modified` matches the bytes over every invocation.
    func testModifiedMatchesRealityOverEveryScenario() throws {
        let project = try TemporaryProject(fixture: "repair/app.pbxproj")
        try project.write(".pbxedit.yml", "lint:\n  exempt:\n    M3: [\"Tools/Generated/**\"]\n")
        let invocations: [[String]] = [
            ["lint", "--fix", "--dry-run"],
            ["lint", "--dry-run"],
            ["lint", "--fix", "--write-baseline", "b.json"],
            ["lint", "--fix"],
            ["lint", "--fix"],
            ["lint", "--fix", "--strict"],
            ["lint"],
            ["lint", "--fix", "--disk"],
        ]
        var modifiedRuns = 0
        for arguments in invocations {
            let before = try project.bytes()
            let result = try pbxedit(arguments + ["--json", "--project", "App.xcodeproj"], in: project.root)
            let after = try project.bytes()
            XCTAssertTrue([0, 1, 2].contains(result.status), "\(arguments): \(result.stderr)")
            if result.status == 2 {
                XCTAssertEqual(result.stdout, "", "\(arguments)")
                XCTAssertEqual(before, after, "\(arguments): a usage error never writes")
                continue
            }
            let object = try jsonObject(result)
            if arguments.contains("--fix") {
                let modified = try XCTUnwrap(object["modified"] as? Bool, "\(arguments)")
                XCTAssertEqual(modified, before != after, "\(arguments): modified must match the bytes")
                if modified { modifiedRuns += 1 }
            } else {
                XCTAssertEqual(before, after, "\(arguments): lint never edits")
            }
            XCTAssertEqual(try project.leftovers(), [], "\(arguments)")
        }
        XCTAssertEqual(modifiedRuns, 1, "the one real run that had something to do")
    }

    /// Task 9.1: the examples in the change's design.md (Evidence) are real
    /// output. Minted group IDs are random per run, so both sides are masked.
    func testDesignEvidenceExamplesAreRealOutput() throws {
        let project = try TemporaryProject(fixture: "repair/app.pbxproj")
        let fixture = String(decoding: try project.bytes(), as: UTF8.self)
        func masked(_ text: String) -> String {
            var result = ""
            var token = ""
            func flush() {
                if token.count == 24, token.allSatisfy({ "0123456789ABCDEF".contains($0) }), !fixture.contains(token) {
                    result += "<id>"
                } else {
                    result += token
                }
                token = ""
            }
            for character in text {
                if character.isHexDigit, character.isUppercase || character.isNumber { token.append(character) } else { flush(); result.append(character) }
            }
            flush()
            return result
        }
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(lint.status, 1)
        XCTAssertTrue(lint.stdout.hasPrefix("error S2 AA0000000000000000000007 : group AA0000000000000000000007 () refers to DEAD0002 in 'children', which does not exist\n"), lint.stdout)
        XCTAssertTrue(lint.stdout.hasSuffix("\n19 errors, 0 warnings\n"), lint.stdout)
        let report = """
            repaired M2 BB0000000000000000000405: build file BB0000000000000000000405 in build phase CC0000000000000000000001 (Sources) has a 'fileRef' AA0000000000000000000998 that does not resolve
              removed phase entry from CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)
              deleted object BB0000000000000000000405: build file whose file does not resolve
            repaired M2 CC0000000000000000000007: build phase CC0000000000000000000007 (Sources) lists DEAD0001, which is not a build file
              removed phase entry from CC0000000000000000000007: entry DEAD0001 in Sources of AppKit (CC0000000000000000000007)
            repaired M1 BB0000000000000000000400 App/Services/Rate2.swift: build file BB0000000000000000000400 (App/Services/Rate2.swift) is listed in no build phase
              targets: App (inferred, 3 siblings in App/Services)
              added phase entry to CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)
              note: 1 of 3 siblings in App/Services is also a member of AppExtension; pbxedit add App/Services/Rate2.swift --target AppExtension adds it there too
            repaired M1 BB0000000000000000000404: build file BB0000000000000000000404 (AA0000000000000000000999) is listed in no build phase
              deleted object BB0000000000000000000404: build file in no phase whose file does not resolve
            repaired M3 AA0000000000000000000406 App/Views/Baz.swift: file reference AA0000000000000000000406 (App/Views/Baz.swift) has no parent group
              added child to group AA0000000000000000000003: child of group Views (AA0000000000000000000003)
            repaired M3 AA0000000000000000000407 App/Features/A.swift: file reference AA0000000000000000000407 (App/Features/A.swift) has no parent group
              created group 8F6B39B7BDE875EF56E94F57: group Features for App/Features under App (AA0000000000000000000002)
              added child to group 8F6B39B7BDE875EF56E94F57: child of group Features (8F6B39B7BDE875EF56E94F57)
            repaired M3 AA0000000000000000000408 App/Features/C.swift: file reference AA0000000000000000000408 (App/Features/C.swift) has no parent group
              added child to group 8F6B39B7BDE875EF56E94F57: child of group Features (8F6B39B7BDE875EF56E94F57)
            repaired M3 AA0000000000000000000409 App/Features/B.swift: file reference AA0000000000000000000409 (App/Features/B.swift) has no parent group
              added child to group 8F6B39B7BDE875EF56E94F57: child of group Features (8F6B39B7BDE875EF56E94F57)
            repaired M3 AA0000000000000000000411 README.md: file reference AA0000000000000000000411 (README.md) has no parent group
              added child to group AA0000000000000000000001: child of group main group (AA0000000000000000000001)
            repaired M3 AA0000000000000000000413 Tools/Generated/Gen.swift: file reference AA0000000000000000000413 (Tools/Generated/Gen.swift) has no parent group
              created group 142BA5324EEAA0DF4270BB92: group Tools for Tools under main group (AA0000000000000000000001)
              created group B5CD31D1415078315BA05E38: group Generated for Tools/Generated under Tools (142BA5324EEAA0DF4270BB92)
              added child to group B5CD31D1415078315BA05E38: child of group Generated (B5CD31D1415078315BA05E38)
            error S2 AA0000000000000000000007 : group AA0000000000000000000007 () refers to DEAD0002 in 'children', which does not exist
            error M1 BB0000000000000000000401 App/Mixed/Mixed3.swift: build file BB0000000000000000000401 (App/Mixed/Mixed3.swift) is listed in no build phase
              not fixable: the siblings in App/Mixed have no target in common: App (1), AppExtension (1)
            error M1 BB0000000000000000000402 AppTests/Foo/fixture.json: build file BB0000000000000000000402 (AppTests/Foo/fixture.json) is listed in no build phase
              not fixable: no file of the same kind in its directory or any ancestor to infer a target from
            error M1 BB0000000000000000000403 App/Views/Twice.swift: build file BB0000000000000000000403 (App/Views/Twice.swift) is listed in 2 build phases: CC0000000000000000000001, CC0000000000000000000004
              not fixable: listed in 2 build phases; which one is right is a human decision
            error M3 AA0000000000000000000410 App/Legacy/Old.swift: file reference AA0000000000000000000410 (App/Legacy/Old.swift) has no parent group
              not fixable: its <group>-relative path App/Legacy/Old.swift would resolve to App/Legacy/App/Legacy/Old.swift under the group for App/Legacy; pbxedit remove App/Legacy/Old.swift, then pbxedit add App/Legacy/Old.swift, re-spells it
            error M3 AA0000000000000000000412 App/Mixed/Dup.swift: file reference AA0000000000000000000412 (App/Mixed/Dup.swift) has 2 parent groups: AA0000000000000000000015, AA0000000000000000000016
              not fixable: a child of 2 groups, AA0000000000000000000015 and AA0000000000000000000016; which one is right is a human decision
            6 errors, 0 warnings, 10 repaired, 5 not fixable

            """
        let dryRun = try pbxedit(["lint", "--fix", "--dry-run", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(dryRun.status, 1, dryRun.stderr)
        XCTAssertTrue(masked(dryRun.stdout).hasPrefix(masked(report + "--- a/project.pbxproj\n+++ b/project.pbxproj\n@@ ")), dryRun.stdout)
        XCTAssertTrue(dryRun.stdout.hasSuffix("\t\t};\nproject.pbxproj: not modified (dry run)\n"), dryRun.stdout)
        let real = try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(real.status, 1, real.stderr)
        XCTAssertEqual(masked(real.stdout), masked(report + "project.pbxproj: modified\n"))
        let written = try pbxedit(["lint", "--write-baseline", ".pbxedit-baseline.json", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(written.status, 0)
        XCTAssertTrue(written.stdout.hasSuffix("\n6 errors, 0 warnings\nbaseline written: .pbxedit-baseline.json (6 entries)\n"), written.stdout)
        XCTAssertEqual(try pbxedit(["lint", "--baseline", ".pbxedit-baseline.json", "--project", "App.xcodeproj"], in: project.root).stdout,
                       "0 errors, 0 warnings, 6 baselined\n")
    }

    // Task 7.1 — spec: Exemptions and baselines — Exempt path is left alone.
    func testAnExemptOrphanIsNotGrouped() throws {
        let project = try TemporaryProject(fixture: "repair/app.pbxproj")
        try project.write(".pbxedit.yml", "lint:\n  exempt:\n    M3: [\"Tools/Generated/**\"]\n")
        let result = try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, result.stderr)
        XCTAssertFalse(result.stdout.contains("AA0000000000000000000413"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\n6 errors, 0 warnings, 9 repaired, 5 not fixable, 1 exempt\n"), result.stdout)
        let after = try Project.load(try project.bytes())
        XCTAssertEqual(after.parents(of: "AA0000000000000000000413"), [])
        XCTAssertEqual(after.groups(at: "Tools"), [])
        XCTAssertEqual(after.groups(at: "App/Features").count, 1)
    }

    // Task 7.1 — spec: Exemptions and baselines — Baselined damage is repaired.
    func testBaselinedDamageIsRepairedAndReportedAsResolved() throws {
        let project = try TemporaryProject(fixture: "repair/app.pbxproj")
        let baseline = project.root.appendingPathComponent(".pbxedit-baseline.json")
        XCTAssertEqual(try pbxedit(["lint", "--write-baseline", baseline.path, "--project", "App.xcodeproj"], in: project.root).status, 0)
        let baselineBytes = try Data(contentsOf: baseline)
        let result = try pbxedit(["lint", "--fix", "--baseline", baseline.path, "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, "everything that remains is baselined: \(result.stdout)")
        XCTAssertEqual(result.stdout.split(separator: "\n").filter { $0.hasPrefix("repaired ") }.count, 10, result.stdout)
        XCTAssertEqual(result.stdout.split(separator: "\n").filter { $0.hasPrefix("error ") }.count, 0, "the remaining findings are baselined")
        XCTAssertTrue(result.stdout.contains("\nresolved M3 AA0000000000000000000406: no longer reported; remove it from the baseline\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\n0 errors, 0 warnings, 10 repaired, 5 not fixable, 6 baselined, 13 resolved\nbaseline: 13 entries resolved by this repair; rewrite it with --write-baseline \(baseline.path)\nproject.pbxproj: modified\n"), result.stdout)
        XCTAssertEqual(try Data(contentsOf: baseline), baselineBytes, "the baseline file is never modified")
        let json = try pbxedit(["lint", "--fix", "--json", "--baseline", baseline.path, "--project", "App.xcodeproj"], in: project.root)
        let object = try jsonObject(json)
        XCTAssertEqual(object["summary"] as? [String: Int],
                       ["errors": 0, "warnings": 0, "baselined": 6, "resolved": 13, "exempt": 0, "repaired": 0, "notFixable": 5])
        XCTAssertEqual((object["resolved"] as? [[String: String]])?.count, 13)
        // The configured baseline is the default here too, and --no-baseline ignores it.
        let configured = try TemporaryProject(fixture: "repair/app.pbxproj")
        XCTAssertEqual(try pbxedit(["lint", "--write-baseline", ".pbxedit-baseline.json", "--project", "App.xcodeproj"], in: configured.root).status, 0)
        try configured.write(".pbxedit.yml", "lint:\n  baseline: .pbxedit-baseline.json\n")
        let viaConfig = try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: configured.root)
        XCTAssertEqual(viaConfig.status, 0, viaConfig.stdout)
        XCTAssertTrue(viaConfig.stdout.contains(", 6 baselined, 13 resolved\n"), viaConfig.stdout)
        let ignored = try TemporaryProject(fixture: "repair/app.pbxproj")
        XCTAssertEqual(try pbxedit(["lint", "--write-baseline", ".pbxedit-baseline.json", "--project", "App.xcodeproj"], in: ignored.root).status, 0)
        try ignored.write(".pbxedit.yml", "lint:\n  baseline: .pbxedit-baseline.json\n")
        let noBaseline = try pbxedit(["lint", "--fix", "--no-baseline", "--project", "App.xcodeproj"], in: ignored.root)
        XCTAssertEqual(noBaseline.status, 1, noBaseline.stdout)
        XCTAssertTrue(noBaseline.stdout.contains("\n6 errors, 0 warnings, 10 repaired, 5 not fixable\n"), noBaseline.stdout)
    }
}
