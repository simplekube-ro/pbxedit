import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Tasks 1.1–5.3: the remove planner (design D1–D7). Every test applies the
/// plan, asserts on the model, asserts the rule set is clean over the touched
/// objects, that `plutil -lint` passes, and that no identifier token of the
/// result equals a deleted ID.
final class RemovePlannerTests: XCTestCase {
    private let services: ObjectID = "AA0000000000000000000013"
    private let appSources: ObjectID = "CC0000000000000000000001"
    private let extensionSources: ObjectID = "CC0000000000000000000004"
    private let app: ObjectID = "DD0000000000000000000001"
    private let appExtension: ObjectID = "DD0000000000000000000002"

    private func plan(_ paths: [String], fixture: String = "remove/app.pbxproj", target: String? = nil, all: Bool = false) throws -> (Plan, Project) {
        let project = try loadProject(fixture)
        let plan = try RemovePlanner.plan(paths, in: project, target: target, all: all)
        return (plan, project)
    }

    /// Applies, checks, and asserts nothing mentions a deleted ID any more.
    private func applied(_ plan: Plan, to project: Project, wholeProjectClean: Bool = true) throws -> Project {
        let result = try plan.apply(to: project)
        assertOperationClean(result, scope: plan.touched)
        if wholeProjectClean { XCTAssertEqual(RuleSet.standard.evaluate(result), []) }
        let deleted = plan.deletedObjects
        let mentioned = identifierTokens(in: result.serialize()).intersection(deleted.map(\.rawValue))
        XCTAssertEqual(mentioned, [], "deleted IDs still mentioned")
        XCTAssertEqual(plan.deletedObjectsMentioned(in: result.serialize()), [], "and the plan's own search agrees")
        for id in deleted { XCTAssertFalse(result.contains(id), "\(id) still exists") }
        return result
    }

    /// Every maximal run of letters, digits and underscores.
    private func identifierTokens(in bytes: [UInt8]) -> Set<String> {
        var tokens: Set<String> = []
        var current: [UInt8] = []
        for byte in bytes + [0x20] {
            let isIdentifier = (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
            if isIdentifier {
                current.append(byte)
            } else if !current.isEmpty {
                tokens.insert(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            }
        }
        return tokens
    }

    private func deleted(_ plan: Plan) -> [ObjectID] {
        plan.changes.filter { $0.action == .deletedObject }.map(\.object)
    }

    // MARK: 1. Complete removal

    // Spec: Ordinary file (1.1); design D1 step order.
    func testAnOrdinaryFileLosesEveryTraceInReferrerOrder() throws {
        let (plan, project) = try plan(["App/Services/Rate.swift"])
        let rate: ObjectID = "AA0000000000000000000230"
        let buildFile: ObjectID = "BB0000000000000000000110"
        XCTAssertEqual(plan.steps, [
            .removePhaseEntry(buildFile, from: appSources),
            .deleteObject(buildFile),
            .removeChild(rate, from: services),
            .deleteObject(rate),
        ])
        XCTAssertEqual(plan.changes.map(\.action), [.removedPhaseEntry, .deletedObject, .removedChild, .deletedObject])
        XCTAssertEqual(plan.changes.map(\.object), [appSources, buildFile, services, rate])
        XCTAssertEqual(plan.changes[1].detail, "build file in App")
        XCTAssertEqual(plan.changes[3].detail, "file reference App/Services/Rate.swift")
        XCTAssertTrue(plan.changes.allSatisfy { $0.path == "App/Services/Rate.swift" })
        XCTAssertEqual(plan.decisions, [])
        XCTAssertEqual(plan.notes, [])
        XCTAssertEqual(plan.touched, [rate, buildFile, services, appSources, app], "the reference, its build file, and every former referrer")
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.fileReferences(at: "App/Services/Rate.swift"), [])
        XCTAssertNil(result.buildFile(buildFile))
        XCTAssertEqual(result.buildPhase(appSources)?.files.contains(buildFile), false)
        XCTAssertEqual(result.group(services)?.children, ["AA0000000000000000000232", "AA0000000000000000000231"], "the siblings stay, in order")
        XCTAssertFalse(MembershipReport(project: result, path: "App/Services/Rate.swift").member)
        XCTAssertEqual(result.objects.count, project.objects.count - 2)
    }

    // Spec: Damaged membership is removed too (1.1).
    func testDamagedMembershipIsRemovedWithoutSpecialCases() throws {
        let (plan, project) = try plan(["AppTests/Views/FooTests.swift"], fixture: "add/partial.pbxproj")
        XCTAssertEqual(plan.steps, [.deleteObject("BF01"), .deleteObject("AB12")], "no phase entry and no group child to remove")
        XCTAssertEqual(plan.changes[0].detail, "build file in no phase")
        XCTAssertEqual(plan.touched, ["AB12", "BF01"])
        let result = try applied(plan, to: project, wholeProjectClean: false)
        XCTAssertNil(result.fileReference("AB12"))
        XCTAssertNil(result.buildFile("BF01"))
        XCTAssertEqual(RuleSet.standard.evaluate(result).map(\.object), ["OR01", "OR02"], "the unrelated orphans remain and did not block")
        XCTAssertFalse(String(decoding: result.serialize(), as: UTF8.self).contains("PBXBuildFile section"), "the emptied section's markers go too")
    }

    // Spec: Project-only file (1.1).
    func testAProjectOnlyFileLosesItsReferenceAndGroupChild() throws {
        let (plan, project) = try plan(["App/App.entitlements"])
        let entitlements: ObjectID = "AA0000000000000000000290"
        let appGroup: ObjectID = "AA0000000000000000000002"
        XCTAssertEqual(plan.steps, [.removeChild(entitlements, from: appGroup), .deleteObject(entitlements)])
        XCTAssertEqual(plan.touched, [entitlements, appGroup])
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.group(appGroup)?.children.count, (project.group(appGroup)?.children.count ?? 0) - 1)
        XCTAssertEqual(result.buildFiles.count, project.buildFiles.count)
        XCTAssertEqual(result.objects.count, project.objects.count - 1)
    }

    // MARK: 1.3 The multi-target guard

    // Spec: Shared source without a choice; Remove from everything (design D3).
    func testASharedFileNeedsAllAndThenLosesEveryBuildFile() throws {
        XCTAssertThrowsError(try plan(["App/Services/Cache.swift"])) { error in
            XCTAssertEqual(error as? PlanError, .sharedFile(path: "App/Services/Cache.swift", targets: ["App", "AppExtension"]))
            XCTAssertTrue("\(error)".contains("--target"), "\(error)")
            XCTAssertTrue("\(error)".contains("--all"), "\(error)")
        }
        let cache: ObjectID = "AA0000000000000000000232"
        let (plan, project) = try plan(["App/Services/Cache.swift"], all: true)
        XCTAssertEqual(plan.steps, [
            .removePhaseEntry("BB0000000000000000000112", from: appSources),
            .deleteObject("BB0000000000000000000112"),
            .removePhaseEntry("BB0000000000000000000113", from: extensionSources),
            .deleteObject("BB0000000000000000000113"),
            .removeChild(cache, from: services),
            .deleteObject(cache),
        ])
        XCTAssertEqual(plan.notes, ["App/Services/Cache.swift: removed from App, AppExtension (--all)"])
        XCTAssertTrue(plan.touched.isSuperset(of: [app, appExtension, appSources, extensionSources]))
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.fileReferences(at: "App/Services/Cache.swift"), [])
        XCTAssertEqual(result.buildPhase(appSources)?.files.count, (project.buildPhase(appSources)?.files.count ?? 0) - 1)
        XCTAssertEqual(result.buildPhase(extensionSources)?.files.count, (project.buildPhase(extensionSources)?.files.count ?? 0) - 1)
        // A single-target file needs no flag and --all is harmless on it.
        let single = try RemovePlanner.plan(["App/Services/Rate.swift"], in: project, all: true)
        XCTAssertEqual(single.steps.count, 4)
        XCTAssertEqual(single.notes, [])
    }

    // Spec: Two build files in one target (design D3: targets, not build files).
    func testTwoBuildFilesInOneTargetBypassTheGuard() throws {
        let (plan, project) = try plan(["App/Foo.swift"], fixture: "rules/m5-double-add.pbxproj")
        XCTAssertEqual(plan.steps, [
            .removePhaseEntry("BF01", from: "S001"),
            .deleteObject("BF01"),
            .removePhaseEntry("BF02", from: "S001"),
            .deleteObject("BF02"),
            .removeChild("AB12", from: "G002"),
            .deleteObject("AB12"),
            .removeChild("G002", from: "G001"),
            .deleteObject("G002"),
        ], "and the emptied App group goes with it; the main group stays")
        XCTAssertEqual(RuleSet.standard.evaluate(project).map(\.rule), [.M5], "the fixture starts with the defect")
        let result = try applied(plan, to: project, wholeProjectClean: false)
        XCTAssertEqual(RuleSet.standard.evaluate(result), [], "and ends without it")
        XCTAssertEqual(result.buildPhase("S001")?.files, [])
        XCTAssertEqual(result.mainGroup?.children, [])
    }

    // MARK: 2. Detach

    // Spec: Detach a shared source (design D4).
    func testDetachingKeepsTheReferenceAndTheOtherTargetsBuildFile() throws {
        let cache: ObjectID = "AA0000000000000000000232"
        let (plan, project) = try plan(["App/Services/Cache.swift"], target: "AppExtension")
        XCTAssertEqual(plan.steps, [
            .removePhaseEntry("BB0000000000000000000113", from: extensionSources),
            .deleteObject("BB0000000000000000000113"),
        ])
        XCTAssertEqual(plan.changes.map(\.detail), ["entry in Sources of AppExtension (CC0000000000000000000004)", "build file in AppExtension"])
        XCTAssertEqual(plan.notes, [])
        XCTAssertEqual(plan.touched, [cache, "BB0000000000000000000113", extensionSources, appExtension, services])
        let result = try applied(plan, to: project)
        let report = MembershipReport(project: result, path: "App/Services/Cache.swift")
        XCTAssertTrue(report.member)
        XCTAssertEqual(report.fileReference, cache)
        XCTAssertEqual(report.groups, [services])
        XCTAssertEqual(report.memberships.map { $0.target?.name }, ["App"])
        XCTAssertEqual(result.buildFile("BB0000000000000000000112")?.fileRef, cache)
        XCTAssertEqual(result.fileReference(cache), project.fileReference(cache))
    }

    // Spec: Last membership detached.
    func testDetachingTheLastTargetLeavesTheReferenceWithANote() throws {
        let rate: ObjectID = "AA0000000000000000000230"
        let (plan, project) = try plan(["App/Services/Rate.swift"], target: "App")
        XCTAssertEqual(plan.steps, [.removePhaseEntry("BB0000000000000000000110", from: appSources), .deleteObject("BB0000000000000000000110")])
        XCTAssertEqual(plan.notes, ["App/Services/Rate.swift: now built by no target; the file reference and its group child remain"])
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.parents(of: rate).map(\.id), [services])
        XCTAssertEqual(result.buildFiles(for: rate), [])
        let report = MembershipReport(project: result, path: "App/Services/Rate.swift")
        XCTAssertTrue(report.member)
        XCTAssertEqual(report.memberships, [])
    }

    // Spec: Not a member of that target; an unknown name is the usage error `add` has.
    func testDetachingFromATargetTheFileIsNotInRefuses() throws {
        XCTAssertThrowsError(try plan(["App/Views/Foo.swift"], target: "AppTests")) { error in
            XCTAssertEqual(error as? PlanError, .notMemberOfTarget(path: "App/Views/Foo.swift", target: "AppTests", targets: ["App"]))
            XCTAssertTrue("\(error)".contains("not a member of AppTests; it belongs to App"), "\(error)")
        }
        XCTAssertThrowsError(try plan(["App/App.entitlements"], target: "App")) { error in
            XCTAssertEqual(error as? PlanError, .notMemberOfTarget(path: "App/App.entitlements", target: "App", targets: []))
            XCTAssertTrue("\(error)".contains("built by no target"), "\(error)")
        }
        XCTAssertThrowsError(try plan(["App/Views/Foo.swift"], target: "Nope")) { error in
            XCTAssertEqual(error as? PlanError, .unknownTarget(name: "Nope", available: ["App", "AppExtension", "AppKit", "AppTests"]))
        }
    }

    // Design D4: a build file in no phase belongs to no target and is left alone by --target.
    func testDetachingLeavesAnUnphasedBuildFileAlone() throws {
        // partial.pbxproj: BF01 is in no phase. Put AB12 into App's Sources with a second build file first.
        var project = try loadProject("add/partial.pbxproj")
        try project.createObject("BF02", isa: Kind.buildFile, attributes: [NewEntry("fileRef", project.reference(to: "AB12"))])
        try project.addPhaseEntry("BF02", to: "S001")
        let plan = try RemovePlanner.plan(["AppTests/Views/FooTests.swift"], in: project, target: "App")
        XCTAssertEqual(plan.steps, [.removePhaseEntry("BF02", from: "S001"), .deleteObject("BF02")])
        XCTAssertEqual(plan.notes.count, 1, "BF01 counts for no target, so the file is now built by none")
        let result = try plan.apply(to: project)
        XCTAssertEqual(result.buildFiles(for: "AB12").map(\.id), ["BF01"])
        // The damage stays, and because it is the touched file's own damage the
        // pre-write check reports it: the detach is refused, not silently completed.
        let findings = RuleSet.standard.evaluate(result, scope: plan.touched).filter { $0.severity == .error }
        XCTAssertEqual(findings.map { ($0.rule, $0.object) }.map { "\($0.0) \($0.1?.rawValue ?? "")" }, ["M1 BF01", "M3 AB12"])
        // Whole removal takes the unphased one too, and is clean.
        let whole = try RemovePlanner.plan(["AppTests/Views/FooTests.swift"], in: project)
        XCTAssertEqual(whole.steps, [.deleteObject("BF01"), .removePhaseEntry("BF02", from: "S001"), .deleteObject("BF02"), .deleteObject("AB12")])
        _ = try applied(whole, to: project, wholeProjectClean: false)
    }

    // MARK: 3. Group pruning

    // Spec: Last file in a directory (design D5).
    func testTheLastFileInAChainPrunesEveryEmptiedGroupButNotThePreexistingEmptyOne() throws {
        let thing: ObjectID = "AA0000000000000000000280"
        let new: ObjectID = "AA0000000000000000000018"
        let features: ObjectID = "AA0000000000000000000017"
        let appGroup: ObjectID = "AA0000000000000000000002"
        let (plan, project) = try plan(["App/Features/New/Thing.swift"])
        XCTAssertEqual(plan.steps, [
            .removePhaseEntry("BB0000000000000000000160", from: appSources),
            .deleteObject("BB0000000000000000000160"),
            .removeChild(thing, from: new),
            .deleteObject(thing),
            .removeChild(new, from: features),
            .deleteObject(new),
            .removeChild(features, from: appGroup),
            .deleteObject(features),
        ])
        XCTAssertEqual(deleted(plan), ["BB0000000000000000000160", thing, new, features])
        XCTAssertEqual(plan.changes.last?.detail, "group Features (AA0000000000000000000017), left empty")
        XCTAssertTrue(plan.touched.isSuperset(of: [new, features, appGroup]))
        let result = try applied(plan, to: project)
        XCTAssertNil(result.group(new))
        XCTAssertNil(result.group(features))
        XCTAssertEqual(result.group("AA0000000000000000000019")?.children, [], "the group that was empty before is untouched")
        XCTAssertEqual(result.group(appGroup)?.children, project.group(appGroup)?.children.filter { $0 != features })
        XCTAssertEqual(result.groups(at: "App/Features"), [])
    }

    // Spec: Root groups are kept.
    func testTheMainGroupAndTheProductsGroupAreNeverPruned() throws {
        let (plan, project) = try plan(["Top.swift", "Odd.swift"], fixture: "remove/roots.pbxproj")
        XCTAssertEqual(deleted(plan), ["BF01", "AB01", "BF02", "AB02"], "no group is deleted")
        let result = try applied(plan, to: project)
        XCTAssertEqual(result.mainGroup?.children, ["G002", "G003"])
        XCTAssertEqual(result.group("G002")?.children, [])
        XCTAssertEqual(result.group("G003")?.children, [])
    }

    // Spec: A directory's files in one command.
    func testSeveralPathsPruneTheirSharedGroupOnce() throws {
        let tvOS: ObjectID = "AA0000000000000000000014"
        let (plan, project) = try plan(["App/tvOS/TV1.swift", "App/tvOS/TV2.swift"])
        XCTAssertEqual(plan.steps.filter { $0 == .deleteObject(tvOS) }.count, 1)
        XCTAssertEqual(plan.steps.suffix(2), [.removeChild(tvOS, from: "AA0000000000000000000002"), .deleteObject(tvOS)], "after both references")
        XCTAssertEqual(plan.changes.last?.path, "App/tvOS/TV1.swift", "attributed to the first path that reached the group")
        let result = try applied(plan, to: project)
        XCTAssertNil(result.group(tvOS))
        // One path alone keeps the group for its sibling.
        let one = try RemovePlanner.plan(["App/tvOS/TV1.swift"], in: project)
        XCTAssertFalse(one.steps.contains(.deleteObject(tvOS)))
        XCTAssertEqual(try applied(one, to: project).group(tvOS)?.children, ["AA0000000000000000000241"])
    }

    // MARK: 4. Refusals

    // Spec: Localized resource; Synchronized folder; Typo (design D2, D7).
    func testUnsupportedAndUnknownPathsRefuse() throws {
        XCTAssertThrowsError(try plan(["App/Resources/en.lproj/Localizable.strings"])) { error in
            XCTAssertEqual(error as? PlanError, .unsupportedContainer(path: "App/Resources/en.lproj/Localizable.strings", group: "AA0000000000000000000201", isa: "PBXVariantGroup"))
            XCTAssertTrue("\(error)".contains("localized variant"), "\(error)")
        }
        XCTAssertThrowsError(try plan(["App/Generated/User.swift"])) { error in
            XCTAssertEqual(error as? PlanError, .synchronizedMembership(path: "App/Generated/User.swift", group: "AA0000000000000000000301", folder: "App/Generated"))
        }
        XCTAssertThrowsError(try plan(["App/Fooo.swift"])) { error in
            XCTAssertEqual(error as? PlanError, .notInProject(path: "App/Fooo.swift"))
        }
        XCTAssertThrowsError(try plan(["Foo.swift"])) { error in
            XCTAssertEqual(error as? PlanError, .notInProject(path: "Foo.swift"), "never by basename")
        }
        // One bad path among three plans nothing.
        XCTAssertThrowsError(try plan(["App/Services/Rate.swift", "App/Nope.swift", "App/Views/Foo.swift"]))
    }

    // MARK: 5. Safety

    // Spec: Incomplete plan is caught (design D6).
    func testAnIncompletePlanIsRejectedByTheScopedCheck() throws {
        let (plan, project) = try plan(["App/Services/Rate.swift"])
        XCTAssertTrue(plan.touched.isSuperset(of: [appSources, services, app]), "former referrers are in scope")
        var stub = plan
        stub.steps.removeAll { $0 == .removePhaseEntry("BB0000000000000000000110", from: appSources) }
        let result = try stub.apply(to: project)
        let findings = RuleSet.standard.evaluate(result, scope: stub.touched).filter { $0.severity == .error }
        XCTAssertEqual(findings.map(\.rule), [.S2, .M2], "the dangling entry, seen by both rules: \(findings)")
        XCTAssertEqual(findings.map(\.object), [appSources, appSources])
        XCTAssertEqual(findings.map(\.related), [["BB0000000000000000000110"], ["BB0000000000000000000110"]])
        // Without the referrers in scope the dangling entry would go unnoticed.
        XCTAssertEqual(RuleSet.standard.evaluate(result, scope: ["AA0000000000000000000230"]), [])
        // The token search sees it too, and matches whole tokens only.
        XCTAssertEqual(stub.deletedObjectsMentioned(in: result.serialize()), ["BB0000000000000000000110"])
        XCTAssertEqual(stub.deletedObjects, ["BB0000000000000000000110", "AA0000000000000000000230"])
        let short = Plan(steps: [.deleteObject("AB12")])
        XCTAssertEqual(short.deletedObjectsMentioned(in: Array("x = AB123; y = AB1; z = (AB12, )".utf8)), ["AB12"])
        XCTAssertEqual(short.deletedObjectsMentioned(in: Array("x = AB123; y = xAB12".utf8)), [])
        XCTAssertEqual(short.deletedObjectsMentioned(in: Array("AB12".utf8)), ["AB12"], "a token at the very end")
    }

    // Spec: No dangling references (5.3) — S2 and M2 are exactly as before on
    // every successful scenario, including fixtures with other findings.
    func testS2AndM2FindingsAreIdenticalBeforeAndAfterEveryRemoval() throws {
        let scenarios: [(fixture: String, paths: [String], target: String?, all: Bool)] = [
            ("remove/app.pbxproj", ["App/Services/Rate.swift"], nil, false),
            ("remove/app.pbxproj", ["App/App.entitlements"], nil, false),
            ("remove/app.pbxproj", ["App/Services/Cache.swift"], nil, true),
            ("remove/app.pbxproj", ["App/Services/Cache.swift"], "AppExtension", false),
            ("remove/app.pbxproj", ["App/Services/Rate.swift"], "App", false),
            ("remove/app.pbxproj", ["App/Features/New/Thing.swift"], nil, false),
            ("remove/app.pbxproj", ["App/tvOS/TV1.swift", "App/tvOS/TV2.swift", "App/Shared.swift"], nil, true),
            ("remove/app.pbxproj", ["AppTests/Views/FooTests.swift", "AppTests/Foo/Bar.swift"], nil, false),
            ("remove/roots.pbxproj", ["Top.swift", "Odd.swift"], nil, false),
            ("add/partial.pbxproj", ["AppTests/Views/FooTests.swift"], nil, false),
            ("rules/m5-double-add.pbxproj", ["App/Foo.swift"], nil, false),
        ]
        func dangling(_ project: Project) -> [Finding] {
            RuleSet.standard.evaluate(project).filter { $0.rule == .S2 || $0.rule == .M2 }
        }
        for scenario in scenarios {
            let project = try loadProject(scenario.fixture)
            let before = dangling(project)
            let plan = try RemovePlanner.plan(scenario.paths, in: project, target: scenario.target, all: scenario.all)
            let result = try plan.apply(to: project)
            XCTAssertEqual(RuleSet.standard.evaluate(result, scope: plan.touched).filter { $0.severity == .error }, [], "\(scenario)")
            XCTAssertEqual(dangling(result), before, "\(scenario)")
            XCTAssertEqual(plan.deletedObjectsMentioned(in: result.serialize()), [], "\(scenario)")
            assertPlutilLints(result.serialize(), scenario.fixture)
        }
        // A fixture whose damage sits on a touched object is refused, not written around.
        let damaged = try loadProject("rules/s2-dangling-child.pbxproj")
        let plan = try RemovePlanner.plan(["App/Foo.swift"], in: damaged)
        let findings = RuleSet.standard.evaluate(try plan.apply(to: damaged), scope: plan.touched)
        XCTAssertEqual(findings.map(\.rule), [.S2], "the group's dangling child is in scope through the group")
        XCTAssertEqual(findings.first?.related, ["DEAD0001"])
    }
}
