import Foundation
import XCTest

/// Tasks 4.1 and 4.3: `pbxedit query` end to end, against the built binary.
final class QueryCommandTests: XCTestCase {
    // Spec: Output and exit codes — human output for one member.
    func testHumanOutputForAMember() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        // Paths are relative to the current directory: run from the source root,
        // here with an absolute --project.
        let result = try pbxedit(["query", "App/Shared.swift", "--project", project.xcodeproj.path], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, """
            App/Shared.swift: member
              reference: AA0000000000000000000130
              group: App (AA0000000000000000000002)
              target: App, phase: Sources, build file: BB0000000000000000000030
              target: AppExtension, phase: Sources, build file: BB0000000000000000000040, platforms: ios, maccatalyst

            """)
        XCTAssertEqual(result.stderr, "")
    }

    // Design D4: the hint, for a reference with no group and a build file with no phase.
    func testHumanOutputAddsTheLintHintForOddFacts() throws {
        let orphan = try TemporaryProject(fixture: "rules/m3-orphan.pbxproj")
        let noGroup = try pbxedit(["query", "AppTests/Views/FooTests.swift", "--project", "App.xcodeproj"], in: orphan.root)
        XCTAssertEqual(noGroup.status, 0, noGroup.stderr)
        XCTAssertEqual(noGroup.stdout, """
            AppTests/Views/FooTests.swift: member
              reference: AB12
              group: none
              target: App, phase: Sources, build file: BF01
              hint: run pbxedit lint

            """)
        let unbuilt = try TemporaryProject(fixture: "rules/m1-no-phase.pbxproj")
        let noPhase = try pbxedit(["query", "AppTests/FooTests.swift", "--project", "App.xcodeproj"], in: unbuilt.root)
        XCTAssertEqual(noPhase.status, 0, noPhase.stderr)
        XCTAssertEqual(noPhase.stdout, """
            AppTests/FooTests.swift: member
              reference: AB12
              group: AppTests (G002)
              target: none, phase: none, build file: BF01
              hint: run pbxedit lint

            """)
    }

    // Spec: Output and exit codes — Mixed results.
    func testJSONForMixedResultsExitsOne() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let result = try pbxedit(["query", "--json", "App/Views/Foo.swift", "App/Nope.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, result.stderr)
        XCTAssertEqual(result.stderr, "")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any], result.stdout)
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "results"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 2)
        let keys: Set<String> = ["path", "member", "fileReference", "groupPath", "groups", "memberships", "synchronized"]
        XCTAssertEqual(Set(results[0].keys), keys)
        XCTAssertEqual(Set(results[1].keys), keys)
        XCTAssertEqual(results.map { $0["path"] as? String }, ["App/Views/Foo.swift", "App/Nope.swift"])
        XCTAssertEqual(results.map { $0["member"] as? Bool }, [true, false])
        XCTAssertEqual(results[0]["fileReference"] as? String, "AA0000000000000000000120")
        XCTAssertEqual(results[0]["groupPath"] as? String, "App/Views")
        XCTAssertEqual(results[0]["groups"] as? [String], ["AA0000000000000000000003"])
        let memberships = try XCTUnwrap(results[0]["memberships"] as? [[String: Any]])
        XCTAssertEqual(memberships.count, 1)
        XCTAssertEqual(Set(memberships[0].keys), ["target", "phase", "buildFile", "platformFilters"])
        XCTAssertEqual(memberships[0]["target"] as? [String: String], ["id": "DD0000000000000000000001", "name": "App"])
        XCTAssertEqual(memberships[0]["phase"] as? [String: String], ["id": "CC0000000000000000000001", "name": "Sources"])
        XCTAssertEqual(memberships[0]["buildFile"] as? String, "BB0000000000000000000020")
        XCTAssertEqual(memberships[0]["platformFilters"] as? [String], [])
        XCTAssertTrue(results[0]["synchronized"] is NSNull)
        XCTAssertTrue(results[1]["fileReference"] is NSNull)
        XCTAssertTrue(results[1]["groupPath"] is NSNull)
        XCTAssertEqual((results[1]["memberships"] as? [Any])?.count, 0)
        XCTAssertTrue(result.stdout.contains("\"synchronized\" : null"), "absent values are null, never omitted")
    }

    func testNotAMemberExitsOneInHumanOutputToo() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let result = try pbxedit(["query", "App/Nope.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, result.stderr)
        XCTAssertEqual(result.stdout, "App/Nope.swift: not a member\n")
        XCTAssertEqual(result.stderr, "")
    }

    // Spec: Output and exit codes — Synchronized path exits zero.
    func testSynchronizedPathExitsZero() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let result = try pbxedit(["query", "App/Generated/User.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, """
            App/Generated/User.swift: not a member; covered by synchronized group App/Generated (AA0000000000000000000301) in App

            """)
        let json = try pbxedit(["query", "--json", "App/Generated/User.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(json.status, 0, json.stderr)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.stdout.utf8)) as? [String: Any], json.stdout)
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual(results[0]["member"] as? Bool, false)
        let synchronized = try XCTUnwrap(results[0]["synchronized"] as? [String: Any])
        XCTAssertEqual(synchronized["group"] as? String, "AA0000000000000000000301")
        XCTAssertEqual(synchronized["path"] as? String, "App/Generated")
        XCTAssertEqual(synchronized["targets"] as? [[String: String]], [["id": "DD0000000000000000000001", "name": "App"]])
    }

    // Spec: Members of a target — Target listing.
    func testTargetListing() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let result = try pbxedit(["query", "--target", "AppTests", "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stdout, """
            AppTests (DD0000000000000000000003): 2 entries
              Sources: AppTests/Foo/Bar.swift (BB0000000000000000000070)
              Sources: AppTests/Views/FooTests.swift (BB0000000000000000000060)

            """)
        let app = try pbxedit(["query", "--target", "App", "--project", project.xcodeproj.path])
        XCTAssertEqual(app.status, 0, app.stderr)
        XCTAssertTrue(app.stdout.hasPrefix("App (DD0000000000000000000001): 5 entries\n  Frameworks: $(SDKROOT)/System/Library/Frameworks/Foundation.framework (BB0000000000000000000080)\n"), app.stdout)
        let ext = try pbxedit(["query", "--target", "AppExtension", "--project", project.xcodeproj.path])
        XCTAssertTrue(ext.stdout.hasSuffix("  Sources: App/Shared.swift (BB0000000000000000000040) [ios, maccatalyst]\n"), ext.stdout)
        let json = try pbxedit(["query", "--json", "--target", "AppTests", "--project", project.xcodeproj.path])
        XCTAssertEqual(json.status, 0, json.stderr)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.stdout.utf8)) as? [String: Any], json.stdout)
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "target", "members"])
        XCTAssertEqual(object["target"] as? [String: String], ["id": "DD0000000000000000000003", "name": "AppTests"])
        let members = try XCTUnwrap(object["members"] as? [[String: Any]])
        XCTAssertEqual(members.map { $0["path"] as? String }, ["AppTests/Foo/Bar.swift", "AppTests/Views/FooTests.swift"])
        XCTAssertEqual(Set(members[0].keys), ["buildFile", "fileReference", "path", "phase", "platformFilters"])
    }

    // Spec: Members of a target — Unknown target.
    func testUnknownTargetExitsTwoListingNames() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let result = try pbxedit(["query", "--target", "Apptests", "--project", project.xcodeproj.path])
        XCTAssertEqual(result.status, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Apptests"), result.stderr)
        XCTAssertTrue(result.stderr.contains("App, AppExtension, AppTests"), result.stderr)
        let json = try pbxedit(["query", "--json", "--target", "Apptests", "--project", project.xcodeproj.path])
        XCTAssertEqual(json.status, 2)
        XCTAssertEqual(json.stdout, "")
        XCTAssertTrue(json.stderr.contains("\"error\""), json.stderr)
    }

    func testTargetWithPathsAndNoArgumentsAreUsageErrors() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let both = try pbxedit(["query", "--target", "App", "App/Views/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(both.status, 2, both.stderr)
        XCTAssertEqual(both.stdout, "")
        XCTAssertTrue(both.stderr.contains("--target"), both.stderr)
        let none = try pbxedit(["query", "--project", project.xcodeproj.path])
        XCTAssertEqual(none.status, 2, none.stderr)
        XCTAssertEqual(none.stdout, "")
        XCTAssertTrue(none.stderr.contains("--target"), none.stderr)
    }

    // Design D3: a file that does not load is exit 2, not a finding.
    func testAnUnparseableProjectExitsTwo() throws {
        let project = try TemporaryProject(fixture: "rules/s1-unterminated-comment.pbxproj")
        let result = try pbxedit(["query", "App/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("3:14"), result.stderr)
    }

    // Spec: Path arguments — Run from a subdirectory.
    func testRunFromASubdirectoryWithARelativeProject() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let views = project.root.appendingPathComponent("App/Views")
        try FileManager.default.createDirectory(at: views, withIntermediateDirectories: true)
        let result = try pbxedit(["query", "Foo.swift", "--project", "../../App.xcodeproj"], in: views)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.hasPrefix("App/Views/Foo.swift: member\n"), result.stdout)
        let dotted = try pbxedit(["query", "./../Views/Foo.swift", "--project", "../../App.xcodeproj"], in: views)
        XCTAssertEqual(dotted.status, 0, dotted.stderr)
        XCTAssertTrue(dotted.stdout.hasPrefix("App/Views/Foo.swift: member\n"), dotted.stdout)
        let basename = try pbxedit(["query", "Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(basename.status, 1, "from the root, Foo.swift is the root's Foo.swift, which is not a member: never by basename")
        XCTAssertEqual(basename.stdout, "Foo.swift: not a member\n")
    }

    // Spec: Path arguments — Outside the source root.
    func testAPathOutsideTheSourceRootExitsTwo() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let result = try pbxedit(["query", "../Other/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 2)
        XCTAssertEqual(result.stdout, "")
        XCTAssertTrue(result.stderr.contains("Other/Foo.swift"), result.stderr)
        XCTAssertTrue(result.stderr.contains("source root"), result.stderr)
        let root = try pbxedit(["query", ".", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(root.status, 2)
        XCTAssertEqual(root.stdout, "")
    }

    /// Task 5.1: the examples in the change's design.md (Evidence) are real
    /// output; this pins them byte for byte.
    func testDesignEvidenceExamplesAreRealOutput() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let human = try pbxedit(["query", "App/Shared.swift", "App/Nope.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(human.status, 1)
        XCTAssertEqual(human.stdout, """
            App/Shared.swift: member
              reference: AA0000000000000000000130
              group: App (AA0000000000000000000002)
              target: App, phase: Sources, build file: BB0000000000000000000030
              target: AppExtension, phase: Sources, build file: BB0000000000000000000040, platforms: ios, maccatalyst
            App/Nope.swift: not a member

            """)
        let json = try pbxedit(["query", "--json", "App/Views/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(json.status, 0)
        XCTAssertEqual(json.stdout, """
            {
              "results" : [
                {
                  "fileReference" : "AA0000000000000000000120",
                  "groupPath" : "App/Views",
                  "groups" : [
                    "AA0000000000000000000003"
                  ],
                  "member" : true,
                  "memberships" : [
                    {
                      "buildFile" : "BB0000000000000000000020",
                      "phase" : {
                        "id" : "CC0000000000000000000001",
                        "name" : "Sources"
                      },
                      "platformFilters" : [

                      ],
                      "target" : {
                        "id" : "DD0000000000000000000001",
                        "name" : "App"
                      }
                    }
                  ],
                  "path" : "App/Views/Foo.swift",
                  "synchronized" : null
                }
              ],
              "schemaVersion" : 1
            }

            """)
        let target = try pbxedit(["query", "--target", "AppTests", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(target.status, 0)
        XCTAssertEqual(target.stdout, """
            AppTests (DD0000000000000000000003): 2 entries
              Sources: AppTests/Foo/Bar.swift (BB0000000000000000000070)
              Sources: AppTests/Views/FooTests.swift (BB0000000000000000000060)

            """)
    }

    // Spec: Read-only — Bytes unchanged, after each invocation form (task 4.3).
    func testEveryInvocationLeavesBytesAndModificationTimeUnchanged() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        // A modification time in the past, so a rewrite with identical bytes would still be visible.
        let past = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: project.pbxproj.path)
        let before = try project.bytes()
        let modified = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: project.pbxproj.path)[.modificationDate] as? Date)
        XCTAssertEqual(modified.timeIntervalSince1970, past.timeIntervalSince1970, accuracy: 1)
        let invocations: [[String]] = [
            ["query", "App/Views/Foo.swift"],
            ["query", "--json", "App/Views/Foo.swift", "App/Nope.swift"],
            ["query", "App/Generated/User.swift"],
            ["query", "--target", "AppTests"],
            ["query", "--json", "--target", "App"],
            ["query", "--target", "Nope"],
            ["query", "../Outside.swift"],
            ["query"],
        ]
        for arguments in invocations {
            let result = try pbxedit(arguments + ["--project", "App.xcodeproj"], in: project.root)
            XCTAssertTrue([0, 1, 2].contains(result.status), "\(arguments): \(result.stderr)")
            XCTAssertEqual(try project.bytes(), before, "\(arguments) changed the bytes")
            let after = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: project.pbxproj.path)[.modificationDate] as? Date)
            XCTAssertEqual(after, modified, "\(arguments) changed the modification time")
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: project.xcodeproj.path)
        XCTAssertEqual(leftovers, ["project.pbxproj"], "nothing else is written beside the project file")
    }
}
