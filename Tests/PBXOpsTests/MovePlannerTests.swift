import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Tasks 1.1–5.3: the move planner (design D1–D6). Every test applies the
/// plan, asserts on the model, asserts the rule set is clean over the touched
/// objects (and the whole project where the fixture starts clean), and that
/// `plutil -lint` passes.
final class MovePlannerTests: XCTestCase {
    private let views: ObjectID = "AA0000000000000000000003"
    private let features: ObjectID = "AA0000000000000000000017"
    private let appGroup: ObjectID = "AA0000000000000000000002"
    private let appTests: ObjectID = "AA0000000000000000000005"
    private let testsViews: ObjectID = "AA0000000000000000000011"
    private let state: ObjectID = "AA0000000000000000000022"
    private let testsServices: ObjectID = "AA0000000000000000000027"
    private let models: ObjectID = "AA0000000000000000000026"
    private let foo: ObjectID = "AA0000000000000000000120"
    private let fooBuildFile: ObjectID = "BB0000000000000000000020"
    private let fooTests: ObjectID = "AA0000000000000000000140"
    private let stateTests: ObjectID = "AA0000000000000000000340"
    private let old: ObjectID = "AA0000000000000000000380"
    private let appSources: ObjectID = "CC0000000000000000000001"
    private let appTestsSources: ObjectID = "CC0000000000000000000005"
    private let slowTestsSources: ObjectID = "CC0000000000000000000010"

    /// Plans a move on the fixture with a disk holding exactly `files`
    /// (the destination alone, unless said otherwise).
    private func plan(_ from: String, _ to: String, project: Project? = nil, files: [String]? = nil,
                      flags: Conventions.Flags = Conventions.Flags(), keepMembership: Bool = false,
                      exemptions: Exemptions? = nil) throws -> (Plan, Project, MemoryDisk) {
        let project = try project ?? loadProject("move/app.pbxproj")
        let disk = MemoryDisk(files ?? [to])
        let plan = try MovePlanner.plan(
            from: from, to: to, in: project, conventions: Conventions(flags: flags), keepMembership: keepMembership,
            disk: disk, exemptions: exemptions, minter: IDMinter(generator: FixedGenerator()))
        return (plan, project, disk)
    }

    /// Applies, checks, and asserts nothing mentions a deleted ID any more.
    /// The fixture carries M6 warnings (App/ is `App`'s root and the
    /// extension's sources lie under it), so "clean" means no error.
    private func applied(_ plan: Plan, to project: Project, wholeProjectClean: Bool = true) throws -> Project {
        let result = try plan.apply(to: project)
        assertOperationClean(result, scope: plan.touched)
        if wholeProjectClean { XCTAssertEqual(RuleSet.standard.evaluate(result).filter { $0.severity == .error }, []) }
        XCTAssertEqual(plan.deletedObjectsMentioned(in: result.serialize()), [], "deleted IDs still mentioned")
        for id in plan.deletedObjects { XCTAssertFalse(result.contains(id), "\(id) still exists") }
        return result
    }

    private func attributes(_ plan: Plan) -> [Step] {
        plan.steps.filter { if case .setAttribute = $0 { return true } else { return false } }
    }

    // MARK: 1. Identity and the reference

    // Spec: Move within a target; Minimal diff (1.1, 1.2).
    func testAMoveWithinATargetKeepsEveryIDAndChangesTwoLines() throws {
        let (plan, project, disk) = try plan("App/Views/Foo.swift", "App/Features/Foo.swift")
        XCTAssertEqual(plan.steps, [
            .removeChild(foo, from: views),
            .addChild(foo, to: features, position: .before("AA0000000000000000000018")),
        ], "no attribute changes, no membership changes")
        XCTAssertEqual(plan.moves, [Plan.Move(from: "App/Views/Foo.swift", to: "App/Features/Foo.swift")])
        XCTAssertEqual(plan.changes.map(\.action), [.reusedFileReference, .removedChild, .addedChild, .reusedBuildFile])
        XCTAssertEqual(plan.changes.map(\.object), [foo, views, features, fooBuildFile])
        XCTAssertTrue(plan.changes.allSatisfy { $0.path == "App/Features/Foo.swift" }, "keyed by the destination")
        XCTAssertEqual(plan.decisions.map(\.attribute), ["location", "targets"])
        XCTAssertEqual(plan.decisions[0].value, "path = Foo.swift; sourceTree = <group>; in group Features (AA0000000000000000000017)")
        XCTAssertEqual(plan.decisions[0].source, .structure)
        XCTAssertEqual(plan.decisions[1].value, "App")
        XCTAssertEqual(plan.decisions[1].source, .inferred(siblings: 3, directory: "App"), "Features has no files; the ancestor decides")
        XCTAssertEqual(plan.touched, [foo, views, features, fooBuildFile])
        _ = disk
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.fileReferences(at: "App/Features/Foo.swift").map(\.id), [foo])
        XCTAssertEqual(result.fileReferences(at: "App/Views/Foo.swift"), [])
        XCTAssertEqual(result.parents(of: foo).map(\.id), [features])
        XCTAssertEqual(result.fileReference(foo), project.fileReference(foo), "the reference object is byte-identical")
        XCTAssertEqual(result.buildFile(fooBuildFile), project.buildFile(fooBuildFile))
        XCTAssertEqual(result.buildPhase(appSources), project.buildPhase(appSources), "the Sources phase is not modified")
        XCTAssertEqual(result.objects.count, project.objects.count)
        let diff = lineDiff(String(decoding: project.serialize(), as: UTF8.self), String(decoding: result.serialize(), as: UTF8.self))
        XCTAssertEqual(diff.removed, ["\t\t\t\tAA0000000000000000000120 /* Foo.swift */,\n"])
        XCTAssertEqual(diff.added, ["\t\t\t\tAA0000000000000000000120 /* Foo.swift */,\n"])
    }

    // Spec: Re-parent between pathful groups (1.1).
    func testAMissingDestinationGroupIsCreated() throws {
        let (plan, project, _) = try plan("App/Views/Foo.swift", "App/Features/Modern/Foo.swift")
        let modern = try XCTUnwrap(plan.changes.first { $0.action == .createdGroup }?.object)
        XCTAssertEqual(plan.steps, [
            .createGroup(id: modern, name: nil, path: "Modern", sourceTree: "<group>"),
            .addChild(modern, to: features, position: .before("AA0000000000000000000018")),
            .removeChild(foo, from: views),
            .addChild(foo, to: modern, position: .last),
        ])
        XCTAssertEqual(plan.decisions[0].value, "path = Foo.swift; sourceTree = <group>; in group Modern (\(modern))")
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.groups(at: "App/Features/Modern").map(\.id), [modern])
        XCTAssertEqual(result.parents(of: foo).map(\.id), [modern])
        XCTAssertEqual(result.resolvedPath(of: foo), .relative("App/Features/Modern/Foo.swift"))
        XCTAssertEqual(result.fileReference(foo)?.path, "Foo.swift")
        XCTAssertEqual(result.group(views)?.children, ["AA0000000000000000000023"], "Views keeps Legacy")
    }

    // Spec: Source-root reference (1.1) — into a name-only group, and the emptied group goes.
    func testASourceRootReferenceIsRepathedIntoANameOnlyGroup() throws {
        let (plan, project, _) = try plan("AppTests/Views/FooTests.swift", "AppTests/State/FooTests.swift")
        XCTAssertEqual(plan.steps, [
            .setAttribute(key: "path", of: fooTests, to: .string("AppTests/State/FooTests.swift")),
            .removeChild(fooTests, from: testsViews),
            .addChild(fooTests, to: state, position: .before(stateTests.rawValue)),
            .removeChild(testsViews, from: appTests),
            .deleteObject(testsViews),
        ])
        XCTAssertEqual(plan.decisions[0].value, "path = AppTests/State/FooTests.swift; sourceTree = SOURCE_ROOT; in group State (AA0000000000000000000022)")
        XCTAssertEqual(plan.changes.map(\.action), [.reusedFileReference, .setAttribute, .removedChild, .addedChild, .reusedBuildFile, .removedChild, .deletedObject])
        XCTAssertEqual(plan.changes[1].detail, "path = AppTests/State/FooTests.swift (was AppTests/Views/FooTests.swift)")
        XCTAssertEqual(plan.changes.last?.detail, "group Views (AA0000000000000000000011), left empty")
        let result = try applied(plan, to: project)
        let reference = try XCTUnwrap(result.fileReference(fooTests))
        XCTAssertEqual(reference.path, "AppTests/State/FooTests.swift")
        XCTAssertEqual(reference.sourceTree, "SOURCE_ROOT")
        XCTAssertEqual(reference.name, "FooTests.swift")
        XCTAssertEqual(result.parents(of: fooTests).map(\.id), [state])
        XCTAssertNil(result.group(testsViews))
        XCTAssertEqual(result.fileReferences(at: "AppTests/State/FooTests.swift").map(\.id), [fooTests])
        XCTAssertEqual(result.group(appTests)?.children, ["AA0000000000000000000006", state, testsServices])
    }

    // Spec: Source-root reference into a pathful group (1.1).
    func testASourceRootReferenceIsRespelledUnderAPathfulGroup() throws {
        let (plan, project, _) = try plan("AppTests/State/StateTests.swift", "AppTests/Services/StateTests.swift")
        XCTAssertEqual(plan.steps, [
            .setAttribute(key: "name", of: stateTests, to: nil),
            .setAttribute(key: "path", of: stateTests, to: .string("StateTests.swift")),
            .setAttribute(key: "sourceTree", of: stateTests, to: .string("<group>")),
            .removeChild(stateTests, from: state),
            .addChild(stateTests, to: testsServices, position: .last),
            .removeChild(state, from: appTests),
            .deleteObject(state),
        ])
        XCTAssertEqual(plan.changes.filter { $0.action == .setAttribute }.map(\.detail), [
            "name removed (was StateTests.swift)",
            "path = StateTests.swift (was AppTests/State/StateTests.swift)",
            "sourceTree = <group> (was SOURCE_ROOT)",
        ])
        let result = try applied(plan, to: project)
        let text = String(decoding: result.serialize(), as: UTF8.self)
        XCTAssertTrue(text.contains("\t\tAA0000000000000000000340 /* StateTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StateTests.swift; sourceTree = \"<group>\"; };\n"), text)
        XCTAssertEqual(result.resolvedPath(of: stateTests), .relative("AppTests/Services/StateTests.swift"))
        XCTAssertNil(result.group(state))
    }

    // Spec: Rename in place (1.4) — every comment follows, the listing stays where it was.
    func testARenameInPlaceUpdatesEveryCommentAndKeepsTheListing() throws {
        let (plan, project, _) = try plan("App/Old.swift", "App/New.swift")
        XCTAssertEqual(plan.steps, [.setAttribute(key: "path", of: old, to: .string("New.swift"))], "no child moves")
        XCTAssertEqual(plan.changes.filter { $0.action == .setAttribute }.map(\.detail), ["path = New.swift (was Old.swift)"])
        let result = try applied(plan, to: project)
        let text = String(decoding: result.serialize(), as: UTF8.self)
        XCTAssertFalse(text.contains("Old.swift"), text)
        XCTAssertTrue(text.contains("\t\tBB0000000000000000000250 /* New.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000380 /* New.swift */; };\n"), text)
        XCTAssertTrue(text.contains("\t\t\t\tBB0000000000000000000250 /* New.swift in Sources */,\n"), text)
        XCTAssertTrue(text.contains("\t\tAA0000000000000000000380 /* New.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = New.swift; sourceTree = \"<group>\"; };\n"), text)
        XCTAssertEqual(result.group(appGroup)?.children, project.group(appGroup)?.children, "same children, same order")
        XCTAssertTrue(text.contains("\t\t\t\tAA0000000000000000000380 /* New.swift */,\n\t\t\t\tAA0000000000000000000290 /* App.entitlements */,\n"), text)
        XCTAssertEqual(result.fileReferences(at: "App/New.swift").map(\.id), [old])
        XCTAssertEqual(result.fileReferences(at: "App/Old.swift"), [])
        // A changed extension carries lastKnownFileType along when the table knows it.
        let (retyped, _, _) = try self.plan("App/Old.swift", "App/Old.m")
        XCTAssertEqual(retyped.steps, [
            .setAttribute(key: "lastKnownFileType", of: old, to: .string("sourcecode.c.objc")),
            .setAttribute(key: "path", of: old, to: .string("Old.m")),
        ])
        _ = try applied(retyped, to: project)
    }

    // Spec: Rename of a named reference (1.4).
    func testARenamedSourceRootReferenceKeepsNameEqualToItsBasename() throws {
        let (plan, project, _) = try plan("AppTests/State/StateTests.swift", "AppTests/State/StoreTests.swift")
        XCTAssertEqual(plan.steps, [
            .setAttribute(key: "name", of: stateTests, to: .string("StoreTests.swift")),
            .setAttribute(key: "path", of: stateTests, to: .string("AppTests/State/StoreTests.swift")),
        ])
        let result = try applied(plan, to: project)
        let text = String(decoding: result.serialize(), as: UTF8.self)
        XCTAssertTrue(text.contains("\t\tAA0000000000000000000340 /* StoreTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = StoreTests.swift; path = AppTests/State/StoreTests.swift; sourceTree = SOURCE_ROOT; };\n"), text)
        XCTAssertTrue(text.contains("/* StoreTests.swift in Sources */"), text)
        XCTAssertFalse(text.contains("StateTests.swift"), text)
        XCTAssertEqual(result.parents(of: stateTests).map(\.id), [state])
    }

    /// Design D1 step 2, the shape a rename must reproduce: in every
    /// Xcode-written corpus file, a `SOURCE_ROOT` reference that has a `name`
    /// has the last component of its `path` as that name. (No Xcode-written
    /// before/after pair of a rename could be obtained non-interactively;
    /// this is the invariant the corpus does show.)
    func testXcodeWritesNameEqualToTheBasenameOfSourceRootReferences() throws {
        var checked = 0
        for url in Fixtures.projectFiles(under: "corpus") {
            let project = try Project.load(Array(try Data(contentsOf: url)))
            for reference in project.fileReferences where reference.sourceTree == Kind.sourceRootSourceTree {
                guard let name = reference.name, let path = reference.path else { continue }
                checked += 1
                XCTAssertEqual(name, PlanBuilder.basename(of: path), "\(url.lastPathComponent) \(reference.id)")
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 8, "the corpus holds named SOURCE_ROOT references (MLX, Kingfisher, CocoaPods)")
    }

    // MARK: 2. Membership follows the destination

    private let rateTests: ObjectID = "AA0000000000000000000310"
    private let rateTestsBuildFile: ObjectID = "BB0000000000000000000180"
    private let slowServices: ObjectID = "AA0000000000000000000029"
    private let panel: ObjectID = "AA0000000000000000000320"
    private let panelBuildFile: ObjectID = "BB0000000000000000000190"
    private let iOS: ObjectID = "AA0000000000000000000020"
    private let shared: ObjectID = "AA0000000000000000000021"

    // Spec: Cross-target move (2.1); docs/design.md Motivation: "Moving a file between targets needed four manual edits" (2.3).
    func testACrossTargetMoveSwapsMembershipAndKeepsTheReference() throws {
        let (plan, project, _) = try plan("AppTests/Services/RateTests.swift", "AppSlowTests/Services/RateTests.swift")
        let created = try XCTUnwrap(plan.changes.first { $0.action == .createdBuildFile }?.object)
        XCTAssertEqual(plan.steps, [
            .removeChild(rateTests, from: testsServices),
            .addChild(rateTests, to: slowServices, position: .before("AA0000000000000000000300")),
            .removePhaseEntry(rateTestsBuildFile, from: appTestsSources),
            .deleteObject(rateTestsBuildFile),
            .createBuildFile(id: created, fileRef: rateTests, platformFilters: []),
            .addPhaseEntry(created, to: slowTestsSources, position: .last),
            .removeChild(testsServices, from: appTests),
            .deleteObject(testsServices),
        ])
        XCTAssertEqual(plan.decisions.map(\.attribute), ["location", "targets", "platformFilters"])
        XCTAssertEqual(plan.decisions[1].value, "AppSlowTests")
        XCTAssertEqual(plan.decisions[1].source, .inferred(siblings: 1, directory: "AppSlowTests/Services"))
        XCTAssertEqual(plan.decisions[2].value, "AppSlowTests: none")
        XCTAssertEqual(plan.changes.map(\.action), [
            .reusedFileReference, .removedChild, .addedChild,
            .removedPhaseEntry, .deletedObject, .createdBuildFile, .addedPhaseEntry,
            .removedChild, .deletedObject,
        ])
        XCTAssertEqual(plan.changes[3].detail, "entry in Sources of AppTests (CC0000000000000000000005)")
        XCTAssertEqual(plan.changes[4].detail, "build file in AppTests")
        XCTAssertEqual(plan.changes[5].detail, "build file for AppSlowTests")
        XCTAssertEqual(plan.changes[6].detail, "entry in Sources of AppSlowTests (CC0000000000000000000010)")
        XCTAssertEqual(plan.notes, [])
        XCTAssertTrue(plan.touched.isSuperset(of: [rateTests, rateTestsBuildFile, created, appTestsSources, slowTestsSources, "DD0000000000000000000003"]))
        let result = try applied(plan, to: project)
        // The Motivation regression: query shows the new target only, and the rule set reports nothing new.
        let report = MembershipReport(project: result, path: "AppSlowTests/Services/RateTests.swift")
        XCTAssertTrue(report.member)
        XCTAssertEqual(report.fileReference, rateTests)
        XCTAssertEqual(report.memberships.map { $0.target?.name }, ["AppSlowTests"])
        XCTAssertEqual(report.memberships.map(\.buildFile), [created])
        XCTAssertEqual(result.buildFiles(for: rateTests).map(\.id), [created])
        XCTAssertNil(result.buildFile(rateTestsBuildFile))
        XCTAssertEqual(result.buildPhase(appTestsSources)?.files, ["BB0000000000000000000060", "BB0000000000000000000070", "BB0000000000000000000210"])
        XCTAssertEqual(RuleSet.standard.evaluate(result), RuleSet.standard.evaluate(project), "no new findings, warnings included")
        XCTAssertEqual(result.fileReference(rateTests), project.fileReference(rateTests))
    }

    // Spec: Platform directory change (2.1); the fixture spells the lone ios
    // as Xcode does, `platformFilter = ios;` (platform-filter-canonical-form).
    func testAPlatformDirectoryChangeRewritesTheFiltersOnTheKeptBuildFile() throws {
        let (plan, project, _) = try plan("App/iOS/Panel.swift", "App/Shared/Panel.swift")
        XCTAssertEqual(plan.steps, [
            .removeChild(panel, from: iOS),
            .addChild(panel, to: shared, position: .last),
            .setAttribute(key: "platformFilter", of: panelBuildFile, to: nil),
            .removeChild(iOS, from: appGroup),
            .deleteObject(iOS),
        ])
        XCTAssertEqual(plan.decisions.map(\.attribute), ["location", "targets", "platformFilters"])
        XCTAssertEqual(plan.decisions[2].value, "App: none")
        XCTAssertEqual(plan.decisions[2].source, .inferred(siblings: 1, directory: "App/Shared"))
        XCTAssertEqual(plan.changes.filter { $0.action == .setAttribute }.map { "\($0.object) \($0.detail)" },
                       ["\(panelBuildFile) platformFilters removed (was ios)"])
        XCTAssertTrue(plan.changes.contains { $0.action == .reusedBuildFile && $0.object == panelBuildFile })
        let result = try applied(plan, to: project)
        XCTAssertNil(result.buildFile(panelBuildFile)?.platformFilter)
        XCTAssertNil(result.buildFile(panelBuildFile)?.platformFilters)
        XCTAssertEqual(result.buildFiles(for: panel).map(\.id), [panelBuildFile])
        XCTAssertEqual(MembershipReport(project: result, path: "App/Shared/Panel.swift").memberships.map(\.platformFilters), [[]])
        // The other way round gains the filter, spelled as Xcode spells a lone ios.
        let (back, _, _) = try self.plan("App/Shared/Common.swift", "App/iOS/Common.swift")
        XCTAssertEqual(back.steps.filter { if case .setAttribute = $0 { return true } else { return false } },
                       [.setAttribute(key: "platformFilter", of: "BB0000000000000000000200", to: .string("ios"))])
        XCTAssertEqual(back.changes.filter { $0.action == .setAttribute }.map(\.detail), ["platformFilters = ios (was none)"])
        let gained = try applied(back, to: project)
        XCTAssertEqual(gained.buildFile("BB0000000000000000000200")?.platformFilter, "ios")
        XCTAssertNil(gained.buildFile("BB0000000000000000000200")?.platformFilters)
        XCTAssertEqual(PlatformFilters.read(from: try XCTUnwrap(gained.buildFile("BB0000000000000000000200"))), ["ios"])
        XCTAssertTrue(String(decoding: gained.serialize(), as: UTF8.self).contains(
            "\t\tBB0000000000000000000200 /* Common.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000330 /* Common.swift */; platformFilter = ios; };\n"))
    }

    // Spec: Keep membership (2.1).
    func testKeepMembershipLeavesTargetsAloneAndNotesTheDifference() throws {
        let (plan, project, _) = try plan("AppTests/Services/RateTests.swift", "AppSlowTests/Services/RateTests.swift", keepMembership: true)
        XCTAssertEqual(plan.steps, [
            .removeChild(rateTests, from: testsServices),
            .addChild(rateTests, to: slowServices, position: .before("AA0000000000000000000300")),
            .removeChild(testsServices, from: appTests),
            .deleteObject(testsServices),
        ])
        XCTAssertEqual(plan.decisions.map(\.attribute), ["location", "targets"])
        XCTAssertEqual(plan.decisions[1].value, "AppTests")
        XCTAssertEqual(plan.decisions[1].source, .flag)
        XCTAssertEqual(plan.notes, ["AppSlowTests/Services/RateTests.swift: membership kept (--keep-membership); the 1 sibling in AppSlowTests/Services belongs to AppSlowTests"])
        XCTAssertTrue(plan.changes.contains { $0.action == .reusedBuildFile && $0.object == rateTestsBuildFile })
        XCTAssertFalse(plan.changes.contains { $0.action == .createdBuildFile })
        let result = try applied(plan, to: project)
        XCTAssertEqual(MembershipReport(project: result, path: "AppSlowTests/Services/RateTests.swift").memberships.map { $0.target?.name }, ["AppTests"])
        // Where the destination agrees, or cannot decide, there is no note.
        let (agreeing, _, _) = try self.plan("App/Views/Foo.swift", "App/Features/Foo.swift", keepMembership: true)
        XCTAssertEqual(agreeing.notes, [])
        let (undecidable, _, _) = try self.plan("App/Views/Foo.swift", "App/Mixed/Foo.swift", keepMembership: true)
        XCTAssertEqual(undecidable.notes, [])
        XCTAssertEqual(undecidable.decisions.last?.value, "App")
    }

    // Spec: Destination is ambiguous (2.1; design D3).
    func testAnAmbiguousDestinationNamesBothExits() throws {
        XCTAssertThrowsError(try plan("App/Views/Foo.swift", "App/Mixed/Foo.swift")) { error in
            let variants = [PlanError.TargetVariant(targets: ["App"], count: 1), PlanError.TargetVariant(targets: ["AppExtension"], count: 1)]
            XCTAssertEqual(error as? PlanError, .orKeepMembership(.noCommonTarget(path: "App/Mixed/Foo.swift", directory: "App/Mixed", variants: variants)))
            XCTAssertTrue("\(error)".contains("pass --target"), "\(error)")
            XCTAssertTrue("\(error)".hasSuffix(", or --keep-membership to leave membership as it is"), "\(error)")
        }
        // --target decides, as for add; --platform too.
        let (flagged, project, _) = try plan("App/Views/Foo.swift", "App/Mixed/Foo.swift", flags: Conventions.Flags(targets: ["AppExtension"], platformFilters: ["ios"]))
        XCTAssertEqual(flagged.decisions.filter { $0.attribute == "targets" }.map { ($0.value, $0.source) }.map { "\($0.0) \($0.1)" }, ["AppExtension flag"])
        let result = try applied(flagged, to: project)
        let report = MembershipReport(project: result, path: "App/Mixed/Foo.swift")
        XCTAssertEqual(report.memberships.map { $0.target?.name }, ["AppExtension"])
        XCTAssertEqual(report.memberships.map(\.platformFilters), [["ios"]])
        XCTAssertNil(result.buildFile(fooBuildFile), "App's build file is gone")
        // A filter disagreement at the destination is wrapped the same way.
        XCTAssertThrowsError(try self.plan("App/Views/Foo.swift", "App/Filtered/Foo.swift")) { error in
            guard case .orKeepMembership(.ambiguousPlatformFilters)? = error as? PlanError else { return XCTFail("\(error)") }
        }
    }

    // MARK: 3. Preconditions and validation

    private let user: ObjectID = "AA0000000000000000000370"
    private let userBuildFile: ObjectID = "BB0000000000000000000240"
    private let generated: ObjectID = "AA0000000000000000000301"

    // Spec: Move not yet performed; Both exist; Neither exists (3.1; design D4).
    func testTheDiskMustAlreadyReflectTheMove() throws {
        let from = "App/Views/Foo.swift"
        let to = "App/Features/Foo.swift"
        XCTAssertThrowsError(try plan(from, to, files: [from])) { error in
            XCTAssertEqual(error as? PlanError, .notMovedOnDisk(from: from, to: to))
            XCTAssertTrue("\(error)".contains("move the file on disk first"), "\(error)")
        }
        XCTAssertThrowsError(try plan(from, to, files: [from, to])) { error in
            XCTAssertEqual(error as? PlanError, .looksLikeACopy(from: from, to: to))
            XCTAssertTrue("\(error)".contains("copy"), "\(error)")
            XCTAssertTrue("\(error)".contains("pbxedit add App/Features/Foo.swift"), "\(error)")
        }
        XCTAssertThrowsError(try plan(from, to, files: [])) { error in
            XCTAssertEqual(error as? PlanError, .destinationMissing(from: from, to: to))
            XCTAssertTrue("\(error)".contains("does not exist"), "\(error)")
        }
        // The disk is checked before any decision is asked of the destination.
        XCTAssertThrowsError(try plan(from, "App/Mixed/Foo.swift", files: [from])) { error in
            XCTAssertEqual(error as? PlanError, .notMovedOnDisk(from: from, to: "App/Mixed/Foo.swift"))
        }
        // And it is the only thing read from the disk: two questions per file.
        let (_, _, disk) = try plan(from, to)
        XCTAssertEqual(disk.calls, 2)
    }

    // Spec: Unknown source; Destination already a member; Localized variant (3.2).
    func testTheProjectValidatesBothEnds() throws {
        XCTAssertThrowsError(try plan("App/Fooo.swift", "App/Views/Fooo.swift")) { error in
            XCTAssertEqual(error as? PlanError, .notInProject(path: "App/Fooo.swift"))
        }
        XCTAssertThrowsError(try plan("Foo.swift", "App/Views/Foo.swift")) { error in
            XCTAssertEqual(error as? PlanError, .notInProject(path: "Foo.swift"), "never by basename")
        }
        XCTAssertThrowsError(try plan("App/Views/Foo.swift", "App/Shared.swift")) { error in
            XCTAssertEqual(error as? PlanError, .destinationTaken(to: "App/Shared.swift", reference: "AA0000000000000000000130"))
            XCTAssertTrue("\(error)".contains("AA0000000000000000000130"), "\(error)")
        }
        XCTAssertThrowsError(try plan("App/Resources/en.lproj/Localizable.strings", "App/Resources/fr.lproj/Localizable.strings")) { error in
            XCTAssertEqual(error as? PlanError, .unsupportedContainer(path: "App/Resources/en.lproj/Localizable.strings", group: "AA0000000000000000000201", isa: "PBXVariantGroup"))
        }
        XCTAssertThrowsError(try plan("App/Views/Foo.swift", "App/Resources/en.lproj/Localizable.strings")) { error in
            XCTAssertEqual(error as? PlanError, .destinationTaken(to: "App/Resources/en.lproj/Localizable.strings", reference: "AA0000000000000000000210"))
        }
    }

    // MARK: 4. Synchronized folders and pruning

    // Spec: Into a synchronized folder; Out of a synchronized folder (4.1; design D6).
    func testMovingIntoASynchronizedFolderDropsExplicitMembership() throws {
        let (plan, project, _) = try plan("App/Models/User.swift", "App/Generated/User.swift")
        XCTAssertEqual(plan.steps, [
            .removePhaseEntry(userBuildFile, from: appSources),
            .deleteObject(userBuildFile),
            .removeChild(user, from: models),
            .deleteObject(user),
            .removeChild(models, from: appGroup),
            .deleteObject(models),
        ])
        XCTAssertEqual(plan.changes.first?.action, .synchronized)
        XCTAssertEqual(plan.changes.first?.object, generated)
        XCTAssertEqual(plan.changes.first?.detail, "membership now comes from synchronized group App/Generated (AA0000000000000000000301)")
        XCTAssertEqual(plan.changes.map(\.action).dropFirst(), [.removedPhaseEntry, .deletedObject, .removedChild, .deletedObject, .removedChild, .deletedObject])
        XCTAssertEqual(plan.decisions, [])
        XCTAssertEqual(plan.moves, [Plan.Move(from: "App/Models/User.swift", to: "App/Generated/User.swift")])
        let result = try applied(plan, to: project)
        let report = MembershipReport(project: result, path: "App/Generated/User.swift")
        XCTAssertFalse(report.member)
        XCTAssertEqual(report.synchronized?.group, generated)
        XCTAssertNil(result.group(models))
        XCTAssertThrowsError(try self.plan("App/Generated/User.swift", "App/Models/User.swift", files: ["App/Models/User.swift"])) { error in
            XCTAssertEqual(error as? PlanError, .synchronizedSource(from: "App/Generated/User.swift", to: "App/Models/User.swift", group: generated, folder: "App/Generated"))
            XCTAssertTrue("\(error)".contains("pbxedit add App/Models/User.swift"), "\(error)")
        }
    }

    // Spec: groups left empty are removed, others kept — including one the plan refills (4.2).
    func testTheSourceGroupIsPrunedOnlyWhenNothingRemains() throws {
        let (emptied, project, _) = try plan("App/Models/User.swift", "App/Views/User.swift")
        XCTAssertEqual(emptied.steps.suffix(2), [.removeChild(models, from: appGroup), .deleteObject(models)])
        XCTAssertNil(try applied(emptied, to: project).group(models))
        let (kept, _, _) = try self.plan("App/Services/Rate.swift", "App/Views/Rate.swift")
        XCTAssertFalse(kept.steps.contains(.deleteObject("AA0000000000000000000013")))
        XCTAssertEqual(try applied(kept, to: project).group("AA0000000000000000000013")?.children, ["AA0000000000000000000232", "AA0000000000000000000231"])
        // Emptied of its file but given a new subgroup by the same plan: not empty.
        let (refilled, _, _) = try self.plan("App/Models/User.swift", "App/Models/Sub/User.swift")
        let sub = try XCTUnwrap(refilled.changes.first { $0.action == .createdGroup }?.object)
        XCTAssertFalse(refilled.steps.contains(.deleteObject(models)), "\(refilled.steps)")
        let result = try applied(refilled, to: project)
        XCTAssertEqual(result.group(models)?.children, [sub])
        XCTAssertEqual(result.resolvedPath(of: user), .relative("App/Models/Sub/User.swift"))
    }

    // MARK: 5. Directory moves

    private let legacy: ObjectID = "AA0000000000000000000023"
    private let legacyA: ObjectID = "AA0000000000000000000024"
    private let legacyB: ObjectID = "AA0000000000000000000025"
    private let legacyMembers = ["Top.swift", "A/A1.swift", "A/A2.swift", "B/B1.swift", "B/B2.swift"]
    private let legacyReferences: [ObjectID] = [
        "AA0000000000000000000350", "AA0000000000000000000351", "AA0000000000000000000352", "AA0000000000000000000353", "AA0000000000000000000354",
    ]

    // Spec: Directory rename; One file missing at the destination (5.1; design D5).
    func testADirectoryRenameMovesEveryMemberAndKeepsEveryID() throws {
        let destinations = legacyMembers.map { "App/Views/Modern/" + $0 }
        let (plan, project, _) = try plan("App/Views/Legacy", "App/Views/Modern", files: destinations)
        XCTAssertEqual(plan.moves.map(\.from), legacyMembers.map { "App/Views/Legacy/" + $0 })
        XCTAssertEqual(plan.moves.map(\.to), destinations)
        XCTAssertEqual(plan.changes.filter { $0.action == .createdGroup }.map(\.detail).map { String($0.prefix(while: { $0 != " " })) + " " + $0.split(separator: " ")[1] },
                       ["group Modern", "group A", "group B"])
        XCTAssertEqual(plan.deletedObjects, [legacy, legacyA, legacyB])
        XCTAssertFalse(plan.changes.contains { $0.action == .createdBuildFile || $0.action == .createdFileReference })
        XCTAssertEqual(plan.notes, [])
        let result = try applied(plan, to: project)
        for (member, id) in zip(destinations, legacyReferences) {
            XCTAssertEqual(result.fileReferences(at: member).map(\.id), [id], member)
            XCTAssertEqual(result.parents(of: id).count, 1, member)
        }
        XCTAssertEqual(result.groups(at: "App/Views/Modern").count, 1)
        XCTAssertEqual(result.groups(at: "App/Views/Modern/A").count, 1)
        XCTAssertEqual(result.groups(at: "App/Views/Modern/B").count, 1)
        XCTAssertEqual(result.groups(at: "App/Views/Legacy"), [])
        XCTAssertNil(result.group(legacy))
        XCTAssertNil(result.group(legacyA))
        XCTAssertNil(result.group(legacyB))
        XCTAssertEqual(result.buildFiles.map(\.id), project.buildFiles.map(\.id), "every build file keeps its ID")
        XCTAssertEqual(result.buildPhase(appSources), project.buildPhase(appSources))
        XCTAssertEqual(result.group(views)?.children.count, 2, "Foo.swift and Modern")
        XCTAssertEqual(result.objects.count, project.objects.count, "three groups replaced three groups")
        // One file missing at the destination: nothing is planned.
        XCTAssertThrowsError(try self.plan("App/Views/Legacy", "App/Views/Modern", files: Array(destinations.dropLast()))) { error in
            XCTAssertEqual(error as? PlanError, .destinationMissing(from: "App/Views/Legacy/B/B2.swift", to: "App/Views/Modern/B/B2.swift"))
        }
    }

    // Spec: Extra files at the destination; Synchronized folder beneath the source (5.2).
    func testExtraFilesAreCountedAndASynchronizedFolderBeneathRefuses() throws {
        let destinations = legacyMembers.map { "App/Views/Modern/" + $0 }
        let (plan, project, _) = try plan("App/Views/Legacy", "App/Views/Modern", files: destinations + ["App/Views/Modern/Extra.swift"])
        XCTAssertEqual(plan.notes, ["App/Views/Modern: 1 file on disk under App/Views/Modern is not in the project: Extra.swift; pbxedit add registers it"])
        _ = try applied(plan, to: project)
        let (two, _, _) = try self.plan("App/Views/Legacy", "App/Views/Modern",
                                        files: destinations + ["App/Views/Modern/Extra.swift", "App/Views/Modern/A/notes.txt"])
        XCTAssertEqual(two.notes, ["App/Views/Modern: 2 files on disk under App/Views/Modern are not in the project: A/notes.txt, Extra.swift; pbxedit add registers them"])
        // A single-file move never looks around.
        let (single, _, disk) = try self.plan("App/Views/Foo.swift", "App/Features/Foo.swift", files: ["App/Features/Foo.swift", "App/Features/Other.swift"])
        XCTAssertFalse(single.notes.contains { $0.contains("on disk") }, "\(single.notes)")
        XCTAssertEqual(disk.calls, 2)
        XCTAssertThrowsError(try self.plan("App", "Application", files: [])) { error in
            XCTAssertEqual(error as? PlanError, .synchronizedBeneath(from: "App", group: generated, folder: "App/Generated"))
        }
    }

    // Spec: Reference that had no group (1.1). Only a SOURCE_ROOT reference
    // still resolves to its path without a parent (model D4).
    func testAnOrphanedReferenceGainsTheDestinationGroup() throws {
        var damaged = try loadProject("move/app.pbxproj")
        try damaged.removeChild(stateTests, from: state)
        XCTAssertEqual(RuleSet.standard.evaluate(damaged).filter { $0.severity == .error }.map { ($0.rule, $0.object) }.map { "\($0.0) \($0.1?.rawValue ?? "")" },
                       ["M3 \(stateTests)"])
        let (plan, project, _) = try plan("AppTests/State/StateTests.swift", "AppTests/Services/StateTests.swift", project: damaged)
        XCTAssertEqual(plan.steps, [
            .setAttribute(key: "name", of: stateTests, to: nil),
            .setAttribute(key: "path", of: stateTests, to: .string("StateTests.swift")),
            .setAttribute(key: "sourceTree", of: stateTests, to: .string("<group>")),
            .addChild(stateTests, to: testsServices, position: .last),
        ], "no child to remove; the group that was already empty is not this plan's business")
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.parents(of: stateTests).map(\.id), [testsServices])
        XCTAssertEqual(result.resolvedPath(of: stateTests), .relative("AppTests/Services/StateTests.swift"))
        XCTAssertEqual(result.group(state)?.children, [], "left alone")
    }
}
