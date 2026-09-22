import Foundation
import XCTest
import PBXModel
@testable import PBXOps

/// Tasks 3.1, 3.2 and 3.4: loading `.pbxedit.yml` — discovery, strict
/// decoding with line numbers (design D4), the configuration root (D7) and
/// project-dependent validation.
final class ConfigTests: XCTestCase {
    private func parse(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> Config {
        try Config.parse(text, file: ".pbxedit.yml")
    }

    private func assertRejected(_ text: String, line expectedLine: Int?, containing fragments: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Config.parse(text, file: ".pbxedit.yml"), "accepted:\n\(text)", file: file, line: line) { error in
            guard let error = error as? ConfigError else { return XCTFail("not a ConfigError: \(error)", file: file, line: line) }
            XCTAssertEqual(error.file, ".pbxedit.yml", file: file, line: line)
            if let expectedLine { XCTAssertEqual(error.line, expectedLine, "\(error)", file: file, line: line) }
            for fragment in fragments {
                XCTAssertTrue(error.description.contains(fragment), "\(error) lacks \(fragment)", file: file, line: line)
            }
            XCTAssertTrue(error.description.hasPrefix(".pbxedit.yml:"), "\(error)", file: file, line: line)
        }
    }

    // MARK: Decoding

    func testTheFullShapeDecodesWithPositionsAndLines() throws {
        let config = try parse("""
            project: App.xcodeproj
            rules:
              - match: "App/tvOS/**"
                platformFilters: [tvos]
              - match: "App/Mixed/**"
                targets: [App]
                platformFilters: []
            lint:
              baseline: .pbxedit-baseline.json
              exempt:
                M3: ["AppTests/Views/**", "Tools/**"]
                D1: ["**/*.generated.swift"]

            """)
        XCTAssertEqual(config.project, "App.xcodeproj")
        XCTAssertEqual(config.rules.count, 2)
        XCTAssertEqual(config.rules[0].position, 1)
        XCTAssertEqual(config.rules[0].line, 3)
        XCTAssertEqual(config.rules[0].match.pattern, "App/tvOS/**")
        XCTAssertNil(config.rules[0].targets)
        XCTAssertEqual(config.rules[0].platformFilters, ["tvos"])
        XCTAssertEqual(config.rules[1].position, 2)
        XCTAssertEqual(config.rules[1].line, 5)
        XCTAssertEqual(config.rules[1].targets, ["App"])
        XCTAssertEqual(config.rules[1].platformFilters, [], "an empty list is explicitly none")
        XCTAssertEqual(config.lint.baseline, ".pbxedit-baseline.json")
        XCTAssertEqual(config.lint.exempt[.M3]?.map(\.pattern), ["AppTests/Views/**", "Tools/**"])
        XCTAssertEqual(config.lint.exempt[.D1]?.map(\.pattern), ["**/*.generated.swift"])
        XCTAssertNil(config.lint.exempt[.M6])
    }

    func testAnEmptyFileIsAnEmptyConfiguration() throws {
        XCTAssertEqual(try parse(""), Config())
        XCTAssertEqual(try parse("# only a comment\n"), Config())
        XCTAssertEqual(try parse("{}\n"), Config())
    }

    func testScalarsAreTakenVerbatim() throws {
        let config = try parse("rules:\n  - match: \"**\"\n    targets: [On, 1, yes]\n")
        XCTAssertEqual(config.rules[0].targets, ["On", "1", "yes"], "a target named like a YAML boolean or number stays a string")
    }

    // Spec: Misspelled key.
    func testAMisspelledKeyNamesTheLineAndTheAllowedKeys() {
        assertRejected("rules:\n  - match: \"App/**\"\n    target: [App]\n", line: 3, containing: ["target", "match, targets, platformFilters"])
        assertRejected("projet: App.xcodeproj\n", line: 1, containing: ["projet", "project, rules, lint"])
        assertRejected("lint:\n  baselines: x\n", line: 2, containing: ["baselines", "baseline, exempt"])
    }

    func testAValueOfTheWrongTypeIsRejectedWithItsLine() {
        assertRejected("rules: App\n", line: 1, containing: ["rules", "list"])
        assertRejected("rules:\n  - match: \"App/**\"\n    targets: App\n", line: 3, containing: ["targets", "list"])
        assertRejected("rules:\n  - match: [\"App/**\"]\n", line: 2, containing: ["match", "string"])
        assertRejected("project:\n  - App.xcodeproj\n", line: 2, containing: ["project", "string"])
        assertRejected("lint: []\n", line: 1, containing: ["lint", "mapping"])
        assertRejected("lint:\n  exempt: [M3]\n", line: 2, containing: ["exempt", "mapping"])
        assertRejected("lint:\n  exempt:\n    M3: \"**\"\n", line: 3, containing: ["M3", "list"])
        assertRejected("- a\n", line: 1, containing: ["mapping"])
        assertRejected("rules:\n  - \"App/**\"\n", line: 2, containing: ["mapping"])
        assertRejected("rules:\n  - targets: [App]\n", line: 2, containing: ["match"])
        assertRejected("rules:\n  - match: \"App/**\"\n    targets: [App, [AppTests]]\n", line: 3, containing: ["targets", "string"])
        assertRejected("rules:\n  - match: \"App/**\"\n    targets: [App, ~]\n", line: 3, containing: ["targets", "string"])
    }

    func testMalformedYAMLIsRejectedWithItsLine() {
        assertRejected("rules: [\n  - match\n", line: nil, containing: ["YAML"])
        assertRejected("project: App.xcodeproj\nrules:\n  - match: \"App/**\n", line: nil, containing: ["YAML"])
        XCTAssertThrowsError(try parse("a: b\n c: d\n")) { error in
            XCTAssertNotNil((error as? ConfigError)?.line, "a YAML error has a line: \(error)")
        }
    }

    func testAnUnknownRuleIDIsRejected() {
        assertRejected("lint:\n  exempt:\n    M9: [\"**\"]\n", line: 3, containing: ["M9", "unknown rule"])
        assertRejected("lint:\n  exempt:\n    m3: [\"**\"]\n", line: 3, containing: ["m3"])
    }

    // Spec: Structural rule cannot be exempted.
    func testANonExemptibleRuleIsRejected() {
        assertRejected("lint:\n  exempt:\n    S2: [\"**\"]\n", line: 3, containing: ["S2", "not exemptible", "M3, M6, D1, D2"])
        assertRejected("lint:\n  exempt:\n    M3: []\n    M1: [\"**\"]\n", line: 4, containing: ["M1", "not exemptible"])
    }

    func testAnUnknownPlatformNameIsRejected() {
        assertRejected("rules:\n  - match: \"**\"\n    platformFilters: [ios, linux]\n", line: 3, containing: ["linux", "ios, maccatalyst, macos, tvos, watchos, xros, driverkit"])
    }

    func testAnUnsupportedGlobIsRejected() {
        assertRejected("rules:\n  - match: \"App/[ab].swift\"\n", line: 2, containing: ["App/[ab].swift"])
        assertRejected("lint:\n  exempt:\n    M3: [\"**/Generated/\"]\n", line: 3, containing: ["**/Generated/"])
    }

    // MARK: Discovery and the configuration root

    private func temporaryTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pbxedit-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App/Views"), withIntermediateDirectories: true)
        return root
    }

    // Spec: Discovery — Found in an ancestor; No configuration.
    func testDiscoveryWalksUpFromTheCurrentDirectory() throws {
        let root = try temporaryTree()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(try ConfigFile.discover(from: root.appendingPathComponent("App/Views")))
        try Data("project: App.xcodeproj\n".utf8).write(to: root.appendingPathComponent(".pbxedit.yml"))
        let found = try XCTUnwrap(try ConfigFile.discover(from: root.appendingPathComponent("App/Views")))
        XCTAssertEqual(found.url.standardizedFileURL.path, root.appendingPathComponent(".pbxedit.yml").standardizedFileURL.path)
        XCTAssertEqual(found.directory.standardizedFileURL.path, root.standardizedFileURL.path)
        XCTAssertEqual(found.config.project, "App.xcodeproj")
        XCTAssertEqual(found.projectURL?.standardizedFileURL.path, root.appendingPathComponent("App.xcodeproj").standardizedFileURL.path,
                       "paths are relative to the file's directory")
        // The nearest one wins.
        try Data("project: Nearer.xcodeproj\n".utf8).write(to: root.appendingPathComponent("App/.pbxedit.yml"))
        XCTAssertEqual(try ConfigFile.discover(from: root.appendingPathComponent("App/Views"))?.config.project, "Nearer.xcodeproj")
    }

    func testAnUnreadableOrInvalidFileIsAConfigError() throws {
        let root = try temporaryTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("custom.yml")
        XCTAssertThrowsError(try ConfigFile.load(url)) { error in
            XCTAssertTrue("\(error)".contains("custom.yml"), "\(error)")
        }
        try Data("rules: nope\n".utf8).write(to: url)
        XCTAssertThrowsError(try ConfigFile.load(url)) { error in
            XCTAssertEqual((error as? ConfigError)?.file, url.path, "the error names the file as given")
            XCTAssertEqual((error as? ConfigError)?.line, 1)
        }
    }

    // Spec: Configuration root.
    func testTheConfigurationDirectoryMustBeTheSourceRootOrAnAncestor() throws {
        let root = try temporaryTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent(".pbxedit.yml")
        try Data("rules:\n  - match: \"Sub/App/**\"\n    targets: [App]\nlint:\n  baseline: b.json\n  exempt:\n    M3: [\"Sub/Tools/**\"]\n".utf8).write(to: url)
        let file = try ConfigFile.load(url)
        let atRoot = try file.bind(sourceRoot: root)
        XCTAssertEqual(atRoot.prefix, "")
        let below = try file.bind(sourceRoot: root.appendingPathComponent("Sub"))
        XCTAssertEqual(below.prefix, "Sub/")
        XCTAssertEqual(below.conventions.targets(for: "App/Foo.swift")?.value, ["App"], "globs are matched after re-basing")
        XCTAssertNil(atRoot.conventions.targets(for: "App/Foo.swift"))
        XCTAssertTrue(below.exemptions.exempts(Finding(rule: .M3, object: nil, path: "Tools/Build.swift", message: "")))
        XCTAssertFalse(atRoot.exemptions.exempts(Finding(rule: .M3, object: nil, path: "Tools/Build.swift", message: "")))
        XCTAssertEqual(file.baselineURL?.standardizedFileURL.path, root.appendingPathComponent("b.json").standardizedFileURL.path)
        XCTAssertThrowsError(try file.bind(sourceRoot: root.deletingLastPathComponent()), "a configuration below the source root") { error in
            XCTAssertTrue("\(error)".contains("source root"), "\(error)")
        }
        let elsewhere = root.appendingPathComponent("Elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("project: App.xcodeproj\n".utf8).write(to: elsewhere.appendingPathComponent(".pbxedit.yml"))
        XCTAssertThrowsError(try ConfigFile.load(elsewhere.appendingPathComponent(".pbxedit.yml")).bind(sourceRoot: root)) { error in
            XCTAssertTrue("\(error)".contains("Elsewhere"), "\(error)")
        }
    }

    // Spec: Target that does not exist (task 3.4).
    func testATargetNotInTheProjectIsRejectedNamingTheRuleAndTheTargets() throws {
        let project = try loadProject("add/app.pbxproj")
        let names = project.targets.compactMap(\.name).sorted()
        let good = try parse("rules:\n  - match: \"App/**\"\n    targets: [App, AppTests]\n")
        XCTAssertNoThrow(try ConfigFile(url: URL(fileURLWithPath: "/x/.pbxedit.yml"), config: good).bind(sourceRoot: URL(fileURLWithPath: "/x")).validate(targets: names))
        let bad = try parse("rules:\n  - match: \"App/**\"\n    targets: [App]\n  - match: \"AppTests/**\"\n    targets: [AppTest]\n")
        XCTAssertThrowsError(try ConfigFile(url: URL(fileURLWithPath: "/x/.pbxedit.yml"), config: bad).bind(sourceRoot: URL(fileURLWithPath: "/x")).validate(targets: names)) { error in
            guard let error = error as? ConfigError else { return XCTFail("\(error)") }
            XCTAssertEqual(error.line, 4, "the line the rule starts on")
            XCTAssertTrue(error.message.contains("rule 2"), error.message)
            XCTAssertTrue(error.message.contains("AppTest"), error.message)
            XCTAssertTrue(error.message.contains("App, AppExtension, AppKit, AppTests"), error.message)
        }
    }

    // Task 7.1: the documented example loads strictly.
    func testTheDocumentedExampleLoads() throws {
        let file = try ConfigFile.load(Fixtures.directory.appendingPathComponent("config/example.pbxedit.yml"))
        XCTAssertEqual(file.config.project, "App.xcodeproj")
        XCTAssertFalse(file.config.rules.isEmpty)
        XCTAssertNotNil(file.config.lint.baseline)
        XCTAssertEqual(Set(file.config.lint.exempt.keys), Set(Config.exemptibleRules), "the example shows every exemptible rule")
    }

    // Task 7.2: every key in `docs/design.md` § Config exists in the decoder and the reverse.
    func testTheDesignDocumentExampleAgreesWithTheDecoder() throws {
        let docs = Fixtures.directory.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/design.md")
        let text = try String(contentsOf: docs, encoding: .utf8)
        let section = try XCTUnwrap(text.range(of: "### Config"), "docs/design.md has a § Config")
        let after = text[section.upperBound...]
        let open = try XCTUnwrap(after.range(of: "```yaml\n"))
        let close = try XCTUnwrap(after[open.upperBound...].range(of: "```"))
        let example = String(after[open.upperBound..<close.lowerBound])
        let config = try Config.parse(example, file: "docs/design.md")
        XCTAssertNotNil(config.project)
        for key in Config.keys + Config.Rule.keys + Config.Lint.keys {
            XCTAssertTrue(example.contains("\(key):"), "docs/design.md § Config does not show the key \(key)")
        }
        XCTAssertEqual(Set(config.lint.exempt.keys), Set(Config.exemptibleRules), "the doc shows every exemptible rule")
    }
}
