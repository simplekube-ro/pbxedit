import Foundation
import XCTest

/// Tasks 6.1 and 6.2: `pbxedit add` end to end, against the built binary.
final class AddCommandTests: XCTestCase {
    private static let jsonKeys: Set<String> = [
        "schemaVersion", "modified", "dryRun", "decisions", "changes", "notes", "findings", "error", "diff", "results",
    ]

    // Spec: The file must exist — Typo.
    func testAMissingFileExitsOneAndWritesNothing() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        let before = try project.bytes()
        let result = try pbxedit(["add", "App/Fooo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, result.stderr)
        XCTAssertTrue(result.stderr.contains("App/Fooo.swift"), result.stderr)
        XCTAssertEqual(result.stdout, "project.pbxproj: not modified\n")
        XCTAssertEqual(try project.bytes(), before)
        XCTAssertEqual(try project.leftovers(), [])
        // A directory that is not a bundle is refused too; a bundle passes.
        try project.touch("App/Views/Sub", directory: true)
        let directory = try pbxedit(["add", "App/Views/Sub", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(directory.status, 1, directory.stderr)
        XCTAssertTrue(directory.stderr.contains("directory"), directory.stderr)
        try project.touch("App/Resources/Extra.xcassets", directory: true)
        let bundle = try pbxedit(["add", "App/Resources/Extra.xcassets", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(bundle.status, 0, bundle.stderr)
        XCTAssertTrue(bundle.stdout.contains("phase: Resources (file type)"), bundle.stdout)
    }

    // Spec: Complete membership in one step — New file; Output states what was decided.
    func testANewFileIsAddedWithProvenanceAndQueryAgrees() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Bar.swift")
        let result = try pbxedit(["add", "App/Views/Bar.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.hasPrefix("App/Views/Bar.swift\n  phase: Sources (file type)\n  location: path = Bar.swift; sourceTree = <group>; in group Views (AA0000000000000000000003) (structure)\n  targets: App (inferred, 1 sibling in App/Views)\n  platformFilters: App: none (inferred, 1 sibling in App/Views)\n  created file reference "), result.stdout)
        XCTAssertTrue(result.stdout.contains("  added child to group AA0000000000000000000003: child of group Views (AA0000000000000000000003)\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("  created build file "), result.stdout)
        XCTAssertTrue(result.stdout.contains("  added phase entry to CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)\n"), result.stdout)
        XCTAssertTrue(result.stdout.contains("  membership: App (Sources)\n"), result.stdout)
        XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: modified\n"), result.stdout)
        XCTAssertEqual(try project.leftovers(), [])
        let query = try pbxedit(["query", "App/Views/Bar.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(query.status, 0, query.stderr)
        XCTAssertTrue(query.stdout.contains("  group: App/Views (AA0000000000000000000003)\n  target: App, phase: Sources, build file: "), query.stdout)
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(lint.status, 0, lint.stdout)
    }

    // Spec: Explicit options override inference; JSON shape.
    func testOverridesAreAttributedToTheFlagAndTheJSONHasEveryKey() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Bar.swift")
        let result = try pbxedit(["add", "--json", "App/Views/Bar.swift", "--target", "AppTests", "--platform", "ios,macos", "--phase", "sources", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        let object = try jsonObject(result)
        XCTAssertEqual(Set(object.keys), Self.jsonKeys)
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["modified"] as? Bool, true)
        XCTAssertEqual(object["dryRun"] as? Bool, false)
        XCTAssertTrue(object["error"] is NSNull)
        XCTAssertTrue(object["diff"] is NSNull)
        XCTAssertEqual((object["findings"] as? [Any])?.count, 0)
        XCTAssertEqual((object["notes"] as? [Any])?.count, 0)
        let decisions = try XCTUnwrap(object["decisions"] as? [[String: Any]])
        XCTAssertEqual(decisions.map { $0["attribute"] as? String }, ["phase", "location", "targets", "platformFilters"])
        let flag: NSDictionary = ["kind": "flag", "siblings": NSNull(), "directory": NSNull(), "rule": NSNull(), "glob": NSNull()]
        XCTAssertEqual(decisions[0]["value"] as? String, "Sources")
        XCTAssertEqual(decisions[0]["source"] as? NSDictionary, flag)
        XCTAssertEqual(decisions[2]["value"] as? String, "AppTests")
        XCTAssertEqual(decisions[2]["source"] as? NSDictionary, flag)
        XCTAssertEqual(decisions[3]["value"] as? String, "AppTests: ios, macos")
        XCTAssertEqual(Set(decisions[1].keys), ["path", "attribute", "value", "source"])
        XCTAssertEqual(decisions[1]["source"] as? NSDictionary, ["kind": "structure", "siblings": NSNull(), "directory": NSNull(), "rule": NSNull(), "glob": NSNull()] as NSDictionary)
        let changes = try XCTUnwrap(object["changes"] as? [[String: Any]])
        XCTAssertEqual(changes.map { $0["action"] as? String }, ["createdFileReference", "addedChild", "createdBuildFile", "addedPhaseEntry"])
        XCTAssertEqual(Set(changes[0].keys), ["path", "action", "object", "detail"])
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["member"] as? Bool, true)
        let memberships = try XCTUnwrap(results[0]["memberships"] as? [[String: Any]])
        XCTAssertEqual(memberships.map { ($0["target"] as? [String: String])?["name"] }, ["AppTests"])
        XCTAssertEqual(memberships[0]["platformFilters"] as? [String], ["ios", "macos"])
        // Inference has its provenance in JSON too.
        try project.touch("App/tvOS/TV3.swift")
        let inferred = try pbxedit(["add", "--json", "App/tvOS/TV3.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(inferred.status, 0, inferred.stderr)
        let inferredDecisions = try XCTUnwrap(try jsonObject(inferred)["decisions"] as? [[String: Any]])
        XCTAssertEqual(inferredDecisions[2]["source"] as? [String: Any] as NSDictionary?, ["kind": "inferred", "siblings": 2, "directory": "App/tvOS", "rule": NSNull(), "glob": NSNull()] as NSDictionary)
        XCTAssertEqual(inferredDecisions[3]["value"] as? String, "App: tvos")
    }

    // Spec: Explicit options override inference — unknown names exit 2.
    func testUnknownTargetOrPlatformExitsTwoListingTheValidNames() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Bar.swift")
        let before = try project.bytes()
        let target = try pbxedit(["add", "App/Views/Bar.swift", "--target", "Apptests", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(target.status, 2)
        XCTAssertEqual(target.stdout, "")
        XCTAssertTrue(target.stderr.contains("Apptests"), target.stderr)
        XCTAssertTrue(target.stderr.contains("App, AppExtension, AppKit, AppTests"), target.stderr)
        let platform = try pbxedit(["add", "--json", "App/Views/Bar.swift", "--platform", "ios,linux", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(platform.status, 2)
        XCTAssertEqual(platform.stdout, "")
        XCTAssertTrue(platform.stderr.contains("linux"), platform.stderr)
        XCTAssertTrue(platform.stderr.contains("\"error\""), platform.stderr)
        let phase = try pbxedit(["add", "App/Views/Bar.swift", "--phase", "links", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(phase.status, 2)
        let none = try pbxedit(["add", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(none.status, 2)
        XCTAssertEqual(try project.bytes(), before)
    }

    // Spec: Nothing is written unless the whole plan is sound — One bad path among three.
    func testOneBadPathAmongThreeLeavesBytesUnchanged() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Bar.swift")
        try project.touch("App/Views/Baz.swift")
        let before = try project.bytes()
        let result = try pbxedit(["add", "App/Views/Bar.swift", "App/Views/Nope.swift", "App/Views/Baz.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 1, result.stderr)
        XCTAssertTrue(result.stderr.contains("App/Views/Nope.swift"), result.stderr)
        XCTAssertEqual(try project.bytes(), before)
        // The same with a refusal from planning: a disagreeing directory among sound paths.
        try project.touch("App/Mixed/New.swift")
        let refused = try pbxedit(["add", "App/Views/Bar.swift", "App/Mixed/New.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(refused.status, 1, refused.stderr)
        XCTAssertTrue(refused.stderr.contains("--target"), refused.stderr)
        XCTAssertEqual(try project.bytes(), before)
        XCTAssertEqual(try project.leftovers(), [])
    }

    // Spec: Idempotence — Re-add; Synchronized folders need no entry.
    func testReAddAndSynchronizedPathsAreNotModified() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Foo.swift")
        try project.touch("App/Generated/User.swift")
        let before = try project.bytes()
        let readd = try pbxedit(["add", "App/Views/Foo.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(readd.status, 0, readd.stderr)
        XCTAssertTrue(readd.stdout.contains("  reused file reference AA0000000000000000000120"), readd.stdout)
        XCTAssertTrue(readd.stdout.hasSuffix("project.pbxproj: not modified\n"), readd.stdout)
        XCTAssertEqual(try project.bytes(), before)
        let synchronized = try pbxedit(["add", "--json", "App/Generated/User.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(synchronized.status, 0, synchronized.stderr)
        let object = try jsonObject(synchronized)
        XCTAssertEqual(object["modified"] as? Bool, false)
        let changes = try XCTUnwrap(object["changes"] as? [[String: Any]])
        XCTAssertEqual(changes.map { $0["action"] as? String }, ["synchronized"])
        XCTAssertEqual(changes[0]["object"] as? String, "AA0000000000000000000301")
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        XCTAssertEqual((results[0]["synchronized"] as? [String: Any])?["path"] as? String, "App/Generated")
        XCTAssertEqual(try project.bytes(), before)
    }

    // Spec: Dry run — Preview.
    func testADryRunPrintsTheDiffAndWritesNothing() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Bar.swift")
        let before = try project.bytes()
        let result = try pbxedit(["add", "--dry-run", "App/Views/Bar.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("\n--- a/project.pbxproj\n+++ b/project.pbxproj\n@@ "), result.stdout)
        XCTAssertTrue(result.stdout.contains("\n+\t\t\t\t"), result.stdout)
        XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: not modified (dry run)\n"), result.stdout)
        XCTAssertEqual(try project.bytes(), before)
        let json = try pbxedit(["add", "--dry-run", "--json", "App/Views/Bar.swift", "--project", "App.xcodeproj"], in: project.root)
        let object = try jsonObject(json)
        XCTAssertEqual(object["modified"] as? Bool, false)
        XCTAssertEqual(object["dryRun"] as? Bool, true)
        XCTAssertTrue((object["diff"] as? String)?.hasPrefix("--- a/project.pbxproj") == true, "\(String(describing: object["diff"]))")
        XCTAssertEqual(try project.bytes(), before)
        // A dry run has the exit code the real run would have.
        let collision = try TemporaryProject(fixture: "add/m4-collision.pbxproj")
        try collision.touch("App/Foo.swift")
        let refused = try pbxedit(["add", "--dry-run", "App/Foo.swift", "--project", "App.xcodeproj"], in: collision.root)
        XCTAssertEqual(refused.status, 1, refused.stderr)
    }

    // Spec: Collision with existing damage; Unrelated damage does not block.
    func testViolationsAmongTouchedObjectsAbortAndUnrelatedDamageDoesNot() throws {
        let collision = try TemporaryProject(fixture: "add/m4-collision.pbxproj")
        try collision.touch("App/Foo.swift")
        let before = try collision.bytes()
        let refused = try pbxedit(["add", "App/Foo.swift", "--project", "App.xcodeproj"], in: collision.root)
        XCTAssertEqual(refused.status, 1, refused.stderr)
        XCTAssertTrue(refused.stdout.contains("error M4 AB13 App/Foo.swift: file reference AB13 resolves to App/Foo.swift, the same path as AB12\n"), refused.stdout)
        XCTAssertTrue(refused.stdout.hasSuffix("project.pbxproj: not modified\n"), refused.stdout)
        XCTAssertEqual(try collision.bytes(), before)
        XCTAssertEqual(try collision.leftovers(), [])
        let json = try pbxedit(["add", "--json", "App/Foo.swift", "--project", "App.xcodeproj"], in: collision.root)
        XCTAssertEqual(json.status, 1)
        let object = try jsonObject(json)
        XCTAssertEqual(object["modified"] as? Bool, false)
        let findings = try XCTUnwrap(object["findings"] as? [[String: Any]])
        XCTAssertEqual(findings.map { $0["rule"] as? String }, ["M4"])
        XCTAssertEqual(Set(findings[0].keys), ["rule", "severity", "object", "path", "related", "message"])

        let partial = try TemporaryProject(fixture: "add/partial.pbxproj")
        try partial.touch("AppTests/Views/FooTests.swift")
        let completed = try pbxedit(["add", "AppTests/Views/FooTests.swift", "--target", "App", "--project", "App.xcodeproj"], in: partial.root)
        XCTAssertEqual(completed.status, 0, completed.stderr)
        XCTAssertTrue(completed.stdout.contains("  reused build file BF01"), completed.stdout)
        XCTAssertTrue(completed.stdout.hasSuffix("project.pbxproj: modified\n"), completed.stdout)
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: partial.root)
        XCTAssertEqual(lint.status, 1)
        XCTAssertTrue(lint.stdout.hasSuffix("2 errors, 0 warnings\n"), "only the two unrelated orphans remain: \(lint.stdout)")
    }

    // Spec: Targets are inferred from siblings — the notes and refusals reach the output.
    func testInferenceNotesAndRefusals() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Services/New.swift")
        let shared = try pbxedit(["add", "App/Services/New.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(shared.status, 0, shared.stderr)
        XCTAssertTrue(shared.stdout.contains("  note: App/Services/New.swift: 1 of 3 siblings in App/Services is also a member of AppExtension; pass --target App --target AppExtension to join it too\n"), shared.stdout)
        XCTAssertTrue(shared.stdout.contains("  membership: App (Sources)\n"), shared.stdout)
        try project.touch("App/Filtered/New.swift")
        let before = try project.bytes()
        let filters = try pbxedit(["add", "--json", "App/Filtered/New.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(filters.status, 1, filters.stderr)
        let object = try jsonObject(filters)
        XCTAssertEqual(object["modified"] as? Bool, false)
        XCTAssertTrue((object["error"] as? String)?.contains("--platform") == true, "\(String(describing: object["error"]))")
        XCTAssertEqual(try project.bytes(), before)
        try project.touch("App/data.bin")
        let unknown = try pbxedit(["add", "App/data.bin", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(unknown.status, 1)
        XCTAssertTrue(unknown.stderr.contains("--phase"), unknown.stderr)
        try project.touch("AppTests/Foo/fixture.json")
        let noPhase = try pbxedit(["add", "AppTests/Foo/fixture.json", "--target", "AppTests", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(noPhase.status, 1)
        XCTAssertTrue(noPhase.stderr.contains("no Resources phase"), noPhase.stderr)
    }

    // Spec: Path arguments are shared: run from a subdirectory.
    func testPathsAreRelativeToTheCurrentDirectory() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        let file = try project.touch("App/Views/Bar.swift")
        let result = try pbxedit(["add", "Bar.swift", "--project", "../../App.xcodeproj"], in: file.deletingLastPathComponent())
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.hasPrefix("App/Views/Bar.swift\n"), result.stdout)
        let outside = try pbxedit(["add", "../Elsewhere.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(outside.status, 2)
    }

    /// Task 7.2: the examples in the change's design.md (Evidence) are real
    /// output. Minted IDs are random per run, so both sides are masked and
    /// the diff is compared by its added lines rather than hunk positions.
    func testDesignEvidenceExamplesAreRealOutput() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Bar.swift")
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
        let dryRun = try pbxedit(["add", "--dry-run", "App/Views/Bar.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(dryRun.status, 0, dryRun.stderr)
        let expectedHead = """
            App/Views/Bar.swift
              phase: Sources (file type)
              location: path = Bar.swift; sourceTree = <group>; in group Views (AA0000000000000000000003) (structure)
              targets: App (inferred, 1 sibling in App/Views)
              platformFilters: App: none (inferred, 1 sibling in App/Views)
              created file reference D0591B5336CBE0FF19A69027: file reference for App/Views/Bar.swift (path = Bar.swift; sourceTree = <group>)
              added child to group AA0000000000000000000003: child of group Views (AA0000000000000000000003)
              created build file A2C1C436873BA2E083589590: build file for App
              added phase entry to CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)
              membership: App (Sources)
            --- a/project.pbxproj
            +++ b/project.pbxproj

            """
        XCTAssertTrue(masked(dryRun.stdout).hasPrefix(masked(expectedHead)), dryRun.stdout)
        XCTAssertTrue(dryRun.stdout.hasSuffix("\t\t};\nproject.pbxproj: not modified (dry run)\n"), dryRun.stdout)
        let expectedAdded = [
            "+\t\tA2C1C436873BA2E083589590 /* Bar.swift in Sources */ = {isa = PBXBuildFile; fileRef = D0591B5336CBE0FF19A69027 /* Bar.swift */; };",
            "+\t\tD0591B5336CBE0FF19A69027 /* Bar.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Bar.swift; sourceTree = \"<group>\"; };",
            "+\t\t\t\tD0591B5336CBE0FF19A69027 /* Bar.swift */,",
            "+\t\t\t\tA2C1C436873BA2E083589590 /* Bar.swift in Sources */,",
        ].map(masked)
        let added = dryRun.stdout.split(separator: "\n").map(String.init).filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.map(masked)
        XCTAssertEqual(added.sorted(), expectedAdded.sorted())
        // Four hunks — build file, reference, group child, phase entry — unless
        // the minted build file sorts last in its section and the reference
        // first in the next: those two insertions are then three lines apart
        // and the diff merges their hunks. The IDs are random per run, so the
        // expectation follows them (found flaky by `remove-command`).
        func mintedInDryRun(_ prefix: String) -> String {
            dryRun.stdout.split(separator: "\n").first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count).prefix(24)) } ?? ""
        }
        let adjacent = mintedInDryRun("  created build file ") > "BB0000000000000000000151"
            && mintedInDryRun("  created file reference ") < "AA0000000000000000000110"
        XCTAssertEqual(dryRun.stdout.components(separatedBy: "\n@@ ").count - 1, adjacent ? 3 : 4,
                       "four hunks: build file, reference, group child, phase entry — three when the first two are adjacent")

        let real = try pbxedit(["add", "App/Views/Bar.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(real.status, 0, real.stderr)
        XCTAssertEqual(masked(real.stdout), masked(String(expectedHead.dropLast("--- a/project.pbxproj\n+++ b/project.pbxproj\n".count)) + "project.pbxproj: modified\n"))
        // Everything minted is named by the real run, so the re-add pins exactly.
        func minted(_ prefix: String) throws -> String {
            let line = try XCTUnwrap(real.stdout.split(separator: "\n").first { $0.hasPrefix(prefix) }, real.stdout)
            return String(line.dropFirst(prefix.count).prefix(24))
        }
        let reference = try minted("  created file reference ")
        let buildFile = try minted("  created build file ")
        XCTAssertTrue(String(decoding: try project.bytes(), as: UTF8.self).contains("\t\t\(reference) /* Bar.swift */ = {isa = PBXFileReference;"))
        let again = try pbxedit(["add", "App/Views/Bar.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(again.status, 0, again.stderr)
        XCTAssertEqual(again.stdout, """
            App/Views/Bar.swift
              phase: Sources (file type)
              targets: App (inferred, 1 sibling in App/Views)
              reused file reference \(reference): file reference App/Views/Bar.swift
              reused build file \(buildFile): build file in App
              membership: App (Sources)
            project.pbxproj: not modified

            """)
        // The JSON example, on a fresh copy, masked the same way.
        let fresh = try TemporaryProject(fixture: "add/app.pbxproj")
        try fresh.touch("App/Views/Bar.swift")
        let json = try pbxedit(["add", "--json", "App/Views/Bar.swift", "--project", "App.xcodeproj"], in: fresh.root)
        XCTAssertEqual(json.status, 0, json.stderr)
        let expectedJSON = """
            {
              "changes" : [
                {
                  "action" : "createdFileReference",
                  "detail" : "file reference for App/Views/Bar.swift (path = Bar.swift; sourceTree = <group>)",
                  "object" : "D0591B5336CBE0FF19A69027",
                  "path" : "App/Views/Bar.swift"
                },
                {
                  "action" : "addedChild",
                  "detail" : "child of group Views (AA0000000000000000000003)",
                  "object" : "AA0000000000000000000003",
                  "path" : "App/Views/Bar.swift"
                },
                {
                  "action" : "createdBuildFile",
                  "detail" : "build file for App",
                  "object" : "A2C1C436873BA2E083589590",
                  "path" : "App/Views/Bar.swift"
                },
                {
                  "action" : "addedPhaseEntry",
                  "detail" : "entry in Sources of App (CC0000000000000000000001)",
                  "object" : "CC0000000000000000000001",
                  "path" : "App/Views/Bar.swift"
                }
              ],
              "decisions" : [
                {
                  "attribute" : "phase",
                  "path" : "App/Views/Bar.swift",
                  "source" : {
                    "directory" : null,
                    "glob" : null,
                    "kind" : "fileType",
                    "rule" : null,
                    "siblings" : null
                  },
                  "value" : "Sources"
                },
                {
                  "attribute" : "location",
                  "path" : "App/Views/Bar.swift",
                  "source" : {
                    "directory" : null,
                    "glob" : null,
                    "kind" : "structure",
                    "rule" : null,
                    "siblings" : null
                  },
                  "value" : "path = Bar.swift; sourceTree = <group>; in group Views (AA0000000000000000000003)"
                },
                {
                  "attribute" : "targets",
                  "path" : "App/Views/Bar.swift",
                  "source" : {
                    "directory" : "App/Views",
                    "glob" : null,
                    "kind" : "inferred",
                    "rule" : null,
                    "siblings" : 1
                  },
                  "value" : "App"
                },
                {
                  "attribute" : "platformFilters",
                  "path" : "App/Views/Bar.swift",
                  "source" : {
                    "directory" : "App/Views",
                    "glob" : null,
                    "kind" : "inferred",
                    "rule" : null,
                    "siblings" : 1
                  },
                  "value" : "App: none"
                }
              ],
              "diff" : null,
              "dryRun" : false,
              "error" : null,
              "findings" : [

              ],
              "modified" : true,
              "notes" : [

              ],
              "results" : [
                {
                  "fileReference" : "D0591B5336CBE0FF19A69027",
                  "groupPath" : "App/Views",
                  "groups" : [
                    "AA0000000000000000000003"
                  ],
                  "member" : true,
                  "memberships" : [
                    {
                      "buildFile" : "A2C1C436873BA2E083589590",
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
                  "path" : "App/Views/Bar.swift",
                  "synchronized" : null
                }
              ],
              "schemaVersion" : 1
            }

            """
        XCTAssertEqual(masked(json.stdout), masked(expectedJSON))
    }

    // Task 6.2 — spec: Message matches reality. `modified` is true exactly
    // when the bytes differ from before the run, over every scenario, run in
    // sequence against the same project so that state evolves.
    func testModifiedMatchesRealityOverEveryScenario() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        for path in ["App/Views/Bar.swift", "App/Views/Foo.swift", "App/Generated/User.swift", "App/Services/Rate.swift",
                     "App/App.entitlements", "App/Mixed/New.swift", "App/Filtered/New.swift", "App/Features/New/Thing.swift",
                     "AppTests/Views/BarTests.swift", "App/Resources/Localizable.xcstrings", "AppKit/Extra.h", "App/data.bin",
                     "AppTests/Foo/fixture.json", "App/tvOS/TV3.swift"] {
            try project.touch(path)
        }
        let invocations: [[String]] = [
            ["add", "App/Views/Bar.swift"],
            ["add", "App/Views/Bar.swift"],
            ["add", "App/Views/Foo.swift"],
            ["add", "--dry-run", "App/tvOS/TV3.swift"],
            ["add", "App/Nope.swift"],
            ["add", "App/Generated/User.swift"],
            ["add", "App/Services/Rate.swift", "--target", "AppExtension"],
            ["add", "App/App.entitlements"],
            ["add", "App/Mixed/New.swift"],
            ["add", "App/Mixed/New.swift", "--target", "App"],
            ["add", "App/Filtered/New.swift"],
            ["add", "App/Filtered/New.swift", "--platform", "none"],
            ["add", "App/Features/New/Thing.swift", "AppTests/Views/BarTests.swift"],
            ["add", "App/Resources/Localizable.xcstrings", "AppKit/Extra.h"],
            ["add", "App/data.bin"],
            ["add", "App/data.bin", "--phase", "resources", "--target", "App"],
            ["add", "AppTests/Foo/fixture.json", "--target", "AppTests"],
            ["add", "App/tvOS/TV3.swift", "--target", "Nope"],
            ["add", "App/tvOS/TV3.swift", "App/Views/Bar.swift"],
            ["add", "../Elsewhere.swift"],
            ["add"],
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
            let modified = try XCTUnwrap(object["modified"] as? Bool, "\(arguments)")
            XCTAssertEqual(modified, before != after, "\(arguments): modified must match the bytes")
            if modified { modifiedRuns += 1 }
            XCTAssertEqual(try project.leftovers(), [], "\(arguments)")
            if result.status == 1 { XCTAssertEqual(before, after, "\(arguments): a failure never leaves a change behind") }
        }
        XCTAssertEqual(modifiedRuns, 9, "the scenarios that write, each once")
        // And the human line says the same thing.
        try project.touch("App/Views/Baz.swift")
        let before = try project.bytes()
        let human = try pbxedit(["add", "App/Views/Baz.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(human.stdout.hasSuffix("project.pbxproj: modified\n"), try project.bytes() != before)
        let again = try pbxedit(["add", "App/Views/Baz.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertTrue(again.stdout.hasSuffix("project.pbxproj: not modified\n"), again.stdout)
        let lint = try pbxedit(["lint", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(lint.status, 0, "after every add the project is clean: \(lint.stdout)")
    }
}
