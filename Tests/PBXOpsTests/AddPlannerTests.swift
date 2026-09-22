import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Tasks 5.1 and 5.2: the add planner's ensure semantics (design D3) and the
/// regression fixtures for the Motivation failures this change closes.
/// Every test applies the plan, asserts on the model, and asserts the rule
/// set is clean over the touched objects and `plutil -lint` passes.
final class AddPlannerTests: XCTestCase {
    private let views: ObjectID = "AA0000000000000000000003"
    private let appSources: ObjectID = "CC0000000000000000000001"
    private let extensionSources: ObjectID = "CC0000000000000000000004"

    private func plan(_ paths: [String], fixture: String = "add/app.pbxproj", flags: Conventions.Flags = Conventions.Flags()) throws -> (Plan, Project) {
        let project = try loadProject(fixture)
        let plan = try AddPlanner.plan(paths, in: project, conventions: Conventions(flags: flags), minter: IDMinter(generator: FixedGenerator()))
        return (plan, project)
    }

    /// Applies, checks, and returns the result with the file's membership.
    private func applied(_ plan: Plan, to project: Project, wholeProjectClean: Bool = true) throws -> Project {
        let result = try plan.apply(to: project)
        assertOperationClean(result, scope: plan.touched)
        if wholeProjectClean { XCTAssertEqual(RuleSet.standard.evaluate(result), []) }
        return result
    }

    private func created(_ plan: Plan, _ action: Change.Action) -> [ObjectID] {
        plan.changes.filter { $0.action == action }.map(\.object)
    }

    // Spec: New file (5.1) — and the same-basename regression (5.2): AppTests/Foo/Bar.swift exists.
    func testANewFileGetsReferenceGroupChildBuildFileAndPhaseEntry() throws {
        let (plan, project) = try plan(["App/Views/Bar.swift"])
        XCTAssertEqual(plan.steps.count, 4, "\(plan.steps)")
        let ref = try XCTUnwrap(created(plan, .createdFileReference).first)
        let buildFile = try XCTUnwrap(created(plan, .createdBuildFile).first)
        XCTAssertNotEqual(ref, "AA0000000000000000000150", "never the reference with the same basename elsewhere")
        XCTAssertEqual(plan.steps[0], .createFileReference(id: ref, path: "Bar.swift", name: nil, sourceTree: "<group>", lastKnownFileType: "sourcecode.swift"))
        XCTAssertEqual(plan.steps[1], .addChild(ref, to: views, position: .before("AA0000000000000000000120")), "in name order, before Foo.swift")
        XCTAssertEqual(plan.steps[2], .createBuildFile(id: buildFile, fileRef: ref, platformFilters: []))
        XCTAssertEqual(plan.steps[3], .addPhaseEntry(buildFile, to: appSources, position: .last))
        XCTAssertEqual(plan.decisions.map(\.attribute), ["phase", "location", "targets", "platformFilters"])
        XCTAssertEqual(plan.decisions.map(\.source), [.fileType, .structure, .inferred(siblings: 1, directory: "App/Views"), .inferred(siblings: 1, directory: "App/Views")])
        XCTAssertEqual(plan.decisions[2].value, "App")
        XCTAssertEqual(plan.notes, [])
        XCTAssertEqual(plan.touched, [ref, buildFile, views, appSources])
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.fileReferences(at: "App/Views/Bar.swift").map(\.id), [ref])
        XCTAssertEqual(result.buildFile(buildFile)?.fileRef, ref)
        XCTAssertEqual(result.phases(of: buildFile).map(\.id), [appSources], "the build file is in its phase (Motivation: build file with no phase entry)")
        let report = MembershipReport(project: result, path: "App/Views/Bar.swift")
        XCTAssertEqual(report.memberships.map { $0.target?.name }, ["App"])
        XCTAssertEqual(report.groupPath, "App/Views")
        XCTAssertEqual(result.membership(of: "AA0000000000000000000150").targets.map(\.name), ["AppTests"], "the other Bar.swift is untouched")
        XCTAssertEqual(result.buildFiles(for: "AA0000000000000000000150").count, 1)
    }

    // Spec: Re-add (5.1).
    func testReAddingACompleteMemberIsZeroSteps() throws {
        let (plan, project) = try plan(["App/Views/Foo.swift"])
        XCTAssertTrue(plan.isNoOp, "\(plan.steps)")
        XCTAssertEqual(plan.changes.map(\.action), [.reusedFileReference, .reusedBuildFile])
        XCTAssertEqual(plan.changes.map(\.object), ["AA0000000000000000000120", "BB0000000000000000000020"])
        XCTAssertTrue(plan.touched.contains("AA0000000000000000000120"), "a re-add is still checked")
        XCTAssertEqual(try plan.apply(to: project).serialize(), project.serialize())
    }

    // Spec: Reference exists without a group or phase entry (5.1); Motivation: reuse skipped the group child (5.2),
    // build file without phase entry (5.2); spec: Unrelated damage does not block.
    func testPartialMembershipIsCompletedWithExistingIDs() throws {
        let (plan, project) = try plan(["AppTests/Views/FooTests.swift"], fixture: "add/partial.pbxproj", flags: Conventions.Flags(targets: ["App"]))
        XCTAssertEqual(created(plan, .createdFileReference), [])
        XCTAssertEqual(created(plan, .createdBuildFile), [])
        XCTAssertEqual(created(plan, .createdGroup).count, 2, "AppTests and Views under the main group")
        XCTAssertEqual(plan.changes.filter { $0.action == .reusedFileReference }.map(\.object), ["AB12"])
        XCTAssertEqual(plan.changes.filter { $0.action == .reusedBuildFile }.map(\.object), ["BF01"])
        XCTAssertTrue(plan.steps.contains(.addPhaseEntry("BF01", to: "S001", position: .last)), "\(plan.steps)")
        XCTAssertEqual(plan.decisions.first { $0.attribute == "targets" }?.source, .flag)
        let result = try applied(plan, to: project, wholeProjectClean: false)
        XCTAssertEqual(result.parents(of: "AB12").count, 1)
        XCTAssertEqual(result.resolvedPath(of: result.parents(of: "AB12")[0].id), .relative("AppTests/Views"))
        XCTAssertEqual(result.fileReference("AB12")?.sourceTree, "SOURCE_ROOT", "the existing spelling is kept")
        XCTAssertEqual(result.phases(of: "BF01").map(\.id), ["S001"])
        XCTAssertEqual(result.buildFiles(for: "AB12").map(\.id), ["BF01"])
        XCTAssertEqual(result.fileReferences.count, project.fileReferences.count)
        let remaining = RuleSet.standard.evaluate(result)
        XCTAssertEqual(remaining.map(\.object), ["OR01", "OR02"], "the unrelated orphans are still there and did not block")
        let text = String(decoding: result.serialize(), as: UTF8.self)
        XCTAssertTrue(text.contains("\t\tBF01 /* FooTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = AB12 /* FooTests.swift */; };\n"),
                      "the definition line gains its annotation: \(text)")
    }

    // Spec: Add to a second target (5.1).
    func testASecondTargetGetsABuildFileAndNothingElseChanges() throws {
        let (plan, project) = try plan(["App/Services/Rate.swift"], flags: Conventions.Flags(targets: ["AppExtension"]))
        let buildFile = try XCTUnwrap(created(plan, .createdBuildFile).first)
        XCTAssertEqual(plan.steps, [
            .createBuildFile(id: buildFile, fileRef: "AA0000000000000000000230", platformFilters: []),
            .addPhaseEntry(buildFile, to: extensionSources, position: .last),
        ])
        XCTAssertEqual(plan.decisions.first { $0.attribute == "platformFilters" }?.source, .inferred(siblings: 1, directory: "App/Services"))
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.membership(of: "AA0000000000000000000230").targets.compactMap(\.name).sorted(), ["App", "AppExtension"])
        XCTAssertEqual(result.group("AA0000000000000000000013")?.children, project.group("AA0000000000000000000013")?.children)
        XCTAssertEqual(result.fileReference("AA0000000000000000000230"), project.fileReference("AA0000000000000000000230"))
    }

    // Spec: Collision with existing damage (5.2, Motivation: M4).
    func testAnM4CollisionAmongTouchedObjectsAborts() throws {
        let (plan, project) = try plan(["App/Foo.swift"], fixture: "add/m4-collision.pbxproj")
        XCTAssertEqual(created(plan, .createdBuildFile).count, 1)
        XCTAssertTrue(plan.touched.contains("AB12"))
        let result = try plan.apply(to: project)
        let findings = RuleSet.standard.evaluate(result, scope: plan.touched)
        XCTAssertEqual(findings.map(\.rule), [.M4])
        XCTAssertEqual(findings.first?.object, "AB13")
        XCTAssertEqual(findings.first?.related, ["AB12"])
    }

    // Spec: Groups are created as needed; Empty directory.
    func testMissingGroupsAreCreatedAndTargetsComeFromTheAncestor() throws {
        let (plan, project) = try plan(["App/Features/New/Thing.swift"])
        XCTAssertEqual(created(plan, .createdGroup).count, 2)
        XCTAssertEqual(plan.decisions.first { $0.attribute == "targets" }?.source, .inferred(siblings: 2, directory: "App"))
        XCTAssertEqual(plan.notes, ["App/Features/New/Thing.swift: 1 of 2 siblings in App is also a member of AppExtension; pass --target App --target AppExtension to join it too"])
        let result = try applied(plan, to: project)
        let report = MembershipReport(project: result, path: "App/Features/New/Thing.swift")
        XCTAssertEqual(report.groupPath, "App/Features/New")
        XCTAssertEqual(report.memberships.map { $0.target?.name }, ["App"])
        XCTAssertEqual(result.groups(at: "App/Features/New").count, 1)
    }

    // Spec: Some siblings are shared; Sorted group.
    func testSharedSiblingsMakeANoteAndTheChildIsInsertedInOrder() throws {
        let (plan, project) = try plan(["App/Services/New.swift"])
        let ref = try XCTUnwrap(created(plan, .createdFileReference).first)
        XCTAssertTrue(plan.steps.contains(.addChild(ref, to: "AA0000000000000000000013", position: .before("AA0000000000000000000230"))), "\(plan.steps)")
        XCTAssertEqual(plan.notes.count, 1)
        XCTAssertTrue(plan.notes[0].contains("1 of 3 siblings"), plan.notes[0])
        XCTAssertTrue(plan.notes[0].contains("AppExtension"), plan.notes[0])
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.group("AA0000000000000000000013")?.children, ["AA0000000000000000000232", "AA0000000000000000000231", ref, "AA0000000000000000000230"])
        XCTAssertEqual(result.membership(of: ref).targets.map(\.name), ["App"])
    }

    // Spec: Unanimous siblings; Platform directory.
    func testUnanimousSiblingsAndFilters() throws {
        let (plan, project) = try plan(["App/tvOS/TV3.swift"])
        let buildFile = try XCTUnwrap(created(plan, .createdBuildFile).first)
        XCTAssertEqual(plan.decisions.first { $0.attribute == "targets" }?.source, .inferred(siblings: 2, directory: "App/tvOS"))
        XCTAssertEqual(plan.decisions.first { $0.attribute == "platformFilters" }?.value, "App: tvos")
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.buildFile(buildFile)?.platformFilters, ["tvos"])
    }

    // Spec: No common target; Disagreement — the planner refuses.
    func testDisagreeingSiblingsRefuse() throws {
        XCTAssertThrowsError(try plan(["App/Mixed/New.swift"])) { error in
            guard case PlanError.noCommonTarget? = error as? PlanError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try plan(["App/Filtered/New.swift"])) { error in
            guard case PlanError.ambiguousPlatformFilters? = error as? PlanError else { return XCTFail("\(error)") }
        }
        // Flags resolve both.
        let (mixed, project) = try plan(["App/Mixed/New.swift", "App/Filtered/New.swift"], flags: Conventions.Flags(targets: ["App"], platformFilters: ["ios"]))
        XCTAssertEqual(created(mixed, .createdBuildFile).count, 2)
        let result = try applied(mixed, to: project)
        for path in ["App/Mixed/New.swift", "App/Filtered/New.swift"] {
            let report = MembershipReport(project: result, path: path)
            XCTAssertEqual(report.memberships.map(\.platformFilters), [["ios"]], path)
        }
    }

    // Spec: Override the target.
    func testTheTargetFlagReplacesInference() throws {
        let (plan, project) = try plan(["App/Views/Bar.swift"], flags: Conventions.Flags(targets: ["AppTests"]))
        XCTAssertEqual(plan.decisions.first { $0.attribute == "targets" }, Decision(path: "App/Views/Bar.swift", attribute: "targets", value: "AppTests", source: .flag))
        let result = try applied(plan, to: project)
        XCTAssertEqual(MembershipReport(project: result, path: "App/Views/Bar.swift").memberships.map { $0.target?.name }, ["AppTests"])
    }

    // Spec: Resource; Header; Project-only file; Unsorted group.
    func testPhaseFollowsTheFileType() throws {
        let (resource, project) = try plan(["App/Resources/Localizable.xcstrings"])
        let resourceRef = try XCTUnwrap(created(resource, .createdFileReference).first)
        let resourceBuildFile = try XCTUnwrap(created(resource, .createdBuildFile).first)
        XCTAssertEqual(resource.steps.last, .addPhaseEntry(resourceBuildFile, to: "CC0000000000000000000003", position: .last))
        var result = try applied(resource, to: project)
        XCTAssertEqual(result.fileReference(resourceRef)?.lastKnownFileType, "text.json.xcstrings")
        XCTAssertEqual(MembershipReport(project: result, path: "App/Resources/Localizable.xcstrings").memberships.map { $0.phase?.name }, ["Resources"])

        let (header, _) = try plan(["AppKit/Extra.h"])
        let headerBuildFile = try XCTUnwrap(created(header, .createdBuildFile).first)
        XCTAssertEqual(header.steps.last, .addPhaseEntry(headerBuildFile, to: "CC0000000000000000000008", position: .last))
        XCTAssertEqual(header.decisions.first { $0.attribute == "targets" }?.value, "AppKit")
        result = try applied(header, to: project)
        XCTAssertEqual(MembershipReport(project: result, path: "AppKit/Extra.h").memberships.map { $0.phase?.name }, ["Headers"])

        let (entitlements, _) = try plan(["App/App.entitlements"])
        let entitlementsRef = try XCTUnwrap(created(entitlements, .createdFileReference).first)
        XCTAssertEqual(entitlements.steps, [
            .createFileReference(id: entitlementsRef, path: "App.entitlements", name: nil, sourceTree: "<group>", lastKnownFileType: "text.plist.entitlements"),
            .addChild(entitlementsRef, to: "AA0000000000000000000002", position: .last),
        ], "no build file; last, because App's children are not sorted")
        XCTAssertEqual(entitlements.decisions.map(\.attribute), ["phase", "location"], "no target or filter decision for a project-only file")
        result = try applied(entitlements, to: project)
        let report = MembershipReport(project: result, path: "App/App.entitlements")
        XCTAssertTrue(report.member)
        XCTAssertEqual(report.memberships, [])
    }

    // Spec: Target has no such phase; unknown extension; `--phase` on an unknown extension.
    func testMissingPhaseAndUnknownTypeRefuse() throws {
        XCTAssertThrowsError(try plan(["AppTests/Foo/fixture.json"], flags: Conventions.Flags(targets: ["AppTests"]))) { error in
            XCTAssertEqual(error as? PlanError, .noSuchPhase(path: "AppTests/Foo/fixture.json", target: "AppTests", phase: "Resources"))
        }
        XCTAssertThrowsError(try plan(["App/data.bin"])) { error in
            XCTAssertEqual(error as? PlanError, .unknownFileType(path: "App/data.bin"))
        }
        let (forced, project) = try plan(["App/data.bin"], flags: Conventions.Flags(targets: ["App"], phase: .resources))
        let ref = try XCTUnwrap(created(forced, .createdFileReference).first)
        XCTAssertEqual(forced.decisions.first { $0.attribute == "phase" }?.source, .flag)
        let result = try applied(forced, to: project)
        XCTAssertEqual(result.fileReference(ref)?.lastKnownFileType, "file")
        XCTAssertEqual(MembershipReport(project: result, path: "App/data.bin").memberships.map { $0.phase?.name }, ["Resources"])
        // --phase none keeps a source out of every phase.
        let (none, _) = try plan(["App/Views/Bar.swift"], flags: Conventions.Flags(phase: .notBuilt))
        XCTAssertEqual(none.steps.count, 2)
    }

    // Spec: Pathless groups.
    func testANameOnlyGroupGetsASourceRootReference() throws {
        let (plan, project) = try plan(["AppTests/Views/BarTests.swift"])
        let ref = try XCTUnwrap(created(plan, .createdFileReference).first)
        XCTAssertEqual(plan.steps[0], .createFileReference(id: ref, path: "AppTests/Views/BarTests.swift", name: "BarTests.swift", sourceTree: "SOURCE_ROOT", lastKnownFileType: "sourcecode.swift"))
        XCTAssertEqual(plan.steps[1], .addChild(ref, to: "AA0000000000000000000011", position: .before("AA0000000000000000000140")))
        XCTAssertEqual(plan.decisions.first { $0.attribute == "targets" }?.value, "AppTests")
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.resolvedPath(of: ref), .relative("AppTests/Views/BarTests.swift"))
        XCTAssertEqual(result.groups(at: "AppTests/Views"), [], "no second Views group was planted")
        let text = String(decoding: result.serialize(), as: UTF8.self)
        XCTAssertTrue(text.contains("\t\t\(ref) /* BarTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = BarTests.swift; path = AppTests/Views/BarTests.swift; sourceTree = SOURCE_ROOT; };\n"), text)
    }

    // Spec: File in a synchronized folder.
    func testASynchronizedPathIsANoOpWithANote() throws {
        let (plan, project) = try plan(["App/Generated/User.swift"])
        XCTAssertTrue(plan.isNoOp)
        XCTAssertEqual(plan.changes, [Change(path: "App/Generated/User.swift", action: .synchronized, object: "AA0000000000000000000301",
                                             detail: "already a member via synchronized group App/Generated (AA0000000000000000000301)")])
        XCTAssertEqual(plan.decisions, [])
        XCTAssertEqual(try plan.apply(to: project).serialize(), project.serialize())
    }

    // Several paths are one plan; two into one new directory share one group.
    func testSeveralPathsFormOnePlan() throws {
        let (plan, project) = try plan(["App/Features/A.swift", "App/Features/B.swift", "App/Views/Foo.swift"])
        XCTAssertEqual(created(plan, .createdGroup).count, 1, "one Features group for both")
        XCTAssertEqual(created(plan, .createdFileReference).count, 2)
        XCTAssertEqual(created(plan, .createdBuildFile).count, 2)
        let result = try applied(plan, to: project)
        let features = try XCTUnwrap(result.groups(at: "App/Features").first)
        XCTAssertEqual(features.children.count, 2)
        XCTAssertEqual(features.children.map { result.annotation(for: $0) }, ["A.swift", "B.swift"])
        XCTAssertEqual(MembershipReport(project: result, path: "App/Features/B.swift").memberships.map { $0.target?.name }, ["App"])
    }

    // Plans mint distinct, collision-checked 24-hex IDs.
    func testMintedIDsAreFreshAndHex() throws {
        let project = try loadProject("add/app.pbxproj")
        let plan = try AddPlanner.plan(["App/Views/Bar.swift", "App/Views/Baz.swift"], in: project, conventions: Conventions())
        let ids = plan.changes.filter { [.createdFileReference, .createdBuildFile].contains($0.action) }.map(\.object)
        XCTAssertEqual(Set(ids).count, 4)
        for id in ids {
            XCTAssertEqual(id.rawValue.count, 24)
            XCTAssertTrue(id.rawValue.allSatisfy { "0123456789ABCDEF".contains($0) }, id.rawValue)
            XCTAssertFalse(project.contains(id))
        }
    }
}
