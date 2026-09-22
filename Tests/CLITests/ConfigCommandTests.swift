import Foundation
import XCTest

/// Tasks 3.1, 3.4 and 6.3: `.pbxedit.yml` reaches every command — discovery,
/// strict validation as exit `2`, and the default project.
final class ConfigCommandTests: XCTestCase {
    // Spec: Discovery — Found in an ancestor.
    func testTheConfigurationIsFoundInAnAncestorOfTheCurrentDirectory() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        let views = try project.touch("App/Views", directory: true)
        let without = try pbxedit(["lint"], in: views)
        XCTAssertEqual(without.status, 2, "no project in App/Views and no configuration: \(without.stderr)")
        try project.write(".pbxedit.yml", "project: App.xcodeproj\n")
        let found = try pbxedit(["lint", "--json"], in: views)
        XCTAssertEqual(found.status, 0, found.stderr)
        let object = try jsonObject(found)
        XCTAssertEqual((object["project"] as? String)?.hasSuffix("/App.xcodeproj/project.pbxproj"), true, "\(String(describing: object["project"]))")
        XCTAssertEqual(try pbxedit(["query", "--target", "App"], in: views).status, 0)
    }

    // Spec: Discovery — No configuration.
    func testWithoutAConfigurationEveryCommandBehavesAsBefore() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Bar.swift")
        let result = try pbxedit(["add", "App/Views/Bar.swift"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("  targets: App (inferred, 1 sibling in App/Views)\n"), result.stdout)
        XCTAssertEqual(try pbxedit(["lint"], in: project.root).status, 0)
    }

    // Spec: Discovery — `--config`, and a missing `--config` path.
    func testConfigOptionNamesTheFileAndAMissingOneExitsTwo() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        _ = try project.addProject(named: "Tools", try Fixtures.load("rules/m3-orphan.pbxproj"))
        try project.write(".pbxedit.yml", "project: Tools.xcodeproj\n")
        try project.write("custom.yml", "project: App.xcodeproj\n")
        let discovered = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(discovered.status, 1, "Tools has an M3: \(discovered.stdout)")
        let explicit = try pbxedit(["lint", "--config", "custom.yml"], in: project.root)
        XCTAssertEqual(explicit.status, 0, "--config wins over the discovered file: \(explicit.stdout)")
        XCTAssertEqual(explicit.stdout, "0 errors, 0 warnings\n")
        for command in [["lint"], ["query", "--target", "App"], ["add", "App/Views/Bar.swift"]] {
            let missing = try pbxedit(command + ["--config", "other.yml"], in: project.root)
            XCTAssertEqual(missing.status, 2, "\(command): \(missing.stderr)")
            XCTAssertTrue(missing.stderr.contains("other.yml"), missing.stderr)
            XCTAssertEqual(missing.stdout, "")
        }
        let json = try pbxedit(["lint", "--json", "--config", "other.yml"], in: project.root)
        XCTAssertEqual(json.status, 2)
        XCTAssertTrue(json.stderr.contains("\"error\""), json.stderr)
    }

    // Spec: Default project — Project named in configuration (task 6.3).
    func testProjectInTheConfigurationResolvesTheTwoProjectsAmbiguity() throws {
        let project = try TemporaryProject(fixture: "model/app.pbxproj")
        _ = try project.addProject(named: "Tools", try Fixtures.load("rules/m3-orphan.pbxproj"))
        let ambiguous = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(ambiguous.status, 2, ambiguous.stderr)
        try project.write(".pbxedit.yml", "project: App.xcodeproj\n")
        let configured = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(configured.status, 0, configured.stderr)
        XCTAssertEqual(configured.stdout, "0 errors, 0 warnings\n")
        // --project still wins.
        let flagged = try pbxedit(["lint", "--project", "Tools.xcodeproj"], in: project.root)
        XCTAssertEqual(flagged.status, 1, flagged.stdout)
        // A configured project that does not exist is a usage error naming it.
        try project.write(".pbxedit.yml", "project: Nope.xcodeproj\n")
        let missing = try pbxedit(["lint"], in: project.root)
        XCTAssertEqual(missing.status, 2)
        XCTAssertTrue(missing.stderr.contains("Nope.xcodeproj"), missing.stderr)
        XCTAssertTrue(missing.stderr.contains(".pbxedit.yml"), missing.stderr)
    }

    // Spec: Strict validation — Misspelled key; every command exits 2 before acting.
    func testAnInvalidConfigurationIsAUsageErrorForEveryCommand() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Bar.swift")
        let before = try project.bytes()
        try project.write(".pbxedit.yml", "project: App.xcodeproj\nrules:\n  - match: \"App/**\"\n    target: [App]\n")
        for command in [["lint"], ["query", "App/Views/Foo.swift"], ["add", "App/Views/Bar.swift"], ["add", "--dry-run", "App/Views/Bar.swift"]] {
            let result = try pbxedit(command, in: project.root)
            XCTAssertEqual(result.status, 2, "\(command): \(result.stderr)")
            XCTAssertEqual(result.stdout, "", "\(command)")
            XCTAssertTrue(result.stderr.contains(".pbxedit.yml:4:"), result.stderr)
            XCTAssertTrue(result.stderr.contains("target"), result.stderr)
            XCTAssertTrue(result.stderr.contains("match, targets, platformFilters"), result.stderr)
        }
        XCTAssertEqual(try project.bytes(), before)
        XCTAssertEqual(try project.leftovers(), [])
    }

    // Spec: Path exemptions — Structural rule cannot be exempted.
    func testANonExemptibleRuleExitsTwoNamingTheLine() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.write(".pbxedit.yml", "lint:\n  exempt:\n    S2: [\"**\"]\n")
        for command in [["lint"], ["query", "App/Views/Foo.swift"], ["add", "App/Views/Foo.swift"]] {
            let result = try pbxedit(command, in: project.root)
            XCTAssertEqual(result.status, 2, "\(command): \(result.stderr)")
            XCTAssertTrue(result.stderr.contains(".pbxedit.yml:3:"), result.stderr)
            XCTAssertTrue(result.stderr.contains("S2"), result.stderr)
            XCTAssertTrue(result.stderr.contains("not exemptible"), result.stderr)
        }
    }

    // Spec: Strict validation — Target that does not exist (task 3.4).
    func testATargetNotInTheProjectExitsTwoAndWritesNothing() throws {
        let project = try TemporaryProject(fixture: "add/app.pbxproj")
        try project.touch("App/Views/Bar.swift")
        let before = try project.bytes()
        try project.write(".pbxedit.yml", "rules:\n  - match: \"App/**\"\n    targets: [AppTest]\n")
        let add = try pbxedit(["add", "App/Views/Bar.swift"], in: project.root)
        XCTAssertEqual(add.status, 2, add.stderr)
        XCTAssertEqual(add.stdout, "")
        XCTAssertTrue(add.stderr.contains(".pbxedit.yml:2:"), "the line the rule starts on: \(add.stderr)")
        XCTAssertTrue(add.stderr.contains("rule 1"), add.stderr)
        XCTAssertTrue(add.stderr.contains("AppTest"), add.stderr)
        XCTAssertTrue(add.stderr.contains("App, AppExtension, AppKit, AppTests"), add.stderr)
        XCTAssertEqual(try project.bytes(), before)
        XCTAssertEqual(try project.leftovers(), [])
        XCTAssertEqual(try pbxedit(["lint"], in: project.root).status, 2)
        XCTAssertEqual(try pbxedit(["query", "App/Views/Foo.swift"], in: project.root).status, 2)
        // A project that does not load is S1 for lint; the target check cannot run and does not mask it.
        let broken = try TemporaryProject(fixture: "rules/s1-unterminated-comment.pbxproj")
        try broken.write(".pbxedit.yml", "rules:\n  - match: \"App/**\"\n    targets: [AppTest]\n")
        let lint = try pbxedit(["lint"], in: broken.root)
        XCTAssertEqual(lint.status, 1, lint.stderr)
        XCTAssertTrue(lint.stdout.hasPrefix("error S1 "), lint.stdout)
    }

    // Spec: Configuration root — Configuration above the source root.
    func testAConfigurationAboveTheSourceRootReBasesItsGlobs() throws {
        let outer = FileManager.default.temporaryDirectory.appendingPathComponent("pbxedit-outer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outer.appendingPathComponent("Sub/Tools"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outer) }
        let xcodeproj = outer.appendingPathComponent("Sub/App.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        try Data(try Fixtures.load("add/app.pbxproj")).write(to: xcodeproj.appendingPathComponent("project.pbxproj"))
        try Data("// Build.swift\n".utf8).write(to: outer.appendingPathComponent("Sub/Tools/Build.swift"))
        try Data("project: Sub/App.xcodeproj\nrules:\n  - match: \"Sub/Tools/**\"\n    targets: [AppKit]\n".utf8).write(to: outer.appendingPathComponent(".pbxedit.yml"))
        let result = try pbxedit(["add", "Tools/Build.swift"], in: outer.appendingPathComponent("Sub"))
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("  targets: AppKit (config, rule 1 \"Sub/Tools/**\")\n"), result.stdout)
        // A configuration beside, not above, the source root is rejected.
        try FileManager.default.createDirectory(at: outer.appendingPathComponent("Elsewhere"), withIntermediateDirectories: true)
        try Data("project: ../Sub/App.xcodeproj\n".utf8).write(to: outer.appendingPathComponent("Elsewhere/.pbxedit.yml"))
        let rejected = try pbxedit(["lint", "--config", "../Elsewhere/.pbxedit.yml"], in: outer.appendingPathComponent("Sub"))
        XCTAssertEqual(rejected.status, 2, rejected.stderr)
        XCTAssertTrue(rejected.stderr.contains("Elsewhere"), rejected.stderr)
        XCTAssertTrue(rejected.stderr.contains("source root"), rejected.stderr)
    }
}
