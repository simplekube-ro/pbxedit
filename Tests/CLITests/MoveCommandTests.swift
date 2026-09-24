import Foundation
import XCTest

/// Tasks 6.1, 6.2 and 7.1: `pbxedit move` end to end, against the built
/// binary. The destination file is created on disk first, as `git mv` would
/// have left it; the source is never created unless a scenario says so.
final class MoveCommandTests: XCTestCase {
    private static let jsonKeys: Set<String> = [
        "schemaVersion", "modified", "dryRun", "decisions", "changes", "notes", "findings", "error", "diff", "results", "moves",
    ]

    private func project() throws -> TemporaryProject { try TemporaryProject(fixture: "move/app.pbxproj") }

    // Spec: Cross-target move; Identity is preserved — and query and lint agree afterwards.
    func testACrossTargetMoveIsReportedAndQueryAndLintAgree() throws {
        let project = try project()
        try project.touch("AppSlowTests/Services/RateTests.swift")
        let result = try pbxedit(["move", "AppTests/Services/RateTests.swift", "AppSlowTests/Services/RateTests.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stderr, "")
        let head = """
            AppTests/Services/RateTests.swift -> AppSlowTests/Services/RateTests.swift
              location: path = RateTests.swift; sourceTree = <group>; in group Services (AA0000000000000000000029) (structure)
              targets: AppSlowTests (inferred, 1 sibling in AppSlowTests/Services)
              platformFilters: AppSlowTests: none (inferred, 1 sibling in AppSlowTests/Services)
              reused file reference AA0000000000000000000310: file reference AppTests/Services/RateTests.swift
              removed child from group AA0000000000000000000027: child of group Services (AA0000000000000000000027)
              added child to group AA0000000000000000000029: child of group Services (AA0000000000000000000029)
              removed phase entry from CC0000000000000000000005: entry in Sources of AppTests (CC0000000000000000000005)
              deleted object BB0000000000000000000180: build file in AppTests
              created build file
            """
        XCTAssertTrue(result.stdout.hasPrefix(head), result.stdout)
        XCTAssertTrue(result.stdout.hasSuffix("""
              added phase entry to CC0000000000000000000010: entry in Sources of AppSlowTests (CC0000000000000000000010)
              removed child from group AA0000000000000000000005: child of group AppTests (AA0000000000000000000005)
              deleted object AA0000000000000000000027: group Services (AA0000000000000000000027), left empty
              membership: AppSlowTests (Sources)
            project.pbxproj: modified

            """), result.stdout)
        XCTAssertEqual(try project.leftovers(), [])
        let text = String(decoding: try project.bytes(), as: UTF8.self)
        XCTAssertTrue(text.contains("AA0000000000000000000310 /* RateTests.swift */"), "the reference keeps its ID")
        XCTAssertFalse(text.contains("BB0000000000000000000180"), text)
        let query = try pbxedit(["query", "AppSlowTests/Services/RateTests.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(query.status, 0, query.stderr)
        XCTAssertTrue(query.stdout.contains("  target: AppSlowTests, phase: Sources, build file: "), query.stdout)
        XCTAssertFalse(query.stdout.contains("target: AppTests"), query.stdout)
        let old = try pbxedit(["query", "AppTests/Services/RateTests.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(old.status, 1)
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(lint.status, 0, lint.stdout)
    }

    // Spec: Keep membership; Explicit flags decide as for add; JSON shape with `moves`.
    func testKeepMembershipAndFlagsAndTheJSONShape() throws {
        let project = try project()
        try project.touch("AppSlowTests/Services/RateTests.swift")
        let kept = try pbxedit(["move", "--json", "--keep-membership", "AppTests/Services/RateTests.swift", "AppSlowTests/Services/RateTests.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(kept.status, 0, kept.stderr)
        let object = try jsonObject(kept)
        XCTAssertEqual(Set(object.keys), Self.jsonKeys)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["modified"] as? Bool, true)
        XCTAssertEqual(object["dryRun"] as? Bool, false)
        XCTAssertTrue(object["error"] is NSNull)
        XCTAssertTrue(object["diff"] is NSNull)
        XCTAssertEqual(object["moves"] as? [[String: String]], [["from": "AppTests/Services/RateTests.swift", "to": "AppSlowTests/Services/RateTests.swift"]])
        XCTAssertEqual(object["notes"] as? [String], ["AppSlowTests/Services/RateTests.swift: membership kept (--keep-membership); the 1 sibling in AppSlowTests/Services belongs to AppSlowTests"])
        let decisions = try XCTUnwrap(object["decisions"] as? [[String: Any]])
        XCTAssertEqual(decisions.map { $0["attribute"] as? String }, ["location", "targets"])
        XCTAssertEqual(decisions[1]["value"] as? String, "AppTests")
        XCTAssertEqual((decisions[1]["source"] as? [String: Any])?["kind"] as? String, "flag")
        let changes = try XCTUnwrap(object["changes"] as? [[String: Any]])
        XCTAssertTrue(changes.allSatisfy { $0["path"] as? String == "AppSlowTests/Services/RateTests.swift" }, "keyed by the destination")
        XCTAssertEqual(changes.map { $0["action"] as? String }, ["reusedFileReference", "removedChild", "addedChild", "reusedBuildFile", "removedChild", "deletedObject"])
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual(results.map { $0["path"] as? String }, ["AppSlowTests/Services/RateTests.swift"])
        XCTAssertEqual((results[0]["memberships"] as? [[String: Any]])?.map { ($0["target"] as? [String: String])?["name"] }, ["AppTests"])
        // --target and --platform override, attributed to the flag.
        try project.touch("App/Mixed/Foo.swift")
        let flagged = try pbxedit(["move", "App/Views/Foo.swift", "App/Mixed/Foo.swift", "--target", "AppExtension", "--platform", "ios", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(flagged.status, 0, flagged.stderr)
        XCTAssertTrue(flagged.stdout.contains("  targets: AppExtension (flag)\n"), flagged.stdout)
        XCTAssertTrue(flagged.stdout.contains("  platformFilters: AppExtension: ios (flag)\n"), flagged.stdout)
        XCTAssertTrue(flagged.stdout.contains("  membership: AppExtension (Sources) [ios]\n"), flagged.stdout)
        XCTAssertEqual(try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root).status, 0)
    }

    // Spec: The disk must already reflect the move; Source and destination are validated; Destination is ambiguous — exit codes, nothing written.
    func testRefusalsAndUsageErrorsWriteNothing() throws {
        let project = try project()
        let before = try project.bytes()
        func refused(_ arguments: [String], _ fragment: String, file: StaticString = #filePath, line: UInt = #line) throws {
            let result = try pbxedit(["move"] + arguments + ["--project", "App.xcodeproj"], in: project.root)
            XCTAssertEqual(result.status, 1, "\(arguments): \(result.stderr)", file: file, line: line)
            XCTAssertTrue(result.stderr.contains(fragment), "\(arguments): \(result.stderr)", file: file, line: line)
            XCTAssertEqual(result.stdout, "project.pbxproj: not modified\n", "\(arguments)", file: file, line: line)
            XCTAssertEqual(try project.bytes(), before, "\(arguments)", file: file, line: line)
        }
        func usage(_ arguments: [String], file: StaticString = #filePath, line: UInt = #line) throws {
            let result = try pbxedit(["move"] + arguments + ["--project", "App.xcodeproj"], in: project.root)
            XCTAssertEqual(result.status, 2, "\(arguments): \(result.stderr)", file: file, line: line)
            XCTAssertEqual(result.stdout, "", "\(arguments)", file: file, line: line)
            XCTAssertEqual(try project.bytes(), before, "\(arguments)", file: file, line: line)
        }
        try refused(["App/Views/Foo.swift", "App/Features/Foo.swift"], "does not exist on disk")
        try project.touch("App/Views/Foo.swift")
        try refused(["App/Views/Foo.swift", "App/Features/Foo.swift"], "move the file on disk first")
        try project.touch("App/Features/Foo.swift")
        try refused(["App/Views/Foo.swift", "App/Features/Foo.swift"], "looks like a copy, not a move; pbxedit add App/Features/Foo.swift")
        try refused(["App/Fooo.swift", "App/Features/Fooo.swift"], "App/Fooo.swift: not in the project")
        try refused(["App/Views/Foo.swift", "App/Shared.swift"], "already resolves there (AA0000000000000000000130)")
        try refused(["App/Resources/en.lproj/Localizable.strings", "App/Resources/fr.lproj/Localizable.strings"], "localized variant in variant group AA0000000000000000000201")
        try refused(["App/Generated/User.swift", "App/Models/User.swift"], "pbxedit add App/Models/User.swift")
        try project.touch("App/Mixed/Foo.swift")
        try FileManager.default.removeItem(at: project.root.appendingPathComponent("App/Views/Foo.swift"))
        try refused(["App/Views/Foo.swift", "App/Mixed/Foo.swift"], "pass --target, or --keep-membership to leave membership as it is")
        try usage(["App/Views/Foo.swift", "App/Mixed/Foo.swift", "--keep-membership", "--target", "App"])
        try usage(["App/Views/Foo.swift", "App/Views/Foo.swift"])
        try usage(["App/Views/Foo.swift"])
        try usage(["App/Views/Foo.swift", "App/Features/Foo.swift", "App/Other/Foo.swift"])
        try usage(["App/Views/Foo.swift", "../Elsewhere.swift"])
        try usage(["App/Views/Foo.swift", "App/Features/Foo.swift", "--target", "Nope"])
        try usage([])
        // A refusal under --json carries the message and the membership as it stands.
        let json = try pbxedit(["move", "--json", "App/Views/Foo.swift", "App/Mixed/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(json.status, 1)
        let object = try jsonObject(json)
        XCTAssertEqual(Set(object.keys), Self.jsonKeys)
        XCTAssertEqual(object["modified"] as? Bool, false)
        XCTAssertTrue((object["error"] as? String)?.contains("--keep-membership") == true, "\(String(describing: object["error"]))")
        XCTAssertEqual(object["moves"] as? [[String: String]], [["from": "App/Views/Foo.swift", "to": "App/Mixed/Foo.swift"]])
        XCTAssertEqual((try XCTUnwrap(object["results"] as? [[String: Any]]))[0]["member"] as? Bool, false, "nothing resolves to the destination yet")
        XCTAssertEqual(try project.bytes(), before)
        XCTAssertEqual(try project.leftovers(), [])
    }

    // Spec: Minimal diff; Dry run.
    func testADryRunShowsTheTwoLineDiffAndWritesNothing() throws {
        let project = try project()
        let before = try project.bytes()
        try project.touch("App/Features/Foo.swift")
        let result = try pbxedit(["move", "--dry-run", "App/Views/Foo.swift", "App/Features/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.hasPrefix("App/Views/Foo.swift -> App/Features/Foo.swift\n  location: path = Foo.swift; sourceTree = <group>; in group Features (AA0000000000000000000017) (structure)\n  targets: App (inferred, 3 siblings in App)\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("\n--- a/project.pbxproj\n+++ b/project.pbxproj\n@@ "), result.stdout)
        XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: not modified (dry run)\n"), result.stdout)
        let lines = result.stdout.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }, ["-\t\t\t\tAA0000000000000000000120 /* Foo.swift */,"])
        XCTAssertEqual(lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }, ["+\t\t\t\tAA0000000000000000000120 /* Foo.swift */,"])
        XCTAssertEqual(try project.bytes(), before)
        let json = try pbxedit(["move", "--dry-run", "--json", "App/Views/Foo.swift", "App/Features/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        let object = try jsonObject(json)
        XCTAssertEqual(object["modified"] as? Bool, false)
        XCTAssertEqual(object["dryRun"] as? Bool, true)
        XCTAssertTrue((object["diff"] as? String)?.hasPrefix("--- a/project.pbxproj") == true)
        XCTAssertEqual((try XCTUnwrap(object["results"] as? [[String: Any]]))[0]["groupPath"] as? String, "App/Features", "the membership the run would leave")
        XCTAssertEqual(try project.bytes(), before)
        // A dry run of a refused move exits as the real run would.
        let refused = try pbxedit(["move", "--dry-run", "App/Views/Foo.swift", "App/Nowhere/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(refused.status, 1)
        XCTAssertEqual(try project.bytes(), before)
    }

    // Spec: Directory rename; Extra files at the destination; Into a synchronized folder.
    func testADirectoryRenameAndASynchronizedDestination() throws {
        let project = try project()
        for member in ["Top.swift", "A/A1.swift", "A/A2.swift", "B/B1.swift", "B/B2.swift", "Extra.swift"] {
            try project.touch("App/Views/Modern/" + member)
        }
        let result = try pbxedit(["move", "App/Views/Legacy", "App/Views/Modern", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        let headers = result.stdout.split(separator: "\n").filter { $0.contains(" -> ") }
        XCTAssertEqual(headers.map(String.init), [
            "App/Views/Legacy/Top.swift -> App/Views/Modern/Top.swift",
            "App/Views/Legacy/A/A1.swift -> App/Views/Modern/A/A1.swift",
            "App/Views/Legacy/A/A2.swift -> App/Views/Modern/A/A2.swift",
            "App/Views/Legacy/B/B1.swift -> App/Views/Modern/B/B1.swift",
            "App/Views/Legacy/B/B2.swift -> App/Views/Modern/B/B2.swift",
        ])
        XCTAssertTrue(result.stdout.contains("\nnote: App/Views/Modern: 1 file on disk under App/Views/Modern is not in the project: Extra.swift; pbxedit add registers it\n"), result.stdout)
        XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: modified\n"), result.stdout)
        let text = String(decoding: try project.bytes(), as: UTF8.self)
        XCTAssertFalse(text.contains("Legacy"), text)
        for id in ["AA0000000000000000000350", "AA0000000000000000000351", "AA0000000000000000000352", "AA0000000000000000000353", "AA0000000000000000000354"] {
            XCTAssertTrue(text.contains(id), id)
        }
        let query = try pbxedit(["query", "App/Views/Modern/B/B2.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(query.status, 0, query.stderr)
        XCTAssertTrue(query.stdout.contains("  group: App/Views/Modern/B ("), query.stdout)
        XCTAssertEqual(try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root).status, 0)
        // Into the synchronized folder: the explicit entries go, the membership reads as covered.
        try project.touch("App/Generated/User.swift")
        let synchronized = try pbxedit(["move", "App/Models/User.swift", "App/Generated/User.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(synchronized.status, 0, synchronized.stderr)
        XCTAssertTrue(synchronized.stdout.hasPrefix("App/Models/User.swift -> App/Generated/User.swift\n  synchronized group AA0000000000000000000301: membership now comes from synchronized group App/Generated (AA0000000000000000000301)\n  removed phase entry from CC0000000000000000000001"), synchronized.stdout)
        XCTAssertTrue(synchronized.stdout.contains("  deleted object AA0000000000000000000026: group Models (AA0000000000000000000026), left empty\n  membership: covered by synchronized group App/Generated (AA0000000000000000000301)\n"), synchronized.stdout)
        XCTAssertEqual(try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root).status, 0)
    }

    // Spec: Renames update every comment; an M3 exemption in the configuration reaches the destination as for add.
    func testARenameAndAnExemptDestination() throws {
        let project = try project()
        try project.touch("App/New.swift")
        let renamed = try pbxedit(["move", "App/Old.swift", "App/New.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(renamed.status, 0, renamed.stderr)
        XCTAssertTrue(renamed.stdout.contains("  set attribute of AA0000000000000000000380: path = New.swift (was Old.swift)\n"), renamed.stdout)
        let text = String(decoding: try project.bytes(), as: UTF8.self)
        XCTAssertFalse(text.contains("Old.swift"), text)
        XCTAssertTrue(text.contains("/* New.swift in Sources */"), text)
        try project.write(".pbxedit.yml", "lint:\n  exempt:\n    M3: [\"App/Loose/**\"]\n")
        try project.touch("App/Loose/New.swift")
        try FileManager.default.removeItem(at: project.root.appendingPathComponent("App/New.swift"))
        let exempt = try pbxedit(["move", "App/New.swift", "App/Loose/New.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(exempt.status, 0, exempt.stderr)
        XCTAssertTrue(exempt.stdout.contains("  location: path = App/Loose/New.swift; sourceTree = SOURCE_ROOT; in no group (config, exempt M3 \"App/Loose/**\")\n"), exempt.stdout)
        XCTAssertTrue(exempt.stdout.contains("  removed child from group AA0000000000000000000002"), exempt.stdout)
        XCTAssertFalse(exempt.stdout.contains("added child"), exempt.stdout)
        let after = String(decoding: try project.bytes(), as: UTF8.self)
        XCTAssertTrue(after.contains("name = New.swift; path = App/Loose/New.swift; sourceTree = SOURCE_ROOT;"), after)
        XCTAssertEqual(try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root).status, 0, "exempt with the config")
        try FileManager.default.removeItem(at: project.root.appendingPathComponent(".pbxedit.yml"))
        let without = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(without.status, 1, "M3 without it: \(without.stdout)")
        XCTAssertTrue(without.stdout.contains("error M3 AA0000000000000000000380"), without.stdout)
    }

    /// Task 7.1: the examples in the change's design.md (Evidence) are real
    /// output. Only the cross-target move mints an ID, which is masked.
    func testDesignEvidenceExamplesAreRealOutput() throws {
        let project = try project()
        let before = try project.bytes()
        try project.touch("App/Views/Foo.swift")
        let early = try pbxedit(["move", "App/Views/Foo.swift", "App/Features/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(early.status, 1)
        XCTAssertEqual(early.stderr, "error: App/Views/Foo.swift is still on disk and App/Features/Foo.swift is not; move the file on disk first (pbxedit moves nothing on disk), then run this command\n")
        XCTAssertEqual(early.stdout, "project.pbxproj: not modified\n")
        // `git mv`, by hand.
        try FileManager.default.moveItem(at: project.root.appendingPathComponent("App/Views/Foo.swift"),
                                         to: try project.touch("App/Features", directory: true).appendingPathComponent("Foo.swift"))
        let dryRun = try pbxedit(["move", "--dry-run", "App/Views/Foo.swift", "App/Features/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(dryRun.status, 0, dryRun.stderr)
        XCTAssertEqual(dryRun.stdout, """
            App/Views/Foo.swift -> App/Features/Foo.swift
              location: path = Foo.swift; sourceTree = <group>; in group Features (AA0000000000000000000017) (structure)
              targets: App (inferred, 3 siblings in App)
              reused file reference AA0000000000000000000120: file reference App/Views/Foo.swift
              removed child from group AA0000000000000000000003: child of group Views (AA0000000000000000000003)
              added child to group AA0000000000000000000017: child of group Features (AA0000000000000000000017)
              reused build file BB0000000000000000000020: build file in App
              note: App/Features/Foo.swift: 1 of 3 siblings in App is also a member of AppExtension; pass --target App --target AppExtension to join it too
              membership: App (Sources)
            --- a/project.pbxproj
            +++ b/project.pbxproj
            @@ -155,7 +155,6 @@
             \t\tAA0000000000000000000003 /* Views */ = {
             \t\t\tisa = PBXGroup;
             \t\t\tchildren = (
            -\t\t\t\tAA0000000000000000000120 /* Foo.swift */,
             \t\t\t\tAA0000000000000000000023 /* Legacy */,
             \t\t\t);
             \t\t\tpath = Views;
            @@ -282,6 +281,7 @@
             \t\tAA0000000000000000000017 /* Features */ = {
             \t\t\tisa = PBXGroup;
             \t\t\tchildren = (
            +\t\t\t\tAA0000000000000000000120 /* Foo.swift */,
             \t\t\t\tAA0000000000000000000018 /* New */,
             \t\t\t);
             \t\t\tpath = Features;
            project.pbxproj: not modified (dry run)

            """)
        XCTAssertEqual(try project.bytes(), before)

        try project.touch("AppSlowTests/Services/RateTests.swift")
        let real = try pbxedit(["move", "AppTests/Services/RateTests.swift", "AppSlowTests/Services/RateTests.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(real.status, 0, real.stderr)
        let masked = real.stdout.replacingOccurrences(of: "created build file [0-9A-F]{24}:", with: "created build file <ID>:", options: .regularExpression)
        XCTAssertEqual(masked, """
            AppTests/Services/RateTests.swift -> AppSlowTests/Services/RateTests.swift
              location: path = RateTests.swift; sourceTree = <group>; in group Services (AA0000000000000000000029) (structure)
              targets: AppSlowTests (inferred, 1 sibling in AppSlowTests/Services)
              platformFilters: AppSlowTests: none (inferred, 1 sibling in AppSlowTests/Services)
              reused file reference AA0000000000000000000310: file reference AppTests/Services/RateTests.swift
              removed child from group AA0000000000000000000027: child of group Services (AA0000000000000000000027)
              added child to group AA0000000000000000000029: child of group Services (AA0000000000000000000029)
              removed phase entry from CC0000000000000000000005: entry in Sources of AppTests (CC0000000000000000000005)
              deleted object BB0000000000000000000180: build file in AppTests
              created build file <ID>: build file for AppSlowTests
              added phase entry to CC0000000000000000000010: entry in Sources of AppSlowTests (CC0000000000000000000010)
              removed child from group AA0000000000000000000005: child of group AppTests (AA0000000000000000000005)
              deleted object AA0000000000000000000027: group Services (AA0000000000000000000027), left empty
              membership: AppSlowTests (Sources)
            project.pbxproj: modified

            """)

        let fresh = try self.project()
        try fresh.touch("AppSlowTests/Services/RateTests.swift")
        let kept = try pbxedit(["move", "--keep-membership", "AppTests/Services/RateTests.swift", "AppSlowTests/Services/RateTests.swift", "--project", "App.xcodeproj"], in: fresh.root)
        XCTAssertEqual(kept.status, 0, kept.stderr)
        XCTAssertEqual(kept.stdout, """
            AppTests/Services/RateTests.swift -> AppSlowTests/Services/RateTests.swift
              location: path = RateTests.swift; sourceTree = <group>; in group Services (AA0000000000000000000029) (structure)
              targets: AppTests (flag)
              reused file reference AA0000000000000000000310: file reference AppTests/Services/RateTests.swift
              removed child from group AA0000000000000000000027: child of group Services (AA0000000000000000000027)
              added child to group AA0000000000000000000029: child of group Services (AA0000000000000000000029)
              reused build file BB0000000000000000000180: build file in AppTests
              removed child from group AA0000000000000000000005: child of group AppTests (AA0000000000000000000005)
              deleted object AA0000000000000000000027: group Services (AA0000000000000000000027), left empty
              note: AppSlowTests/Services/RateTests.swift: membership kept (--keep-membership); the 1 sibling in AppSlowTests/Services belongs to AppSlowTests
              membership: AppTests (Sources)
            project.pbxproj: modified

            """)
    }

    // Spec: Message matches reality — `modified` is true exactly when the
    // bytes differ, over every scenario, in sequence on one project.
    func testModifiedMatchesRealityOverEveryScenario() throws {
        let project = try project()
        // Each step first makes the disk look as it would after the user's own move: destination created, source gone.
        let invocations: [(touch: [String], delete: [String], arguments: [String])] = [
            (["App/Features/Foo.swift"], [], ["move", "App/Views/Foo.swift", "App/Features/Foo.swift"]),
            ([], [], ["move", "App/Views/Foo.swift", "App/Features/Foo.swift"]),
            (["App/Views/Bar.swift"], ["App/Features/Foo.swift"], ["move", "App/Features/Foo.swift", "App/Views/Bar.swift"]),
            (["App/Mixed/Foo.swift"], ["App/Views/Bar.swift"], ["move", "--dry-run", "App/Views/Bar.swift", "App/Mixed/Foo.swift", "--target", "App"]),
            ([], [], ["move", "App/Views/Bar.swift", "App/Mixed/Foo.swift"]),
            ([], [], ["move", "App/Views/Bar.swift", "App/Mixed/Foo.swift", "--keep-membership"]),
            (["AppSlowTests/Services/RateTests.swift"], [], ["move", "AppTests/Services/RateTests.swift", "AppSlowTests/Services/RateTests.swift"]),
            (["App/Shared/Panel.swift"], [], ["move", "App/iOS/Panel.swift", "App/Shared/Panel.swift"]),
            (["App/New.swift"], [], ["move", "App/Old.swift", "App/New.swift"]),
            (["App/Generated/User.swift"], [], ["move", "App/Models/User.swift", "App/Generated/User.swift"]),
            (["App/Models/User.swift"], ["App/Generated/User.swift"], ["move", "App/Generated/User.swift", "App/Models/User.swift"]),
            (["AppTests/State/FooTests.swift"], [], ["move", "AppTests/Views/FooTests.swift", "AppTests/State/FooTests.swift"]),
            (["App/Views/Modern/Top.swift", "App/Views/Modern/A/A1.swift", "App/Views/Modern/A/A2.swift", "App/Views/Modern/B/B1.swift",
              "App/Views/Modern/B/B2.swift"], [], ["move", "App/Views/Legacy", "App/Views/Modern"]),
            ([], [], ["move", "App/Views/Legacy", "App/Views/Modern"]),
            ([], [], ["move", "App/Resources/en.lproj/Localizable.strings", "App/Resources/fr.lproj/Localizable.strings"]),
            ([], [], ["move", "App/Shared.swift", "App/Shared.swift"]),
            ([], [], ["move", "App/Shared.swift", "../Shared.swift"]),
            ([], [], ["move", "App/Shared.swift"]),
            ([], [], ["move", "App/Shared.swift", "App/New.swift", "--target", "Nope"]),
            ([], [], ["move"]),
        ]
        var modifiedRuns = 0
        for (touch, delete, arguments) in invocations {
            for file in touch { try project.touch(file) }
            for file in delete { try FileManager.default.removeItem(at: project.root.appendingPathComponent(file)) }
            let before = try project.bytes()
            let result = try pbxedit(arguments + ["--json", "--project", "App.xcodeproj"], in: project.root)
            let after = try project.bytes()
            XCTAssertTrue([0, 1, 2].contains(result.status), "\(arguments): \(result.status) \(result.stderr)")
            if result.status == 2 {
                XCTAssertEqual(result.stdout, "", "\(arguments)")
                XCTAssertEqual(before, after, "\(arguments): a usage error never writes")
                continue
            }
            let object = try jsonObject(result)
            let modified = try XCTUnwrap(object["modified"] as? Bool, "\(arguments)")
            XCTAssertEqual(modified, before != after, "\(arguments): modified must match the bytes")
            if modified { modifiedRuns += 1 }
            XCTAssertEqual(try project.leftovers(), [], "\(arguments)")
            if result.status == 1 { XCTAssertEqual(before, after, "\(arguments): a failure never leaves a change behind") }
        }
        XCTAssertEqual(modifiedRuns, 9, "the scenarios that write, each once")
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(lint.status, 0, "after every move the project is clean: \(lint.stdout)")
    }

    // Spec: A case-only rename performed on disk; A case-only rename not yet performed (issue #36).
    // On a case-sensitive volume the old spelling is simply gone, and the test passes either way.
    func testACaseOnlyRenameIsAMove() throws {
        let project = try project()
        let old = try project.touch("App/Views/Foo.swift")
        let before = try project.bytes()
        let early = try pbxedit(["move", "--keep-membership", "App/Views/Foo.swift", "App/Views/foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(early.status, 1, early.stderr)
        XCTAssertTrue(early.stderr.contains("move the file on disk first"), early.stderr)
        XCTAssertEqual(try project.bytes(), before)
        try FileManager.default.moveItem(at: old, to: project.root.appendingPathComponent("App/Views/foo.swift"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: project.root.appendingPathComponent("App/Views").path), ["foo.swift"])
        let result = try pbxedit(["move", "--keep-membership", "App/Views/Foo.swift", "App/Views/foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, """
            App/Views/Foo.swift -> App/Views/foo.swift
              location: path = foo.swift; sourceTree = <group>; in group Views (AA0000000000000000000003) (structure)
              targets: App (flag)
              reused file reference AA0000000000000000000120: file reference App/Views/Foo.swift
              set attribute of AA0000000000000000000120: path = foo.swift (was Foo.swift)
              reused build file BB0000000000000000000020: build file in App
              membership: App (Sources)
            project.pbxproj: modified

            """)
        let text = String(decoding: try project.bytes(), as: UTF8.self)
        XCTAssertFalse(text.contains("Foo.swift"), text)
        XCTAssertTrue(text.contains("\t\tAA0000000000000000000120 /* foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = foo.swift; sourceTree = \"<group>\"; };\n"), text)
        XCTAssertTrue(text.contains("\t\tBB0000000000000000000020 /* foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000120 /* foo.swift */; };\n"), text)
        let query = try pbxedit(["query", "App/Views/foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(query.status, 0, query.stderr)
        XCTAssertTrue(query.stdout.contains("  target: App, phase: Sources, build file: BB0000000000000000000020"), query.stdout)
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(lint.status, 0, lint.stdout)
        let plutil = Process()
        plutil.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        plutil.arguments = ["-lint", project.pbxproj.path]
        plutil.standardOutput = FileHandle.nullDevice
        try plutil.run()
        plutil.waitUntilExit()
        XCTAssertEqual(plutil.terminationStatus, 0)
    }
}
