import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 5.1–5.2: each unit is replayed, skipped or decided (design D4).
final class ClassificationTests: XCTestCase {
    private func classify(ours: Project, theirs: Project) throws -> [ClassifiedUnit] {
        let base = MembershipSnapshot(try MergeFixture.base())
        let (o, t) = (MembershipSnapshot(ours), MembershipSnapshot(theirs))
        let units = MergeUnit.discover(base: base, ours: o, theirs: t)
        return ClassifiedUnit.classify(units, base: base, ours: ours, oursSnapshot: o, theirs: t, minter: IDMinter(generator: SplitMix(seed: 3)))
    }

    // Spec: Both sides add different files.
    func testBothSidesAddDifferentFiles() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.add(["App/Views/Bar.swift"], to: base)
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: base, platforms: ["ios"], seed: 2)
        let classified = try classify(ours: ours, theirs: theirs)
        XCTAssertEqual(classified.map(\.unit.paths), [["App/Services/New.swift"]])
        XCTAssertEqual(classified.first?.outcome, .replayed)
        XCTAssertEqual(classified.first?.choices, [])
        XCTAssertEqual(classified.first?.residuals, [])
    }

    // Spec: Both sides made the same change.
    func testBothSidesMadeTheSameChange() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.add(["App/Views/Bar.swift"], to: base, seed: 1)
        let theirs = try MergeFixture.add(["App/Views/Bar.swift"], to: base, seed: 2)
        let classified = try classify(ours: ours, theirs: theirs)
        XCTAssertEqual(classified.map(\.unit.paths), [["App/Views/Bar.swift"]])
        XCTAssertEqual(classified.first?.outcome, .skipped)
    }

    // Spec: Different changes to one file.
    func testDifferentChangesToOneFile() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.move("App/Filtered/F1.swift", to: "App/Views/F1.swift", in: base)
        let theirs = try MergeFixture.remove(["App/Filtered/F1.swift"], from: base)
        let classified = try classify(ours: ours, theirs: theirs)
        XCTAssertEqual(classified.count, 1)
        let unit = try XCTUnwrap(classified.first)
        XCTAssertEqual(unit.unit.paths, ["App/Filtered/F1.swift", "App/Views/F1.swift"])
        XCTAssertEqual(unit.outcome, .decision)
        XCTAssertEqual(unit.choices, [.ours, .theirs])
        XCTAssertNil(unit.reason)
        XCTAssertEqual(unit.states.map(\.path), ["App/Filtered/F1.swift", "App/Views/F1.swift"])
        let filtered = unit.states[0]
        XCTAssertEqual(filtered.base?.rows.map(\.description), ["App (sources) [ios]"])
        XCTAssertNil(filtered.ours)
        XCTAssertNil(filtered.theirs)
        let views = unit.states[1]
        XCTAssertNil(views.base)
        XCTAssertEqual(views.ours?.rows.map(\.description), ["App (sources) [ios]"])
        XCTAssertNil(views.theirs)
    }

    // Spec: Build-file settings are a residual.
    func testBuildFileSettingsMakeADecisionWithoutTheirs() throws {
        let base = try MergeFixture.base()
        let added = try MergeFixture.add(["AppKit/Extra.h"], to: base, targets: ["AppKit"])
        let buildFile = try XCTUnwrap(MembershipSnapshot(added).references["AppKit/Extra.h"]?.rows.first?.buildFile)
        let theirs = try MergeFixture.attribute("settings", .dictionary([NewEntry("ATTRIBUTES", .array([.string("Public")]))]), of: buildFile, in: added)
        let classified = try classify(ours: base, theirs: theirs)
        let unit = try XCTUnwrap(classified.first)
        XCTAssertEqual(unit.outcome, .decision)
        XCTAssertEqual(unit.choices, [.ours, .theirsMembership])
        XCTAssertEqual(unit.residuals.map(\.kind), [.settings(target: "AppKit")])
    }

    func testAReplayThatCannotRunOffersOnlyOurs() throws {
        let base = try MergeFixture.base()
        // Ours removed AppKit's Headers phase; theirs adds a header to it.
        var ours = base
        try ours.setAttribute("buildPhases", of: "DD0000000000000000000004", to: .array([
            ours.reference(to: "CC0000000000000000000007"), ours.reference(to: "CC0000000000000000000009"),
        ]))
        let theirs = try MergeFixture.add(["AppKit/Extra.h"], to: base, targets: ["AppKit"])
        let unit = try XCTUnwrap(try classify(ours: ours, theirs: theirs).first { $0.unit.paths == ["AppKit/Extra.h"] })
        XCTAssertEqual(unit.outcome, .decision)
        XCTAssertEqual(unit.choices, [.ours])
        XCTAssertTrue(unit.reason?.contains("has no Headers phase") == true, "\(unit.reason ?? "nil")")
    }
}
