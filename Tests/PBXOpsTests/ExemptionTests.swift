import Foundation
import XCTest
import PBXModel
@testable import PBXOps

/// Tasks 5.2 and 6.1: `lint.exempt` as a filter on findings (design D5) in
/// the rule set and in the runner's pre-write check.
final class ExemptionTests: XCTestCase {
    private func exemptions(_ yaml: String) throws -> Exemptions {
        Exemptions(try Config.parse(yaml, file: ".pbxedit.yml").lint.exempt)
    }

    // Spec: Orphans under a directory stay out of groups.
    func testAnExemptFindingIsSplitOffAndANonMatchingPathIsKept() throws {
        let project = try loadProject("rules/m3-orphan.pbxproj")
        let all = RuleSet.standard.evaluate(project)
        XCTAssertEqual(all.map(\.rule), [.M3])
        XCTAssertEqual(all[0].path, "AppTests/Views/FooTests.swift")
        let matching = try exemptions("lint:\n  exempt:\n    M3: [\"App/**\", \"AppTests/Views/**\"]\n")
        let split = matching.apply(to: all)
        XCTAssertEqual(split.kept, [])
        XCTAssertEqual(split.exempt, all)
        XCTAssertEqual(RuleSet.standard.evaluate(project, exemptions: matching), [])
        let other = try exemptions("lint:\n  exempt:\n    M3: [\"App/**\"]\n    M6: [\"**\"]\n")
        XCTAssertEqual(other.apply(to: all).kept, all, "a non-matching path is still reported")
        XCTAssertEqual(other.apply(to: all).exempt, [])
        XCTAssertEqual(RuleSet.standard.evaluate(project, exemptions: other), all)
        // The rule must match too: an M3 glob does not silence an M6.
        let m6 = Finding(rule: .M6, object: ObjectID("X"), path: "AppTests/Views/FooTests.swift", message: "")
        XCTAssertFalse(matching.exempts(m6))
        XCTAssertTrue(Exemptions([:]).isEmpty)
        XCTAssertFalse(matching.isEmpty)
    }

    func testAFindingWithoutAPathIsNeverExempt() throws {
        let exemptions = try exemptions("lint:\n  exempt:\n    D2: [\"**\"]\n")
        XCTAssertFalse(exemptions.exempts(Finding(rule: .D2, object: nil, path: nil, message: "")))
        XCTAssertTrue(exemptions.exempts(Finding(rule: .D2, object: nil, path: "Scripts/x.sh", message: "")))
    }

    // Spec: An M3 exemption governs add — Pre-write check honours the exemption.
    func testTheRunnerHonoursExemptionsBeforeAndAfterTheWrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pbxedit-exempt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("project.pbxproj")
        try Data(try Fixtures.load("add/app.pbxproj")).write(to: url)
        var runner = try OperationRunner(projectFile: url)
        // A plan that creates a reference with no group child: an orphan, by construction.
        var builder = PlanBuilder(project: runner.project)
        let id = builder.mint()
        builder.add(.createFileReference(id: id, path: "Tools/Build.swift", name: "Build.swift", sourceTree: "SOURCE_ROOT", lastKnownFileType: "sourcecode.swift"), touching: [id])
        builder.record(Change(path: "Tools/Build.swift", action: .createdFileReference, object: id, detail: "test"))
        let plan = builder.build()

        let refused = runner.run(plan, dryRun: true)
        XCTAssertEqual(refused.outcome, .violations(stage: .beforeWrite))
        XCTAssertEqual(refused.findings.map(\.rule), [.M3])
        XCTAssertEqual(refused.findings[0].object, id)

        runner.exemptions = try exemptions("lint:\n  exempt:\n    M3: [\"Tools/**\"]\n")
        let previewed = runner.run(plan, dryRun: true)
        XCTAssertEqual(previewed.outcome, .ok, "\(previewed.findings)")
        let written = runner.run(plan, dryRun: false)
        XCTAssertEqual(written.outcome, .ok, "the post-write check honours it too: \(written.findings)")
        XCTAssertTrue(written.modified)
        let reloaded = try XCTUnwrap(written.project)
        XCTAssertEqual(reloaded.parents(of: id).count, 0)
        XCTAssertEqual(reloaded.resolvedPath(of: id)?.description, "Tools/Build.swift")
        assertPlutilLints(try Array(Data(contentsOf: url)))
        // The same file, checked without the exemption, shows the orphan again: the exemption filters, it does not repair.
        XCTAssertEqual(RuleSet.standard.evaluate(reloaded).map(\.rule), [.M3])

        let unrelated = try exemptions("lint:\n  exempt:\n    M3: [\"App/**\"]\n")
        runner = try OperationRunner(projectFile: url)
        runner.exemptions = unrelated
        var again = PlanBuilder(project: runner.project)
        let second = again.mint()
        again.add(.createFileReference(id: second, path: "Tools/Other.swift", name: "Other.swift", sourceTree: "SOURCE_ROOT", lastKnownFileType: "sourcecode.swift"), touching: [second])
        XCTAssertEqual(runner.run(again.build(), dryRun: true).outcome, .violations(stage: .beforeWrite), "a glob that does not match does not exempt")
    }

    // Spec: An M3 exemption governs add — Exempt path (task 6.1, design D6), on the model.
    func testAnM3ExemptPathIsPlannedWithoutAGroup() throws {
        let project = try loadProject("add/app.pbxproj")
        let config = try Config.parse("rules:\n  - match: \"Tools/**\"\n    targets: [AppKit]\nlint:\n  exempt:\n    M3: [\"Tools/**\"]\n", file: ".pbxedit.yml")
        let conventions = Conventions(config: ConfigConventions(rules: config.rules))
        let exemptions = Exemptions(config.lint.exempt)
        let plan = try AddPlanner.plan(["Tools/Build.swift"], in: project, conventions: conventions, exemptions: exemptions)
        XCTAssertEqual(plan.changes.map(\.action), [.createdFileReference, .createdBuildFile, .addedPhaseEntry], "no group created or modified")
        let location = try XCTUnwrap(plan.decisions.first { $0.attribute == "location" })
        XCTAssertEqual(location.source, .exemption(rule: .M3, glob: "Tools/**"))
        XCTAssertEqual(location.source.description, "config, exempt M3 \"Tools/**\"")
        XCTAssertEqual(location.source.kind, "exemption")
        let result = try plan.apply(to: project)
        let reference = try XCTUnwrap(result.fileReferences(at: "Tools/Build.swift").first)
        XCTAssertEqual(reference.path, "Tools/Build.swift")
        XCTAssertEqual(reference.name, "Build.swift")
        XCTAssertEqual(reference.sourceTree, "SOURCE_ROOT")
        XCTAssertEqual(result.parents(of: reference.id).count, 0)
        XCTAssertEqual(result.membership(of: reference.id).targets.map(\.name), ["AppKit"])
        XCTAssertEqual(result.groups.count, project.groups.count, "no group created")
        for group in project.groups {
            XCTAssertEqual(result.group(group.id)?.children, group.children, "group \(group.id) unchanged")
        }
        // The rule set, with the same exemption, is clean over what was touched; without it, the orphan is the one finding.
        XCTAssertEqual(RuleSet.standard.evaluate(result, scope: plan.touched, exemptions: exemptions).filter { $0.severity == .error }, [])
        XCTAssertEqual(RuleSet.standard.evaluate(result, scope: plan.touched).map(\.rule), [.M3])
        assertPlutilLints(result.serialize())
        // Without the exemption the same add groups the file as before.
        let grouped = try AddPlanner.plan(["Tools/Build.swift"], in: project, conventions: conventions)
        XCTAssertEqual(grouped.changes.map(\.action), [.createdGroup, .createdFileReference, .addedChild, .createdBuildFile, .addedPhaseEntry])
        // An exemption that does not match changes nothing either.
        let other = try AddPlanner.plan(["Tools/Build.swift"], in: project, conventions: conventions, exemptions: Exemptions([.M3: [try PathGlob("App/**")]]))
        XCTAssertEqual(other.changes.map(\.action), grouped.changes.map(\.action))
    }
}
