import Foundation
import XCTest

/// Tasks 6.1, 6.2 and 7.1: `pbxedit remove` end to end, against the built
/// binary. No file is ever created on disk: removal never reads it.
final class RemoveCommandTests: XCTestCase {
    private static let jsonKeys: Set<String> = [
        "schemaVersion", "modified", "dryRun", "decisions", "changes", "notes", "findings", "error", "diff", "results",
    ]

    // Spec: Ordinary file; File already deleted from disk; No dangling references.
    func testAnOrdinaryFileIsRemovedAndQueryAndLintAgree() throws {
        let project = try TemporaryProject(fixture: "remove/app.pbxproj")
        let result = try pbxedit(["remove", "App/Services/Rate.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stderr, "")
        XCTAssertEqual(result.stdout, """
            App/Services/Rate.swift
              removed phase entry from CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)
              deleted object BB0000000000000000000110: build file in App
              removed child from group AA0000000000000000000013: child of group Services (AA0000000000000000000013)
              deleted object AA0000000000000000000230: file reference App/Services/Rate.swift
              membership: not a member
            project.pbxproj: modified

            """)
        XCTAssertEqual(try project.leftovers(), [])
        let text = String(decoding: try project.bytes(), as: UTF8.self)
        XCTAssertFalse(text.contains("AA0000000000000000000230"), text)
        XCTAssertFalse(text.contains("BB0000000000000000000110"), text)
        XCTAssertFalse(text.contains("Rate.swift"), "no comment mentions it either")
        let query = try pbxedit(["query", "App/Services/Rate.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(query.status, 1)
        XCTAssertEqual(query.stdout, "App/Services/Rate.swift: not a member\n")
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(lint.status, 0, lint.stdout)
        // Removing it again is the unknown-path error (design D2).
        let again = try pbxedit(["remove", "App/Services/Rate.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(again.status, 1)
        XCTAssertTrue(again.stderr.contains("App/Services/Rate.swift: not in the project"), again.stderr)
        XCTAssertEqual(again.stdout, "project.pbxproj: not modified\n")
    }

    // Spec: Shared source without a choice; Remove from everything; Detach a shared source; JSON shape.
    func testASharedFileNeedsAChoiceAndTheJSONListsWhatWasRemoved() throws {
        let project = try TemporaryProject(fixture: "remove/app.pbxproj")
        let before = try project.bytes()
        let refused = try pbxedit(["remove", "App/Services/Cache.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(refused.status, 1)
        XCTAssertEqual(refused.stderr, "error: App/Services/Cache.swift belongs to App and AppExtension; pass --target <name> to detach it from one, or --all to remove it from the project\n")
        XCTAssertEqual(refused.stdout, "project.pbxproj: not modified\n")
        XCTAssertEqual(try project.bytes(), before)
        let both = try pbxedit(["remove", "--target", "App", "--all", "App/Services/Cache.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(both.status, 2, "--target with --all is a usage error")
        XCTAssertEqual(both.stdout, "")
        XCTAssertEqual(try project.bytes(), before)

        let detached = try pbxedit(["remove", "--json", "App/Services/Cache.swift", "--target", "AppExtension", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(detached.status, 0, detached.stderr)
        let object = try jsonObject(detached)
        XCTAssertEqual(Set(object.keys), Self.jsonKeys)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["modified"] as? Bool, true)
        XCTAssertEqual(object["dryRun"] as? Bool, false)
        XCTAssertTrue(object["error"] is NSNull)
        XCTAssertTrue(object["diff"] is NSNull)
        XCTAssertEqual((object["decisions"] as? [Any])?.count, 0)
        XCTAssertEqual((object["findings"] as? [Any])?.count, 0)
        XCTAssertEqual(object["notes"] as? [String], [])
        let changes = try XCTUnwrap(object["changes"] as? [[String: Any]])
        XCTAssertEqual(changes.map { $0["action"] as? String }, ["removedPhaseEntry", "deletedObject"])
        XCTAssertEqual(changes.map { $0["object"] as? String }, ["CC0000000000000000000004", "BB0000000000000000000113"])
        XCTAssertEqual(changes[1]["detail"] as? String, "build file in AppExtension")
        XCTAssertEqual(Set(changes[0].keys), ["path", "action", "object", "detail"])
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual(results[0]["member"] as? Bool, true)
        XCTAssertEqual(results[0]["fileReference"] as? String, "AA0000000000000000000232")
        XCTAssertEqual(results[0]["groups"] as? [String], ["AA0000000000000000000013"])
        XCTAssertEqual((results[0]["memberships"] as? [[String: Any]])?.map { ($0["target"] as? [String: String])?["name"] }, ["App"])

        let all = try pbxedit(["remove", "--json", "App/Shared.swift", "--all", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(all.status, 0, all.stderr)
        let removed = try jsonObject(all)
        let kinds = try XCTUnwrap(removed["changes"] as? [[String: Any]]).filter { $0["action"] as? String == "deletedObject" }
            .map { "\($0["object"] as? String ?? "") \($0["detail"] as? String ?? "")" }
        XCTAssertEqual(kinds, [
            "BB0000000000000000000030 build file in App",
            "BB0000000000000000000040 build file in AppExtension",
            "AA0000000000000000000130 file reference App/Shared.swift",
        ], "every removed object with its ID and kind")
        XCTAssertEqual(removed["notes"] as? [String], ["App/Shared.swift: removed from App, AppExtension (--all)"])
        XCTAssertEqual((try XCTUnwrap(removed["results"] as? [[String: Any]]))[0]["member"] as? Bool, false)
        XCTAssertEqual(try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root).status, 0)
    }

    // Spec: Last membership detached; Not a member of that target; unknown target name.
    func testDetachExitCodes() throws {
        let project = try TemporaryProject(fixture: "remove/app.pbxproj")
        let last = try pbxedit(["remove", "App/Services/Rate.swift", "--target", "App", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(last.status, 0, last.stderr)
        XCTAssertTrue(last.stdout.contains("  note: App/Services/Rate.swift: now built by no target; the file reference and its group child remain\n"), last.stdout)
        XCTAssertTrue(last.stdout.contains("  membership: referenced, built by no target\n"), last.stdout)
        XCTAssertTrue(last.stdout.hasSuffix("project.pbxproj: modified\n"), last.stdout)
        let before = try project.bytes()
        let notMember = try pbxedit(["remove", "--json", "App/Views/Foo.swift", "--target", "AppTests", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(notMember.status, 1)
        let object = try jsonObject(notMember)
        XCTAssertEqual(object["modified"] as? Bool, false)
        XCTAssertEqual(object["error"] as? String, "App/Views/Foo.swift is not a member of AppTests; it belongs to App")
        XCTAssertEqual((try XCTUnwrap(object["results"] as? [[String: Any]]))[0]["member"] as? Bool, true, "the membership as it stands")
        XCTAssertEqual(try project.bytes(), before)
        let unknown = try pbxedit(["remove", "App/Views/Foo.swift", "--target", "Apptests", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(unknown.status, 2)
        XCTAssertEqual(unknown.stdout, "")
        XCTAssertTrue(unknown.stderr.contains("App, AppExtension, AppKit, AppTests"), unknown.stderr)
        XCTAssertEqual(try project.bytes(), before)
    }

    // Spec: Typo; Localized resource; Synchronized folder; One unknown path among three.
    func testRefusalsExitOneAndWriteNothing() throws {
        let project = try TemporaryProject(fixture: "remove/app.pbxproj")
        let before = try project.bytes()
        let typo = try pbxedit(["remove", "App/Fooo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(typo.status, 1)
        XCTAssertTrue(typo.stderr.contains("App/Fooo.swift"), typo.stderr)
        XCTAssertEqual(typo.stdout, "project.pbxproj: not modified\n")
        let variant = try pbxedit(["remove", "App/Resources/en.lproj/Localizable.strings", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(variant.status, 1)
        XCTAssertTrue(variant.stderr.contains("localized variant in variant group AA0000000000000000000201"), variant.stderr)
        let synchronized = try pbxedit(["remove", "--json", "App/Generated/User.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(synchronized.status, 1)
        let object = try jsonObject(synchronized)
        XCTAssertTrue((object["error"] as? String)?.contains("synchronized folder App/Generated (AA0000000000000000000301)") == true, "\(String(describing: object["error"]))")
        XCTAssertEqual(((try XCTUnwrap(object["results"] as? [[String: Any]]))[0]["synchronized"] as? [String: Any])?["group"] as? String, "AA0000000000000000000301")
        let three = try pbxedit(["remove", "App/Services/Rate.swift", "App/Nope.swift", "App/Views/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(three.status, 1)
        XCTAssertTrue(three.stderr.contains("App/Nope.swift"), three.stderr)
        let none = try pbxedit(["remove", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(none.status, 2)
        let outside = try pbxedit(["remove", "../Elsewhere.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(outside.status, 2)
        XCTAssertEqual(try project.bytes(), before)
        XCTAssertEqual(try project.leftovers(), [])
    }

    // Spec: Dry run — the diff, bytes unchanged, the real run's exit code.
    func testADryRunPrintsTheDiffAndWritesNothing() throws {
        let project = try TemporaryProject(fixture: "remove/app.pbxproj")
        let before = try project.bytes()
        let result = try pbxedit(["remove", "--dry-run", "App/tvOS/TV1.swift", "App/tvOS/TV2.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("\n--- a/project.pbxproj\n+++ b/project.pbxproj\n@@ "), result.stdout)
        XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: not modified (dry run)\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("  deleted object AA0000000000000000000014: group tvOS (AA0000000000000000000014), left empty\n"), result.stdout)
        let lines = result.stdout.split(separator: "\n").map(String.init)
        let removedLines = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }
        XCTAssertEqual(removedLines.count, 2 + 2 + 2 + 1 + 9, "two build files, two references, two phase entries, one child of App, the tvOS group's nine lines: \(removedLines)")
        XCTAssertFalse(lines.contains { $0.hasPrefix("+") && !$0.hasPrefix("+++") }, "nothing is added: \(result.stdout)")
        XCTAssertEqual(try project.bytes(), before)
        let json = try pbxedit(["remove", "--dry-run", "--json", "App/tvOS/TV1.swift", "--project", "App.xcodeproj"], in: project.root)
        let object = try jsonObject(json)
        XCTAssertEqual(object["modified"] as? Bool, false)
        XCTAssertEqual(object["dryRun"] as? Bool, true)
        XCTAssertTrue((object["diff"] as? String)?.hasPrefix("--- a/project.pbxproj") == true)
        XCTAssertEqual((try XCTUnwrap(object["results"] as? [[String: Any]]))[0]["member"] as? Bool, false, "the membership the run would leave")
        XCTAssertEqual(try project.bytes(), before)
        let refused = try pbxedit(["remove", "--dry-run", "App/Services/Cache.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(refused.status, 1)
    }

    // Spec: Empty groups are removed — the chain, in text; exemptions are honoured by the checks.
    func testTheChainIsPrunedAndConfigExemptionsApply() throws {
        let project = try TemporaryProject(fixture: "remove/app.pbxproj")
        let result = try pbxedit(["remove", "App/Features/New/Thing.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("  deleted object AA0000000000000000000018: group New (AA0000000000000000000018), left empty\n  removed child from group AA0000000000000000000002: child of group App (AA0000000000000000000002)\n  deleted object AA0000000000000000000017: group Features (AA0000000000000000000017), left empty\n"), result.stdout)
        let text = String(decoding: try project.bytes(), as: UTF8.self)
        XCTAssertFalse(text.contains("Features"), text)
        XCTAssertTrue(text.contains("AA0000000000000000000019 /* Empty */"), "the group that was already empty stays")
        XCTAssertEqual(try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root).status, 0)
        // A detach on a file whose reference is exempt from M3 (and orphaned) passes only with the config.
        let partial = try TemporaryProject(fixture: "add/partial.pbxproj")
        try partial.write("AppTests/Views/.keep", "")
        let refused = try pbxedit(["remove", "AppTests/Views/FooTests.swift", "--target", "App", "--project", "App.xcodeproj"], in: partial.root)
        XCTAssertEqual(refused.status, 1, "BF01 is in no phase, so the file is not a member of App: \(refused.stderr)")
        let whole = try pbxedit(["remove", "AppTests/Views/FooTests.swift", "--project", "App.xcodeproj"], in: partial.root)
        XCTAssertEqual(whole.status, 0, whole.stderr)
        XCTAssertTrue(whole.stdout.contains("  deleted object BF01: build file in no phase\n"), whole.stdout)
        XCTAssertTrue(whole.stdout.hasSuffix("project.pbxproj: modified\n"), whole.stdout)
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: partial.root)
        XCTAssertTrue(lint.stdout.hasSuffix("2 errors, 0 warnings\n"), "only the two unrelated orphans remain: \(lint.stdout)")
    }

    /// Task 7.1: the examples in the change's design.md (Evidence) are real
    /// output. Nothing is minted by a removal, so they are compared exactly.
    func testDesignEvidenceExamplesAreRealOutput() throws {
        let project = try TemporaryProject(fixture: "remove/app.pbxproj")
        let before = try project.bytes()
        let dryRun = try pbxedit(["remove", "--dry-run", "App/Features/New/Thing.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(dryRun.status, 0, dryRun.stderr)
        let head = """
            App/Features/New/Thing.swift
              removed phase entry from CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)
              deleted object BB0000000000000000000160: build file in App
              removed child from group AA0000000000000000000018: child of group New (AA0000000000000000000018)
              deleted object AA0000000000000000000280: file reference App/Features/New/Thing.swift
              removed child from group AA0000000000000000000017: child of group Features (AA0000000000000000000017)
              deleted object AA0000000000000000000018: group New (AA0000000000000000000018), left empty
              removed child from group AA0000000000000000000002: child of group App (AA0000000000000000000002)
              deleted object AA0000000000000000000017: group Features (AA0000000000000000000017), left empty
              membership: not a member
            --- a/project.pbxproj
            +++ b/project.pbxproj
            @@ -29,7 +29,6 @@
             \t\tBB0000000000000000000141 /* F2.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000261 /* F2.swift */; };
             \t\tBB0000000000000000000150 /* AppKit.h in Headers */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000270 /* AppKit.h */; settings = {ATTRIBUTES = (Public, ); }; };
             \t\tBB0000000000000000000151 /* Kit.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000271 /* Kit.swift */; };
            -\t\tBB0000000000000000000160 /* Thing.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000280 /* Thing.swift */; };
             /* End PBXBuildFile section */

            """
        XCTAssertTrue(dryRun.stdout.hasPrefix(head), dryRun.stdout)
        XCTAssertTrue(dryRun.stdout.hasSuffix("project.pbxproj: not modified (dry run)\n"), dryRun.stdout)
        XCTAssertEqual(try project.bytes(), before)
        let real = try pbxedit(["remove", "App/Features/New/Thing.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(real.status, 0, real.stderr)
        XCTAssertEqual(real.stdout, String(head.prefix(upTo: head.range(of: "--- a/project.pbxproj")!.lowerBound)) + "project.pbxproj: modified\n")

        let detached = try pbxedit(["remove", "App/Services/Cache.swift", "--target", "AppExtension", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(detached.status, 0, detached.stderr)
        XCTAssertEqual(detached.stdout, """
            App/Services/Cache.swift
              removed phase entry from CC0000000000000000000004: entry in Sources of AppExtension (CC0000000000000000000004)
              deleted object BB0000000000000000000113: build file in AppExtension
              membership: App (Sources)
            project.pbxproj: modified

            """)

        let fresh = try TemporaryProject(fixture: "remove/app.pbxproj")
        let shared = try pbxedit(["remove", "App/Services/Cache.swift", "--project", "App.xcodeproj"], in: fresh.root)
        XCTAssertEqual(shared.status, 1)
        XCTAssertEqual(shared.stderr, "error: App/Services/Cache.swift belongs to App and AppExtension; pass --target <name> to detach it from one, or --all to remove it from the project\n")
        XCTAssertEqual(shared.stdout, "project.pbxproj: not modified\n")
    }

    // Spec: Message matches reality — `modified` is true exactly when the
    // bytes differ, over every scenario, in sequence on one project.
    func testModifiedMatchesRealityOverEveryScenario() throws {
        let project = try TemporaryProject(fixture: "remove/app.pbxproj")
        let invocations: [[String]] = [
            ["remove", "App/Services/Rate.swift"],
            ["remove", "App/Services/Rate.swift"],
            ["remove", "--dry-run", "App/Views/Foo.swift"],
            ["remove", "App/Services/Cache.swift"],
            ["remove", "App/Services/Cache.swift", "--target", "AppExtension"],
            ["remove", "App/Services/Cache.swift", "--target", "AppExtension"],
            ["remove", "App/Services/Cache.swift", "--all"],
            ["remove", "App/Shared.swift", "--target", "App"],
            ["remove", "App/Shared.swift", "--target", "AppExtension"],
            ["remove", "App/Shared.swift"],
            ["remove", "App/App.entitlements"],
            ["remove", "App/Generated/User.swift"],
            ["remove", "App/Resources/en.lproj/Localizable.strings"],
            ["remove", "App/Features/New/Thing.swift", "AppTests/Foo/Bar.swift"],
            ["remove", "App/tvOS/TV1.swift", "App/Nope.swift"],
            ["remove", "App/tvOS/TV1.swift", "App/tvOS/TV2.swift"],
            ["remove", "App/Views/Foo.swift", "--target", "Nope"],
            ["remove", "App/Views/Foo.swift", "--target", "App", "--all"],
            ["remove", "../Elsewhere.swift"],
            ["remove"],
            ["remove", "App/Views/Foo.swift", "--target", "AppKit"],
        ]
        var modifiedRuns = 0
        for arguments in invocations {
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
        XCTAssertEqual(lint.status, 0, "after every removal the project is clean: \(lint.stdout)")
    }
}
