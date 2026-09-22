import XCTest
import PBXModel
@testable import PBXOps

/// Task 4.1: sibling inference (design D4) on `add/app.pbxproj`.
final class InferenceTests: XCTestCase {
    private var project: Project!
    private let conventions = Conventions()

    override func setUpWithError() throws {
        project = try loadProject("add/app.pbxproj")
    }

    private func target(_ name: String) -> Target {
        project.targets.first { $0.name == name }!
    }

    // Spec: Unanimous siblings.
    func testUnanimousSiblings() throws {
        let choice = try conventions.targets(for: "App/tvOS/TV3.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["App"])
        XCTAssertEqual(choice.source, .inferred(siblings: 2, directory: "App/tvOS"))
        XCTAssertEqual(choice.extras.count, 0)
    }

    // Spec: Some siblings are shared.
    func testSharedSiblingsAreANoteNotAMember() throws {
        let choice = try conventions.targets(for: "App/Services/New.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["App"])
        XCTAssertEqual(choice.source, .inferred(siblings: 3, directory: "App/Services"))
        XCTAssertEqual(choice.extras.map { ($0.target.name, $0.count) }.map { "\($0.0 ?? "") \($0.1)" }, ["AppExtension 1"])
    }

    // Spec: Empty directory.
    func testAnEmptyDirectoryInfersFromTheNearestAncestorWithSiblings() throws {
        let choice = try conventions.targets(for: "App/Features/New/Thing.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["App"])
        XCTAssertEqual(choice.source, .inferred(siblings: 2, directory: "App"), "AppMain.swift and Shared.swift")
        XCTAssertEqual(choice.extras.map(\.target.name), ["AppExtension"])
    }

    // Spec: No common target.
    func testNoCommonTargetIsAnErrorListingTheVariants() throws {
        XCTAssertThrowsError(try conventions.targets(for: "App/Mixed/New.swift", kind: .source, in: project)) { error in
            guard case PlanError.noCommonTarget(let path, let directory, let variants)? = error as? PlanError else { return XCTFail("\(error)") }
            XCTAssertEqual(path, "App/Mixed/New.swift")
            XCTAssertEqual(directory, "App/Mixed")
            XCTAssertEqual(variants, [PlanError.TargetVariant(targets: ["App"], count: 1), PlanError.TargetVariant(targets: ["AppExtension"], count: 1)])
            XCTAssertTrue("\(error)".contains("--target"), "\(error)")
        }
    }

    func testNoSiblingAnywhereIsAnError() throws {
        XCTAssertThrowsError(try conventions.targets(for: "Docs/Guide.md", kind: .projectOnly, in: project)) { error in
            XCTAssertEqual(error as? PlanError, .noSiblings(path: "Docs/Guide.md"))
        }
        // Siblings are of the same kind: a source among resources walks up to App.
        let source = try conventions.targets(for: "App/Resources/X.swift", kind: .source, in: project)
        XCTAssertEqual(source.source, .inferred(siblings: 2, directory: "App"))
        let resource = try conventions.targets(for: "App/Resources/X.xcstrings", kind: .resource, in: project)
        XCTAssertEqual(resource.source, .inferred(siblings: 1, directory: "App/Resources"), "Assets.xcassets")
    }

    func testTheFileItselfIsNotItsOwnSibling() throws {
        let choice = try conventions.targets(for: "App/Views/Foo.swift", kind: .source, in: project)
        XCTAssertEqual(choice.source, .inferred(siblings: 2, directory: "App"), "Foo.swift alone in App/Views does not count; the walk goes up")
    }

    // Spec: Platform directory.
    func testUnanimousPlatformFilters() throws {
        let filters = try conventions.platformFilters(for: "App/tvOS/TV3.swift", kind: .source, target: target("App"), in: project)
        XCTAssertEqual(filters.value, ["tvos"])
        XCTAssertEqual(filters.source, .inferred(siblings: 2, directory: "App/tvOS"))
        let none = try conventions.platformFilters(for: "App/Services/New.swift", kind: .source, target: target("App"), in: project)
        XCTAssertEqual(none.value, [])
        XCTAssertEqual(none.source, .inferred(siblings: 3, directory: "App/Services"))
    }

    // Spec: Disagreement.
    func testDisagreeingPlatformFiltersAreAnError() throws {
        XCTAssertThrowsError(try conventions.platformFilters(for: "App/Filtered/New.swift", kind: .source, target: target("App"), in: project)) { error in
            guard case PlanError.ambiguousPlatformFilters(let path, let targetName, let directory, let variants)? = error as? PlanError else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(path, "App/Filtered/New.swift")
            XCTAssertEqual(targetName, "App")
            XCTAssertEqual(directory, "App/Filtered")
            XCTAssertEqual(variants, [PlanError.FilterVariant(filters: [], count: 1), PlanError.FilterVariant(filters: ["ios"], count: 1)])
            XCTAssertTrue("\(error)".contains("--platform"), "\(error)")
        }
    }

    func testNoSiblingInTheTargetMeansNoFilters() throws {
        let filters = try conventions.platformFilters(for: "App/Services/Rate.swift", kind: .source, target: target("AppExtension"), in: project)
        XCTAssertEqual(filters.value, [], "Cache.swift is the one sibling in AppExtension and has no filter")
        XCTAssertEqual(filters.source, .inferred(siblings: 1, directory: "App/Services"))
        let fresh = try conventions.platformFilters(for: "App/tvOS/TV3.swift", kind: .source, target: target("AppTests"), in: project)
        XCTAssertEqual(fresh.value, [])
        XCTAssertEqual(fresh.source, .inferred(siblings: 0, directory: "App/tvOS"))
    }

    // Spec: Explicit options override inference.
    func testFlagsReplaceInference() throws {
        let flagged = Conventions(flags: Conventions.Flags(targets: ["AppTests"], platformFilters: ["ios", "macos"], phase: .resources))
        let choice = try flagged.targets(for: "App/Mixed/New.swift", kind: .source, in: project)
        XCTAssertEqual(choice.targets.map(\.name), ["AppTests"])
        XCTAssertEqual(choice.source, .flag)
        let filters = try flagged.platformFilters(for: "App/Filtered/New.swift", kind: .source, target: target("App"), in: project)
        XCTAssertEqual(filters.value, ["ios", "macos"])
        XCTAssertEqual(filters.source, .flag)
        XCTAssertEqual(flagged.phase(for: "X.swift", kind: .source).value, .resources)
        XCTAssertEqual(flagged.phase(for: "X.swift", kind: .source).source, .flag)
        XCTAssertEqual(conventions.phase(for: "X.swift", kind: .source).value, .sources)
        XCTAssertEqual(conventions.phase(for: "X.swift", kind: .source).source, .fileType)
        XCTAssertThrowsError(try Conventions(flags: Conventions.Flags(targets: ["Nope"])).targets(for: "X.swift", kind: .source, in: project)) { error in
            XCTAssertEqual(error as? PlanError, .unknownTarget(name: "Nope", available: ["App", "AppExtension", "AppKit", "AppTests"]))
        }
    }
}
