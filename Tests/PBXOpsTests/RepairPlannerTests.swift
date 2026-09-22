import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Tasks 1.1, 3.1, 4.1 and 5.1: `RepairPlanner` and its three fixers on
/// `Tests/Fixtures/repair/app.pbxproj`, the `add/app.pbxproj` project plus
/// M1, M2 and M3 damage of every fixable and not-fixable shape and one S2
/// that remains. Every test applies the plan, asserts on the model, asserts
/// the rule set is clean over the touched objects, that no finding appeared
/// and every repaired one vanished, and that `plutil -lint` passes.
final class RepairPlannerTests: XCTestCase {
    // The fixture's damaged objects.
    private let rate2BuildFile: ObjectID = "BB0000000000000000000400"      // M1, fixable: joins App
    private let mixed3BuildFile: ObjectID = "BB0000000000000000000401"     // M1, siblings disagree
    private let fixtureBuildFile: ObjectID = "BB0000000000000000000402"    // M1, no sibling / no phase in AppTests
    private let twiceBuildFile: ObjectID = "BB0000000000000000000403"      // M1, in two phases
    private let deadBuildFile: ObjectID = "BB0000000000000000000404"       // M1, dangling fileRef: deleted
    private let missingBuildFile: ObjectID = "BB0000000000000000000405"    // M2, dangling fileRef in a phase
    private let appKitSources: ObjectID = "CC0000000000000000000007"       // M2, lists DEAD0001
    private let appSources: ObjectID = "CC0000000000000000000001"
    private let baz: ObjectID = "AA0000000000000000000406"                 // M3, SOURCE_ROOT into Views
    private let a: ObjectID = "AA0000000000000000000407"                   // M3, App/Features (no group)
    private let c: ObjectID = "AA0000000000000000000408"
    private let b: ObjectID = "AA0000000000000000000409"
    private let old: ObjectID = "AA0000000000000000000410"                 // M3, <group> with a directory
    private let readme: ObjectID = "AA0000000000000000000411"              // M3, <group> at the root
    private let dup: ObjectID = "AA0000000000000000000412"                 // M3, two parents
    private let gen: ObjectID = "AA0000000000000000000413"                 // M3, Tools/Generated (no groups)
    private let frameworksGroup: ObjectID = "AA0000000000000000000007"     // S2 that remains
    private let mainGroup: ObjectID = "AA0000000000000000000001"
    private let app: ObjectID = "AA0000000000000000000002"
    private let views: ObjectID = "AA0000000000000000000003"
    private let foo: ObjectID = "AA0000000000000000000120"
    private let twice: ObjectID = "AA0000000000000000000403"

    private func findings(_ project: Project, exemptions: Exemptions? = nil) -> [Finding] {
        RuleSet.standard.evaluate(project, exemptions: exemptions)
    }

    private func repair(_ project: Project, conventions: Conventions = Conventions(), exemptions: Exemptions? = nil) -> RepairPlan {
        RepairPlanner.plan(findings(project, exemptions: exemptions), in: project, conventions: conventions, exemptions: exemptions,
                           minter: IDMinter(generator: FixedGenerator()))
    }

    /// Applies the plan and asserts the invariants every repair keeps: the
    /// whole-project comparison of design D5 — not the scoped check, which
    /// would refuse any repair touching a phase that carries unrelated,
    /// unfixable damage (the build file listed in two phases names App's
    /// Sources phase, where Rate2.swift is listed) — and `plutil -lint`.
    @discardableResult
    private func applied(_ repair: RepairPlan, to project: Project, exemptions: Exemptions? = nil,
                         file: StaticString = #filePath, line: UInt = #line) throws -> Project {
        let result = try repair.plan.apply(to: project)
        assertPlutilLints(result.serialize(), file: file, line: line)
        let before = Set(findings(project, exemptions: exemptions).map(\.identity))
        let after = findings(result, exemptions: exemptions)
        let survivors = repair.repaired.filter { finding in after.contains { $0.identity == finding.identity } }
        XCTAssertEqual(survivors, [], "repaired findings still reported", file: file, line: line)
        let appeared = after.filter { !before.contains($0.identity) }
        XCTAssertEqual(appeared, [], "findings that were absent before", file: file, line: line)
        XCTAssertEqual(result.fileReferences.count, project.fileReferences.count, "no reference created or deleted", file: file, line: line)
        XCTAssertLessThanOrEqual(result.buildFiles.count, project.buildFiles.count, "no build file created", file: file, line: line)
        return result
    }

    private func objects(_ findings: [Finding]) -> [ObjectID] { findings.compactMap(\.object) }

    // MARK: Task 1.1 — the framework

    func testFixableFindingsArePlannedAndTheRestCarryAReason() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        XCTAssertEqual(Set(objects(repair.repaired)),
                       [appKitSources, missingBuildFile, rate2BuildFile, deadBuildFile, baz, a, b, c, readme, gen])
        XCTAssertEqual(Set(objects(repair.notFixable.map(\.finding))), [mixed3BuildFile, fixtureBuildFile, twiceBuildFile, old, dup])
        for entry in repair.notFixable { XCTAssertFalse(entry.reason.isEmpty, "\(entry.finding)") }
        // Findings of other rules are neither repaired nor listed as not fixable.
        XCTAssertFalse(objects(repair.repaired).contains(frameworksGroup))
        XCTAssertFalse(objects(repair.notFixable.map(\.finding)).contains(frameworksGroup))
        XCTAssertEqual(RepairPlanner.fixableRules, [.M2, .M1, .M3])
        try applied(repair, to: project)
    }

    func testOrphansSharingADirectoryProduceOneGroupAndThePlanIsKeyedByFinding() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        let created = repair.plan.changes.filter { $0.action == .createdGroup }
        XCTAssertEqual(created.count, 3, "Features, Tools and Generated: \(created)")
        XCTAssertEqual(created.map(\.path), ["M3 \(a)", "M3 \(gen)", "M3 \(gen)"], "the first orphan into a directory creates its group")
        // Changes and decisions are keyed by the finding.
        let bazFinding = try XCTUnwrap(repair.repaired.first { $0.object == baz })
        XCTAssertEqual(RepairPlan.key(for: bazFinding), "M3 \(baz)")
        XCTAssertEqual(repair.changes(for: bazFinding).map(\.action), [.addedChild])
        XCTAssertEqual(repair.changes(for: bazFinding).map(\.object), [views])
        let bFinding = try XCTUnwrap(repair.repaired.first { $0.object == b })
        XCTAssertEqual(repair.changes(for: bFinding).map(\.action), [.addedChild], "the group was planned by A.swift")
        XCTAssertEqual(repair.decisions(for: bFinding), [])
        let rate2Finding = try XCTUnwrap(repair.repaired.first { $0.object == rate2BuildFile })
        XCTAssertEqual(repair.decisions(for: rate2Finding).map(\.attribute), ["targets"])
        XCTAssertEqual(repair.decisions(for: rate2Finding).first?.source, .inferred(siblings: 3, directory: "App/Services"))
    }

    func testTheOrderIsM2ThenM1ThenM3InObjectOrderAndDeterministic() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        XCTAssertEqual(repair.repaired.map(\.rule), [.M2, .M2, .M1, .M1, .M3, .M3, .M3, .M3, .M3, .M3])
        XCTAssertEqual(objects(repair.repaired), [missingBuildFile, appKitSources, rate2BuildFile, deadBuildFile, baz, a, c, b, readme, gen])
        XCTAssertEqual(repair.notFixable.map(\.finding.rule), [.M1, .M1, .M1, .M3, .M3])
        // The first steps are the M2 removals, the last the M3 children.
        XCTAssertEqual(repair.plan.steps.first, .removePhaseEntry(missingBuildFile, from: appSources))
        guard case .addChild? = repair.plan.steps.last else { return XCTFail("\(String(describing: repair.plan.steps.last))") }
        XCTAssertEqual(self.repair(project).plan, repair.plan, "two runs give identical steps")
    }

    // MARK: Task 3.1 — M2

    func testADanglingEntryIsRemovedAloneAndADeadBuildFileIsRemovedAndDeleted() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        let result = try applied(repair, to: project)
        XCTAssertEqual(result.buildPhase(appKitSources)?.files, ["BB0000000000000000000151"], "the entry is gone, nothing else in the phase changed")
        XCTAssertFalse(result.contains(missingBuildFile))
        XCTAssertFalse(result.buildPhase(appSources)?.files.contains(missingBuildFile) ?? true)
        let entryFinding = try XCTUnwrap(repair.repaired.first { $0.object == appKitSources })
        XCTAssertEqual(repair.changes(for: entryFinding).map(\.action), [.removedPhaseEntry])
        let deadFinding = try XCTUnwrap(repair.repaired.first { $0.object == missingBuildFile })
        XCTAssertEqual(repair.changes(for: deadFinding).map(\.action), [.removedPhaseEntry, .deletedObject])
        XCTAssertEqual(repair.plan.deletedObjectsMentioned(in: result.serialize()), [])
        // The two M2 scenarios on the rule fixture: the phase ends up empty.
        let small = try loadProject("rules/m2-dangling-entry.pbxproj")
        let smallRepair = self.repair(small)
        XCTAssertEqual(objects(smallRepair.repaired), ["BF01", "S001"])
        let repaired = try applied(smallRepair, to: small)
        XCTAssertEqual(repaired.buildPhase("S001")?.files, [])
        XCTAssertFalse(repaired.contains("BF01"))
        XCTAssertEqual(findings(repaired), [], "the fixture is clean afterwards")
    }

    func testEveryListingOfADanglingEntryIsRemoved() throws {
        var source = try Fixtures.text("repair/app.pbxproj")
        source = source.replacingOccurrences(of: "\t\t\t\tDEAD0001 /* Gone.swift in Sources */,\n",
                                             with: "\t\t\t\tDEAD0001 /* Gone.swift in Sources */,\n\t\t\t\tDEAD0001 /* Gone.swift in Sources */,\n")
        let project = try Project.load(Array(source.utf8))
        XCTAssertTrue(findings(project).contains { $0.rule == .S3 && $0.object == appKitSources }, "the double listing is an S3 too")
        let repair = repair(project)
        let result = try applied(repair, to: project)
        XCTAssertEqual(result.buildPhase(appKitSources)?.files, ["BB0000000000000000000151"])
        XCTAssertFalse(findings(result).contains { $0.rule == .S3 }, "the S3 vanished as a side effect, which is allowed")
    }

    // MARK: Task 4.1 — M1 (Motivation: "A PBXBuildFile created with no build-phase entry, so tests silently never ran")

    func testABuildFileInNoPhaseJoinsTheUnanimousTargetWithItsOwnID() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        XCTAssertEqual(repair.plan.changes.filter { [.createdBuildFile, .createdFileReference].contains($0.action) }, [], "zero objects created")
        let finding = try XCTUnwrap(repair.repaired.first { $0.object == rate2BuildFile })
        XCTAssertEqual(repair.changes(for: finding).map(\.action), [.addedPhaseEntry])
        XCTAssertTrue(repair.plan.steps.contains(.addPhaseEntry(rate2BuildFile, to: appSources, position: .last)), "\(repair.plan.steps)")
        let result = try applied(repair, to: project)
        XCTAssertEqual(result.phases(of: rate2BuildFile).map(\.id), [appSources])
        XCTAssertEqual(PlatformFilters.read(from: try XCTUnwrap(result.buildFile(rate2BuildFile))), ["ios"], "the existing filter is preserved")
        XCTAssertEqual(result.buildFile(rate2BuildFile)?.platformFilter, "ios", "in its own spelling: a repair never re-spells")
        let report = MembershipReport(project: result, path: "App/Services/Rate2.swift")
        XCTAssertEqual(report.memberships.map { $0.target?.name }, ["App"])
        XCTAssertEqual(report.memberships.map(\.buildFile), [rate2BuildFile])
        let text = String(decoding: result.serialize(), as: UTF8.self)
        XCTAssertTrue(text.contains("\t\tBB0000000000000000000400 /* Rate2.swift in Sources */ = {isa = PBXBuildFile;"), "the definition line gains its annotation")
        // The note add would print about the extra target is kept as a note on the finding.
        XCTAssertTrue(repair.plan.notes.contains { $0.hasPrefix("M1 \(rate2BuildFile): 1 of 3 siblings in App/Services is also a member of AppExtension") }, "\(repair.plan.notes)")
    }

    func testAmbiguousMissingPhaseAndDoublyListedBuildFilesAreNotFixable() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        func reason(_ id: ObjectID) throws -> String {
            try XCTUnwrap(repair.notFixable.first { $0.finding.object == id }, "\(id) should not be fixable").reason
        }
        XCTAssertEqual(try reason(mixed3BuildFile), "the siblings in App/Mixed have no target in common: App (1), AppExtension (1)")
        XCTAssertEqual(try reason(fixtureBuildFile), "no file of the same kind in its directory or any ancestor to infer a target from")
        XCTAssertEqual(try reason(twiceBuildFile), "listed in 2 build phases; which one is right is a human decision")
        // With a configured target that lacks the phase.
        let rule = try Config.Rule(position: 1, line: 3, match: PathGlob("AppTests/**"), targets: ["AppTests"])
        let configured = self.repair(project, conventions: Conventions(config: ConfigConventions(rules: [rule])))
        XCTAssertEqual(try XCTUnwrap(configured.notFixable.first { $0.finding.object == fixtureBuildFile }).reason, "target AppTests has no Resources phase")
        // Several configured targets are not a choice either.
        let two = try Config.Rule(position: 1, line: 3, match: PathGlob("App/Mixed/**"), targets: ["App", "AppExtension"])
        let several = self.repair(project, conventions: Conventions(config: ConfigConventions(rules: [two])))
        XCTAssertEqual(try XCTUnwrap(several.notFixable.first { $0.finding.object == mixed3BuildFile }).reason,
                       "the configuration (rule 1 \"App/Mixed/**\") names 2 targets, App and AppExtension; one orphaned build file can belong to only one of them")
        // The doubly listed build file is not touched at all.
        let result = try applied(repair, to: project)
        XCTAssertEqual(result.phases(of: twiceBuildFile).map(\.id), [appSources, "CC0000000000000000000004"])
        XCTAssertEqual(result.phases(of: mixed3BuildFile), [])
    }

    func testADeadBuildFileInNoPhaseIsDeleted() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        let finding = try XCTUnwrap(repair.repaired.first { $0.object == deadBuildFile })
        XCTAssertEqual(repair.changes(for: finding).map(\.action), [.deletedObject])
        let result = try applied(repair, to: project)
        XCTAssertFalse(result.contains(deadBuildFile))
        XCTAssertEqual(repair.plan.deletedObjectsMentioned(in: result.serialize()), [])
    }

    func testATargetAlreadyBuildingTheFileIsNotFixable() throws {
        // Foo.swift gains a second build file in no phase; App already builds it.
        var source = try Fixtures.text("repair/app.pbxproj")
        source = source.replacingOccurrences(
            of: "/* End PBXBuildFile section */",
            with: "\t\tBB0000000000000000000499 = {isa = PBXBuildFile; fileRef = AA0000000000000000000120 /* Foo.swift */; };\n/* End PBXBuildFile section */")
        let project = try Project.load(Array(source.utf8))
        let repair = repair(project)
        let entry = try XCTUnwrap(repair.notFixable.first { $0.finding.object == "BB0000000000000000000499" })
        XCTAssertEqual(entry.reason, "the inferred target App already builds the file (build file BB0000000000000000000020); a second listing would be an M5")
        try applied(repair, to: project)
    }

    // MARK: Task 5.1 — M3

    func testAnOrphanJoinsItsExistingGroupInNameOrderAsOneLine() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        XCTAssertTrue(repair.plan.steps.contains(.addChild(baz, to: views, position: .before(foo.rawValue))), "\(repair.plan.steps)")
        let result = try applied(repair, to: project)
        XCTAssertEqual(result.group(views)?.children, [baz, foo, twice])
        XCTAssertEqual(result.fileReference(baz), project.fileReference(baz), "path, name and sourceTree are byte-identical")
        XCTAssertEqual(result.resolvedPath(of: baz), .relative("App/Views/Baz.swift"))
        XCTAssertEqual(result.parents(of: baz).map(\.id), [views])
        // On the rule fixture the whole repair is one added line.
        let small = try loadProject("rules/m3-orphan.pbxproj")
        let smallRepair = self.repair(small)
        let repaired = try applied(smallRepair, to: small)
        let diff = lineDiff(String(decoding: small.serialize(), as: UTF8.self), String(decoding: repaired.serialize(), as: UTF8.self))
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.added.count, 1 + 2 * 8, "one children line in the main group, plus the groups AppTests and Views (eight lines each, their child included)")
        XCTAssertTrue(diff.added.contains("\t\t\t\tAB12 /* FooTests.swift */,\n"), "\(diff.added)")
        XCTAssertEqual(findings(repaired), [])
    }

    func testOrphansInADirectoryWithNoGroupShareOneNewGroupInNameOrder() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        let result = try applied(repair, to: project)
        let features = try XCTUnwrap(result.groups(at: "App/Features").first)
        XCTAssertEqual(features.path, "Features")
        XCTAssertNil(features.name)
        XCTAssertEqual(features.sourceTree, "<group>")
        XCTAssertEqual(features.children, [a, b, c], "name order, not object order")
        XCTAssertEqual(result.group(app)?.children.last, features.id, "App's children are not sorted: last")
        XCTAssertEqual(result.groups(at: "App/Features").count, 1)
        for id in [a, b, c] {
            XCTAssertEqual(result.fileReference(id), project.fileReference(id))
            XCTAssertEqual(result.resolvedPath(of: id), project.resolvedPath(of: id))
        }
        // Two missing chain links: Tools, then Generated, under the main group.
        let generated = try XCTUnwrap(result.groups(at: "Tools/Generated").first)
        XCTAssertEqual(generated.children, [gen])
        XCTAssertEqual(result.parents(of: generated.id).map { result.resolvedPath(of: $0.id) }, [.relative("Tools")])
        XCTAssertEqual(result.group(mainGroup)?.children.last, result.groups(at: "Tools").first?.id, "the main group is not sorted: last, after README.md")
    }

    func testAGroupRelativeOrphanAtTheRootJoinsTheMainGroup() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        let result = try applied(repair, to: project)
        XCTAssertEqual(result.parents(of: readme).map(\.id), [mainGroup])
        XCTAssertEqual(result.resolvedPath(of: readme), .relative("README.md"))
        XCTAssertEqual(result.fileReference(readme), project.fileReference(readme))
    }

    func testOrphansThatCannotBeGroupedSafelyAreNotFixable() throws {
        let project = try loadProject("repair/app.pbxproj")
        let repair = repair(project)
        func reason(_ id: ObjectID) throws -> String {
            try XCTUnwrap(repair.notFixable.first { $0.finding.object == id }, "\(id) should not be fixable").reason
        }
        XCTAssertEqual(try reason(old), "its <group>-relative path App/Legacy/Old.swift would resolve to App/Legacy/App/Legacy/Old.swift under the group for App/Legacy; pbxedit remove App/Legacy/Old.swift, then pbxedit add App/Legacy/Old.swift, re-spells it")
        XCTAssertEqual(try reason(dup), "a child of 2 groups, AA0000000000000000000015 and AA0000000000000000000016; which one is right is a human decision")
        XCTAssertEqual(repair.plan.changes.filter { $0.action == .createdGroup && $0.detail.contains("Legacy") }, [], "no group is created for a refused orphan")
        let result = try applied(repair, to: project)
        XCTAssertEqual(result.parents(of: old), [])
        XCTAssertEqual(result.parents(of: dup).count, 2)
        // A reference that is not project-relative.
        var source = try Fixtures.text("rules/m3-orphan.pbxproj")
        source = source.replacingOccurrences(of: "path = AppTests/Views/FooTests.swift; sourceTree = SOURCE_ROOT;",
                                             with: "path = AppTests/Views/FooTests.swift; sourceTree = SDKROOT;")
        let sdk = try Project.load(Array(source.utf8))
        let sdkRepair = self.repair(sdk)
        XCTAssertEqual(sdkRepair.repaired, [])
        XCTAssertEqual(sdkRepair.notFixable.map(\.reason), ["not project-relative (sourceTree = SDKROOT); no group stands for its directory"])
        XCTAssertTrue(sdkRepair.plan.isNoOp)
    }

    // MARK: Task 7.1 — exemptions

    func testAnExemptOrphanIsNeitherRepairedNorGivenAGroup() throws {
        let project = try loadProject("repair/app.pbxproj")
        let exemptions = Exemptions([.M3: [try PathGlob("Tools/Generated/**")]])
        let repair = repair(project, exemptions: exemptions)
        XCTAssertFalse(objects(repair.repaired).contains(gen))
        XCTAssertFalse(objects(repair.notFixable.map(\.finding)).contains(gen))
        XCTAssertEqual(repair.plan.changes.filter { $0.action == .createdGroup }.count, 1, "Features only")
        let result = try applied(repair, to: project, exemptions: exemptions)
        XCTAssertEqual(result.parents(of: gen), [])
        XCTAssertEqual(result.groups(at: "Tools"), [])
        // The planner also drops an exempt finding it is handed, so a caller cannot repair one by accident.
        let handed = RepairPlanner.plan(findings(project), in: project, exemptions: exemptions)
        XCTAssertFalse(objects(handed.repaired).contains(gen))
    }
}
