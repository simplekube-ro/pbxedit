import XCTest
import PBXModel
@testable import PBXOps

/// Tasks 4.1 and 4.2: the configuration layer inside `Conventions` (design
/// D1, D2) on `add/app.pbxproj`, and its precedence against flags and
/// inference.
final class ConfigConventionsTests: XCTestCase {
    private var project: Project!

    override func setUpWithError() throws {
        project = try loadProject("add/app.pbxproj")
    }

    private func target(_ name: String) -> Target {
        project.targets.first { $0.name == name }!
    }

    private func conventions(_ yaml: String, flags: Conventions.Flags = Conventions.Flags()) throws -> Conventions {
        let config = try Config.parse(yaml, file: ".pbxedit.yml")
        return Conventions(flags: flags, config: ConfigConventions(rules: config.rules))
    }

    // Spec: First file in a new target directory.
    func testASingleRuleSuppliesTargetsWhereInferenceHasNothing() throws {
        XCTAssertThrowsError(try Conventions().targets(for: "Tools/Build.swift", kind: .source, in: project)) { error in
            XCTAssertEqual(error as? PlanError, .noSiblings(path: "Tools/Build.swift"))
        }
        let configured = try conventions("rules:\n  - match: \"Tools/**\"\n    targets: [AppKit]\n")
        let choice = try configured.targets(for: "Tools/Build.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["AppKit"])
        XCTAssertEqual(choice.source, .config(rule: 1, glob: "Tools/**"))
        XCTAssertEqual(choice.extras.count, 0)
        XCTAssertEqual(choice.source.description, "config, rule 1 \"Tools/**\"")
        XCTAssertEqual(choice.source.kind, "config")
        // The filters for that target still come from inference: no sibling in AppKit means none.
        let filters = try configured.platformFilters(for: "Tools/Build.swift", kind: .source, target: target("AppKit"), in: project)
        XCTAssertEqual(filters.value, [])
        XCTAssertEqual(filters.source, .inferred(siblings: 0, directory: "Tools"))
    }

    // Spec: Attributes come from different rules.
    func testAttributesComeFromTheFirstRuleThatSetsEach() throws {
        let configured = try conventions("""
            rules:
              - match: "App/**"
                platformFilters: [tvos]
              - match: "App/Mixed/**"
                targets: [App]
              - match: "App/Mixed/**"
                targets: [AppExtension]
                platformFilters: [ios]

            """)
        let choice = try configured.targets(for: "App/Mixed/New.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["App"], "rule 2, the first that sets targets")
        XCTAssertEqual(choice.source, .config(rule: 2, glob: "App/Mixed/**"))
        let filters = try configured.platformFilters(for: "App/Mixed/New.swift", kind: .source, target: target("App"), in: project)
        XCTAssertEqual(filters.value, ["tvos"], "rule 1, the first that sets platformFilters")
        XCTAssertEqual(filters.source, .config(rule: 1, glob: "App/**"))
    }

    // Spec: Explicitly no filter.
    func testAnEmptyListIsExplicitlyNoFilterAndSiblingsAreNotConsulted() throws {
        XCTAssertThrowsError(try Conventions().platformFilters(for: "App/Filtered/New.swift", kind: .source, target: target("App"), in: project))
        let configured = try conventions("rules:\n  - match: \"App/Filtered/**\"\n    platformFilters: []\n")
        let filters = try configured.platformFilters(for: "App/Filtered/New.swift", kind: .source, target: target("App"), in: project)
        XCTAssertEqual(filters.value, [])
        XCTAssertEqual(filters.source, .config(rule: 1, glob: "App/Filtered/**"))
        // Targets are still inferred: F1 and F2 are both in App.
        let choice = try configured.targets(for: "App/Filtered/New.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["App"])
        XCTAssertEqual(choice.source, .inferred(siblings: 2, directory: "App/Filtered"))
    }

    func testNoMatchingRuleFallsThroughToInference() throws {
        let configured = try conventions("rules:\n  - match: \"Tools/**\"\n    targets: [AppKit]\n  - match: \"App/tvOS/*.m\"\n    platformFilters: []\n")
        let choice = try configured.targets(for: "App/tvOS/TV3.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["App"])
        XCTAssertEqual(choice.source, .inferred(siblings: 2, directory: "App/tvOS"))
        let filters = try configured.platformFilters(for: "App/tvOS/TV3.swift", kind: .source, target: target("App"), in: project)
        XCTAssertEqual(filters.value, ["tvos"])
        XCTAssertEqual(filters.source, .inferred(siblings: 2, directory: "App/tvOS"))
        // A rule that matches but sets nothing relevant does not count either.
        let irrelevant = try conventions("rules:\n  - match: \"App/**\"\n    platformFilters: [ios]\n")
        XCTAssertEqual(try irrelevant.targets(for: "App/tvOS/TV3.swift", kind: .source, in: project).source, .inferred(siblings: 2, directory: "App/tvOS"))
        // Inference errors still arise when the configuration is silent.
        XCTAssertThrowsError(try configured.targets(for: "App/Mixed/New.swift", kind: .source, in: project))
    }

    // Spec: Precedence — Configuration resolves disagreement.
    func testConfigurationResolvesADisagreementWithoutInferring() throws {
        let configured = try conventions("rules:\n  - match: \"App/tvOS/**\"\n    platformFilters: [tvos]\n  - match: \"App/Mixed/**\"\n    targets: [App]\n")
        let choice = try configured.targets(for: "App/Mixed/New.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["App"])
        XCTAssertEqual(choice.source, .config(rule: 2, glob: "App/Mixed/**"))
        XCTAssertEqual(choice.extras.count, 0, "nothing was inferred, so there is no note")
        XCTAssertEqual(choice.source.description, "config, rule 2 \"App/Mixed/**\"")
        // Several targets, de-duplicated and sorted by name.
        let two = try conventions("rules:\n  - match: \"**\"\n    targets: [AppTests, App, AppTests]\n")
        XCTAssertEqual(try two.targets(for: "App/Mixed/New.swift", kind: .source, in: project).targets.map(\.name), ["App", "AppTests"])
        // A name the project lacks is the same error the flag raises (validation normally catches it first).
        XCTAssertThrowsError(try conventions("rules:\n  - match: \"**\"\n    targets: [Nope]\n").targets(for: "X.swift", kind: .source, in: project)) { error in
            XCTAssertEqual(error as? PlanError, .unknownTarget(name: "Nope", available: ["App", "AppExtension", "AppKit", "AppTests"]))
        }
    }

    // Spec: Precedence — Flag wins.
    func testAFlagWinsOverTheConfiguration() throws {
        let flags = Conventions.Flags(targets: ["AppTests"], platformFilters: ["macos"], phase: nil)
        let configured = try conventions("rules:\n  - match: \"App/Views/**\"\n    targets: [App]\n    platformFilters: [tvos]\n", flags: flags)
        let choice = try configured.targets(for: "App/Views/Bar.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["AppTests"])
        XCTAssertEqual(choice.source, .flag)
        let filters = try configured.platformFilters(for: "App/Views/Bar.swift", kind: .source, target: target("AppTests"), in: project)
        XCTAssertEqual(filters.value, ["macos"])
        XCTAssertEqual(filters.source, .flag)
        // Flags for one attribute leave the other to the configuration.
        let targetOnly = try conventions("rules:\n  - match: \"App/Views/**\"\n    targets: [App]\n    platformFilters: [tvos]\n", flags: Conventions.Flags(targets: ["AppTests"]))
        let mixed = try targetOnly.platformFilters(for: "App/Views/Bar.swift", kind: .source, target: target("AppTests"), in: project)
        XCTAssertEqual(mixed.value, ["tvos"])
        XCTAssertEqual(mixed.source, .config(rule: 1, glob: "App/Views/**"))
    }

    func testWithoutAConfigurationNothingChanges() throws {
        let plain = Conventions(flags: Conventions.Flags(), config: nil)
        XCTAssertEqual(try plain.targets(for: "App/tvOS/TV3.swift", kind: .source, in: project).source, .inferred(siblings: 2, directory: "App/tvOS"))
        XCTAssertEqual(try Conventions().platformFilters(for: "App/tvOS/TV3.swift", kind: .source, target: target("App"), in: project).value, ["tvos"])
    }
}
