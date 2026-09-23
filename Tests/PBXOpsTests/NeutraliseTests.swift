import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 5.3–5.4: every unit path leaves the base and theirs
/// before the text merge, with `remove`'s planner, only where the version
/// holds a reference for it (design D6).
final class NeutraliseTests: XCTestCase {
    func testUnitPathsAreRemovedOnlyWhereHeld() throws {
        let base = try MergeFixture.base()
        let result = try Neutralise.run(base, paths: ["App/Services/New.swift", "App/Views/Foo.swift"])
        XCTAssertEqual(result.fileReferences(at: "App/Views/Foo.swift"), [])
        XCTAssertNil(result.buildFile("BB0000000000000000000020"))
        XCTAssertEqual(result.fileReferences(at: "App/Services/New.swift"), [])
        XCTAssertNotNil(result.fileReference("AA0000000000000000000230"), "nothing else goes")
        assertPlutilLints(result.serialize())
    }

    func testASynchronizedFolderPathIsNeverRemoved() throws {
        let base = try MergeFixture.base()
        let result = try Neutralise.run(base, paths: ["App/Generated/Made.swift"])
        XCTAssertEqual(result.serialize(), base.serialize())
    }

    func testNothingHeldIsNoChange() throws {
        let base = try MergeFixture.base()
        XCTAssertEqual(try Neutralise.run(base, paths: []).serialize(), base.serialize())
    }

    /// The `skipPresenceFilter` fault: every path in every copy. The planner
    /// refuses the absent path, and the refusal names it.
    func testWithoutThePresenceFilterTheAbsentPathIsNamed() throws {
        let base = try MergeFixture.base()
        XCTAssertThrowsError(try Neutralise.run(base, paths: ["App/Services/New.swift", "App/Views/Foo.swift"], presenceFilter: false)) { error in
            XCTAssertTrue("\(error)".contains("App/Services/New.swift"), "\(error)")
        }
    }

    /// Through the engine: the run fails (exit `1`) naming the absent path, and writes nothing.
    func testWithoutThePresenceFilterTheRunFailsNamingThePath() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"])
        var engine = MergeEngine()
        XCTAssertEqual(engine.run(base: base.serialize(), ours: base.serialize(), theirs: theirs.serialize()).status, .merged)
        engine.faults = .skipPresenceFilter
        let report = engine.run(base: base.serialize(), ours: base.serialize(), theirs: theirs.serialize())
        XCTAssertEqual(report.status, .failed)
        XCTAssertTrue(report.result == nil)
        XCTAssertTrue(report.error?.contains("App/Services/New.swift") == true, report.error ?? "")
    }
}

/// Review finding: neutralisation prunes a group its unit paths leave
/// empty. A group theirs changed apart from its children stays in both
/// neutralised copies, so the text merge carries theirs' change to it.
final class NeutralisePrunedGroupTests: XCTestCase {
    private func soloBase() throws -> (Project, ObjectID) {
        let base = try MergeFixture.add(["App/Solo/Solo.swift"], to: try MergeFixture.base(), targets: ["App"], seed: 7)
        let group = try XCTUnwrap(base.groups.first { base.resolvedPath(of: $0.id)?.description == "App/Solo" })
        return (base, group.id)
    }

    func testAGroupTheirsChangedIsKeptInBothCopies() throws {
        let (base, group) = try soloBase()
        let changed = try MergeFixture.attribute("indentWidth", .string("2"), of: group, in: base)
        let theirs = try MergeFixture.remove(["App/Solo/Solo.swift"], from: changed, target: "App")
        let kept = Neutralise.keptGroups(base: base, theirs: theirs, paths: ["App/Solo/Solo.swift"])
        XCTAssertEqual(kept, [group])
        XCTAssertNotNil(try Neutralise.run(base, paths: ["App/Solo/Solo.swift"], keeping: kept).group(group))
        XCTAssertNotNil(try Neutralise.run(theirs, paths: ["App/Solo/Solo.swift"], keeping: kept).group(group))
    }

    func testAGroupTheirsLeftAloneIsPrunedAsBefore() throws {
        let (base, group) = try soloBase()
        let theirs = try MergeFixture.remove(["App/Solo/Solo.swift"], from: base, target: "App")
        XCTAssertEqual(Neutralise.keptGroups(base: base, theirs: theirs, paths: ["App/Solo/Solo.swift"]), [])
        XCTAssertNil(try Neutralise.run(theirs, paths: ["App/Solo/Solo.swift"]).group(group))
    }

    /// Theirs deleted the file and the group with it: nothing is kept, so
    /// the text merge sees no modify/delete conflict on the group.
    func testAGroupTheirsDeletedIsNotKept() throws {
        let (base, _) = try soloBase()
        let theirs = try MergeFixture.remove(["App/Solo/Solo.swift"], from: base)
        XCTAssertEqual(Neutralise.keptGroups(base: base, theirs: theirs, paths: ["App/Solo/Solo.swift"]), [])
        var engine = MergeEngine()
        engine.minter = IDMinter(generator: SplitMix(seed: 1234))
        let report = engine.run(base: base.serialize(), ours: base.serialize(), theirs: theirs.serialize())
        XCTAssertEqual(report.status, .merged, report.error ?? "\(report.checks)")
        XCTAssertTrue(report.hunks.isEmpty)
    }

    /// The finding's scenario through the engine: theirs detaches the only
    /// child of a group and sets the group's `indentWidth`; the merge keeps both.
    func testTheirsChangeToAnEmptiedGroupSurvivesTheMerge() throws {
        let (base, group) = try soloBase()
        let changed = try MergeFixture.attribute("indentWidth", .string("2"), of: group, in: base)
        let theirs = try MergeFixture.remove(["App/Solo/Solo.swift"], from: changed, target: "App")
        var engine = MergeEngine()
        engine.minter = IDMinter(generator: SplitMix(seed: 1234))
        let report = engine.run(base: base.serialize(), ours: base.serialize(), theirs: theirs.serialize())
        XCTAssertEqual(report.status, .merged, report.error ?? "\(report.checks)")
        let result = try Project.load(try XCTUnwrap(report.result))
        XCTAssertEqual(result.object(group)?.string("indentWidth"), "2")
        XCTAssertEqual(result.membership(of: try XCTUnwrap(result.fileReferences(at: "App/Solo/Solo.swift").first).id).targets, [])
        assertPlutilLints(try XCTUnwrap(report.result))
    }

    /// A group theirs created for a new file, with an attribute of its own:
    /// kept, so the replay's `add` finds it and the attribute survives.
    func testAGroupTheirsAddedKeepsItsAttributes() throws {
        let base = try MergeFixture.base()
        let added = try MergeFixture.add(["App/Fresh/Fresh.swift"], to: base, targets: ["App"], seed: 7)
        let group = try XCTUnwrap(added.groups.first { added.resolvedPath(of: $0.id)?.description == "App/Fresh" })
        let theirs = try MergeFixture.attribute("indentWidth", .string("2"), of: group.id, in: added)
        XCTAssertEqual(Neutralise.keptGroups(base: base, theirs: theirs, paths: ["App/Fresh/Fresh.swift"]), [group.id])
        let report = try MergeFixture.merge(ours: base, theirs: theirs)
        XCTAssertEqual(report.status, .merged, report.error ?? "\(report.checks)")
        let result = try Project.load(try XCTUnwrap(report.result))
        let groups = result.groups.filter { result.resolvedPath(of: $0.id)?.description == "App/Fresh" }
        XCTAssertEqual(groups.map(\.id), [group.id])
        XCTAssertEqual(result.object(group.id)?.string("indentWidth"), "2")
        XCTAssertEqual(result.fileReferences(at: "App/Fresh/Fresh.swift").count, 1)
    }

    /// Theirs deleted the only file of a group but kept the group, with a
    /// change: the replay's removal does not prune it, so the result holds
    /// the group as theirs does.
    func testAGroupTheirsEmptiedAndKeptIsNotPrunedByTheReplay() throws {
        let (base, group) = try soloBase()
        let changed = try MergeFixture.attribute("indentWidth", .string("2"), of: group, in: base)
        let theirs = try RemovePlanner.plan(["App/Solo/Solo.swift"], in: changed, all: true, keeping: [group]).apply(to: changed)
        XCTAssertNotNil(theirs.group(group))
        var engine = MergeEngine()
        engine.minter = IDMinter(generator: SplitMix(seed: 1234))
        let report = engine.run(base: base.serialize(), ours: base.serialize(), theirs: theirs.serialize())
        XCTAssertEqual(report.status, .merged, report.error ?? "\(report.checks)")
        let result = try Project.load(try XCTUnwrap(report.result))
        XCTAssertEqual(result.fileReferences(at: "App/Solo/Solo.swift"), [])
        XCTAssertEqual(result.group(group)?.children, [])
        XCTAssertEqual(result.object(group)?.string("indentWidth"), "2")
    }
}
