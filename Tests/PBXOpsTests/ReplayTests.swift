import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 4.3–4.4: the transition planner (design D5), each
/// transition applied to the base as "current". Every result is checked
/// clean under the scoped rule set and `plutil -lint`.
final class ReplayTests: XCTestCase {
    private let appSources: ObjectID = "CC0000000000000000000001"
    private let appResources: ObjectID = "CC0000000000000000000003"
    private let extensionSources: ObjectID = "CC0000000000000000000004"

    /// Replays the unit of `theirs` over `paths` onto `current` (the base by default).
    private func replay(_ paths: [String], theirs: Project, current: Project? = nil, exemptions: Exemptions? = nil) throws -> Replay.Outcome {
        let current = try current ?? MergeFixture.base()
        let outcome = try Replay.run(paths: paths, current: current, theirs: MembershipSnapshot(theirs), exemptions: exemptions,
                                     minter: IDMinter(generator: SplitMix(seed: 42)))
        let errors = RuleSet.standard.evaluate(outcome.project, scope: outcome.touched, exemptions: exemptions).filter { $0.severity == .error }
        XCTAssertEqual(errors, [], "the transition is clean over what it touched")
        assertPlutilLints(outcome.project.serialize())
        return outcome
    }

    private func rows(_ project: Project, _ path: String) -> [MembershipSnapshot.MaskedRow] {
        MembershipSnapshot(project).references[path]?.masked.rows ?? []
    }

    func testAnAddedSourceWithAFilter() throws {
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: try MergeFixture.base(), platforms: ["ios"])
        let result = try replay(["App/Services/New.swift"], theirs: theirs).project
        let reference = try XCTUnwrap(result.fileReferences(at: "App/Services/New.swift").first)
        XCTAssertEqual(result.parents(of: reference.id).map(\.id), ["AA0000000000000000000013"])
        let buildFile = try XCTUnwrap(result.buildFiles(for: reference.id).first)
        XCTAssertEqual(buildFile.platformFilter, "ios")
        XCTAssertEqual(result.phases(of: buildFile.id).map(\.id), [appSources])
        XCTAssertEqual(rows(result, "App/Services/New.swift"), rows(theirs, "App/Services/New.swift"))
    }

    func testTwoTargetsWithDifferentFilters() throws {
        let base = try MergeFixture.base()
        let once = try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"], platforms: ["ios"])
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: once, targets: ["AppExtension"], platforms: ["macos"])
        let outcome = try replay(["App/Services/New.swift"], theirs: theirs)
        XCTAssertEqual(rows(outcome.project, "App/Services/New.swift"), [
            .init(target: "App", phase: .sources, filters: ["ios"], settings: nil),
            .init(target: "AppExtension", phase: .sources, filters: ["macos"], settings: nil),
        ])
    }

    func testAReferenceWithoutABuildFile() throws {
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: try MergeFixture.base(), phase: .notBuilt)
        let result = try replay(["App/Services/New.swift"], theirs: theirs).project
        let reference = try XCTUnwrap(result.fileReferences(at: "App/Services/New.swift").first)
        XCTAssertEqual(result.buildFiles(for: reference.id), [])
        XCTAssertEqual(result.parents(of: reference.id).map(\.id), ["AA0000000000000000000013"])
    }

    func testARemovalOfAPathTheirsDropped() throws {
        let theirs = try MergeFixture.remove(["App/Views/Foo.swift"], from: try MergeFixture.base())
        let result = try replay(["App/Views/Foo.swift"], theirs: theirs).project
        XCTAssertEqual(result.fileReferences(at: "App/Views/Foo.swift"), [])
        XCTAssertNil(result.buildFile("BB0000000000000000000020"))
    }

    func testARenameKeepsTheReferenceAndTheBuildFile() throws {
        let theirs = try MergeFixture.move("App/Views/Foo.swift", to: "App/Features/Foo.swift", in: try MergeFixture.base())
        let result = try replay(["App/Features/Foo.swift", "App/Views/Foo.swift"], theirs: theirs).project
        XCTAssertEqual(result.fileReferences(at: "App/Features/Foo.swift").map(\.id), ["AA0000000000000000000120"])
        XCTAssertEqual(result.fileReferences(at: "App/Views/Foo.swift"), [])
        XCTAssertEqual(result.buildFiles(for: "AA0000000000000000000120").map(\.id), ["BB0000000000000000000020"])
        XCTAssertEqual(result.phases(of: "BB0000000000000000000020").map(\.id), [appSources])
    }

    func testADirectoryMoveRebuildsTheGroupAndPrunesTheOldOne() throws {
        let theirs = try MergeFixture.move("App/Views/Legacy/A", to: "App/Old/A", in: try MergeFixture.base())
        var current = try MergeFixture.base()
        for unit in [["App/Old/A/A1.swift", "App/Views/Legacy/A/A1.swift"], ["App/Old/A/A2.swift", "App/Views/Legacy/A/A2.swift"]] {
            current = try replay(unit, theirs: theirs, current: current).project
        }
        XCTAssertEqual(current.fileReferences(at: "App/Old/A/A1.swift").map(\.id), ["AA0000000000000000000351"])
        XCTAssertEqual(current.fileReferences(at: "App/Old/A/A2.swift").map(\.id), ["AA0000000000000000000352"])
        XCTAssertEqual(current.groups(at: "App/Views/Legacy/A"), [], "pruned")
        XCTAssertEqual(current.groups(at: "App/Old/A").count, 1)
        XCTAssertEqual(current.groups(at: "App/Views/Legacy").count, 1, "still holds Top.swift and B")
    }

    // Spec: A re-filter keeps ours' attribute.
    func testAReFilterKeepsTheIDsAndOursAttribute() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.attribute("fileEncoding", .string("4"), of: "AA0000000000000000000260", in: base)
        let detached = try MergeFixture.remove(["App/Filtered/F1.swift"], from: base, target: "App")
        let theirs = try MergeFixture.add(["App/Filtered/F1.swift"], to: detached, targets: ["App"], platforms: ["ios", "macos"])
        XCTAssertNotEqual(MembershipSnapshot(theirs).references["App/Filtered/F1.swift"]?.rows.first?.buildFile, "BB0000000000000000000140")
        let outcome = try replay(["App/Filtered/F1.swift"], theirs: theirs, current: ours)
        let result = outcome.project
        XCTAssertEqual(result.fileReferences(at: "App/Filtered/F1.swift").map(\.id), ["AA0000000000000000000260"])
        XCTAssertEqual(result.fileReference("AA0000000000000000000260")?.object.string("fileEncoding"), "4")
        XCTAssertEqual(result.buildFiles(for: "AA0000000000000000000260").map(\.id), ["BB0000000000000000000140"])
        XCTAssertEqual(result.buildFile("BB0000000000000000000140")?.platformFilters, ["ios", "macos"])
        XCTAssertNil(result.buildFile("BB0000000000000000000140")?.platformFilter)
    }

    func testAPhaseKindChangeDetachesAndAttaches() throws {
        let base = try MergeFixture.base()
        let detached = try MergeFixture.remove(["App/Views/Foo.swift"], from: base, target: "App")
        let theirs = try MergeFixture.add(["App/Views/Foo.swift"], to: detached, targets: ["App"], phase: .resources)
        let result = try replay(["App/Views/Foo.swift"], theirs: theirs).project
        XCTAssertEqual(result.fileReferences(at: "App/Views/Foo.swift").map(\.id), ["AA0000000000000000000120"])
        let buildFiles = result.buildFiles(for: "AA0000000000000000000120")
        XCTAssertEqual(buildFiles.count, 1)
        XCTAssertEqual(buildFiles.flatMap { result.phases(of: $0.id).map(\.id) }, [appResources])
        XCTAssertNil(result.buildFile("BB0000000000000000000020"))
    }

    func testAnM3ExemptPathGetsNoGroupChild() throws {
        let exemptions = try MergeFixture.exemptions("lint:\n  exempt:\n    M3: [\"App/Loose/**\"]\n")
        let theirs = try MergeFixture.add(["App/Loose/Free.swift"], to: try MergeFixture.base(), targets: ["App"], exemptions: exemptions)
        let result = try replay(["App/Loose/Free.swift"], theirs: theirs, exemptions: exemptions).project
        let reference = try XCTUnwrap(result.fileReferences(at: "App/Loose/Free.swift").first)
        XCTAssertEqual(result.parents(of: reference.id), [])
        XCTAssertEqual(reference.sourceTree, "SOURCE_ROOT")
        XCTAssertEqual(rows(result, "App/Loose/Free.swift"), rows(theirs, "App/Loose/Free.swift"))
    }

    func testNothingToDoIsNoPlan() throws {
        let base = try MergeFixture.base()
        let outcome = try replay(["App/Views/Foo.swift"], theirs: base)
        XCTAssertEqual(outcome.plans, [])
        XCTAssertEqual(outcome.project.serialize(), base.serialize())
    }

    /// Review finding: a target's rows compared in order. Theirs re-created
    /// a file with two rows in App, and its build-file IDs sort the other
    /// way; the rows are the same, so the replay changes nothing.
    func testTheSameRowsInAnotherOrderAreNoChange() throws {
        let path = "App/Services/Two.swift"
        let base = try MergeFixture.add([path], to: try MergeFixture.base(), phase: .notBuilt, seed: 3)
        let reference = try XCTUnwrap(base.fileReferences(at: path).first).id
        func twoRows(sources: ObjectID, resources: ObjectID) throws -> Project {
            var project = base
            for (id, phase) in [(sources, appSources), (resources, appResources)] {
                try project.createObject(id, isa: "PBXBuildFile", attributes: [NewEntry("fileRef", project.reference(to: reference))])
                try project.addPhaseEntry(id, to: phase)
            }
            return project
        }
        let current = try twoRows(sources: "BF0000000000000000000001", resources: "BF0000000000000000000002")
        let theirs = try twoRows(sources: "BF0000000000000000000004", resources: "BF0000000000000000000003")
        XCTAssertEqual(MembershipSnapshot(current).references[path]?.rows.map(\.phase), [.sources, .resources])
        XCTAssertEqual(MembershipSnapshot(theirs).references[path]?.rows.map(\.phase), [.resources, .sources])
        let outcome = try Replay.run(paths: [path], current: current, theirs: MembershipSnapshot(theirs),
                                     minter: IDMinter(generator: SplitMix(seed: 42)))
        XCTAssertEqual(outcome.plans.count, 0, "\(outcome.changes)")
        XCTAssertEqual(outcome.project.serialize(), current.serialize())
    }

    /// Review finding: the trial rebuilt ours' snapshot for every unit. A
    /// snapshot passed in gives the same result as one built inside.
    func testTheTrialGivesTheSameResultWithOursSnapshotPassedIn() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: base, platforms: ["ios"])
        let (baseSnapshot, theirsSnapshot) = (MembershipSnapshot(base), MembershipSnapshot(theirs))
        let built = Trial.run(paths: ["App/Services/New.swift"], base: baseSnapshot, ours: base, theirs: theirsSnapshot,
                              minter: IDMinter(generator: SplitMix(seed: 42)))
        let passed = Trial.run(paths: ["App/Services/New.swift"], base: baseSnapshot, ours: base, oursSnapshot: baseSnapshot,
                               theirs: theirsSnapshot, minter: IDMinter(generator: SplitMix(seed: 42)))
        XCTAssertEqual(built, .replayed([]))
        XCTAssertEqual(passed, built)
    }

    // Review finding: a target with two rows for one path (Sources and
    // Resources of App) was replayed as "remove every row, add want[0]".
    // Rows are now matched by phase kind.

    private let twoRowPath = "App/Services/Two.swift"

    /// Base with `twoRowPath` as a reference in no target, then one build
    /// file per `(id, phase, filter)` in `rows`.
    private func withRows(_ rows: [(ObjectID, ObjectID, String?)]) throws -> Project {
        var project = try MergeFixture.add([twoRowPath], to: try MergeFixture.base(), phase: .notBuilt, seed: 3)
        let reference = try XCTUnwrap(project.fileReferences(at: twoRowPath).first).id
        for (id, phase, filter) in rows {
            var attributes = [NewEntry("fileRef", project.reference(to: reference))]
            if let filter { attributes.append(NewEntry("platformFilter", .string(filter))) }
            try project.createObject(id, isa: "PBXBuildFile", attributes: attributes)
            try project.addPhaseEntry(id, to: phase)
        }
        return project
    }

    private func appRows(_ project: Project) -> [String] {
        (MembershipSnapshot(project).references[twoRowPath]?.rows ?? []).map { "\($0.target) \($0.phase.rawValue) \($0.filters) \($0.buildFile)" }.sorted()
    }

    func testASecondRowInOneTargetIsAttached() throws {
        let current = try withRows([("BF0000000000000000000001", appSources, nil)])
        let theirs = try withRows([("BF0000000000000000000001", appSources, nil), ("BF0000000000000000000002", appResources, "ios")])
        let result = try replay([twoRowPath], theirs: theirs, current: current).project
        let rows = MembershipSnapshot(result).references[twoRowPath]?.rows ?? []
        XCTAssertEqual(rows.map(\.masked).sorted { "\($0)" < "\($1)" }, MembershipSnapshot(theirs).references[twoRowPath]?.masked.rows)
        XCTAssertTrue(rows.contains { $0.buildFile == "BF0000000000000000000001" && $0.phase == .sources }, "the Sources row keeps its build file: \(appRows(result))")
    }

    func testOneOfTwoRowsInOneTargetIsDetached() throws {
        let current = try withRows([("BF0000000000000000000001", appSources, nil), ("BF0000000000000000000002", appResources, nil)])
        let theirs = try withRows([("BF0000000000000000000001", appSources, nil)])
        let result = try replay([twoRowPath], theirs: theirs, current: current).project
        XCTAssertEqual(appRows(result), ["App sources [] BF0000000000000000000001"])
    }

    func testOneOfTwoRowsInOneTargetIsReFiltered() throws {
        let current = try withRows([("BF0000000000000000000001", appSources, nil), ("BF0000000000000000000002", appResources, nil)])
        let theirs = try withRows([("BF0000000000000000000001", appSources, nil), ("BF0000000000000000000002", appResources, "ios")])
        let outcome = try replay([twoRowPath], theirs: theirs, current: current)
        XCTAssertEqual(appRows(outcome.project), ["App resources [\"ios\"] BF0000000000000000000002", "App sources [] BF0000000000000000000001"])
        XCTAssertFalse(outcome.changes.contains { $0.action == .deletedObject || $0.action == .createdBuildFile }, "\(outcome.changes)")
    }

    /// Through the trial: no residual, so the unit is replayed rather than offered as a decision.
    func testASecondRowInOneTargetLeavesNoResidual() throws {
        let base = try withRows([("BF0000000000000000000001", appSources, nil)])
        let theirs = try withRows([("BF0000000000000000000001", appSources, nil), ("BF0000000000000000000002", appResources, "ios")])
        let trial = Trial.run(paths: [twoRowPath], base: MembershipSnapshot(base), ours: base, theirs: MembershipSnapshot(theirs),
                              minter: IDMinter(generator: SplitMix(seed: 42)))
        XCTAssertEqual(trial, .replayed([]))
    }

    /// Through the engine: the unit is replayed, the merge passes every
    /// check, and the result holds both of theirs' rows.
    func testASecondRowInOneTargetMerges() throws {
        let base = try withRows([("BF0000000000000000000001", appSources, nil)])
        let theirs = try withRows([("BF0000000000000000000001", appSources, nil), ("BF0000000000000000000002", appResources, "ios")])
        var engine = MergeEngine()
        engine.minter = IDMinter(generator: SplitMix(seed: 1234))
        let report = engine.run(base: base.serialize(), ours: base.serialize(), theirs: theirs.serialize())
        XCTAssertEqual(report.status, .merged, report.error ?? "\(report.checks)")
        XCTAssertEqual(report.units.map(\.classified.outcome), [.replayed])
        let result = try Project.load(try XCTUnwrap(report.result))
        XCTAssertEqual(MembershipSnapshot(result).references[twoRowPath]?.masked, MembershipSnapshot(theirs).references[twoRowPath]?.masked)
        assertPlutilLints(try XCTUnwrap(report.result))
    }
}
