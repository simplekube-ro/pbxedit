import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command task 8.1: the three-way fixtures the command tests read,
/// `Tests/Fixtures/merge/<scenario>/{base,ours,theirs}.pbxproj`, built from
/// the Xcode-saved base with pbxedit's own planners. They are committed, so
/// the command tests do not depend on the planners they exercise; this
/// test checks the committed files are what the recipe builds, and with
/// `PBXEDIT_WRITE_MERGE_FIXTURES=1` rewrites them.
final class MergeFixtureFileTests: XCTestCase {
    static let writeVariable = "PBXEDIT_WRITE_MERGE_FIXTURES"

    /// Scenario → (base, ours, theirs); `base` is `nil` for the Xcode-saved
    /// fixture, which all but one scenario start from.
    static func scenarios() throws -> [(name: String, base: Project?, ours: Project, theirs: Project)] {
        let base = try MergeFixture.base()
        let a1: ObjectID = "1000000000000000000000A1"

        let extraAdded = try MergeFixture.add(["AppKit/Extra.h"], to: base, targets: ["AppKit"], seed: 3)
        let extraBuildFile = try XCTUnwrap(MembershipSnapshot(extraAdded).references["AppKit/Extra.h"]?.rows.first?.buildFile)
        let settings = try MergeFixture.attribute("settings", .dictionary([NewEntry("ATTRIBUTES", .array([.string("Public")]))]),
                                                  of: extraBuildFile, in: extraAdded)

        var phaseRemoved = try MergeFixture.remove(["AppKit/AppKit.h"], from: base, target: "AppKit")
        phaseRemoved = try MergeFixture.add(["AppKit/AppKit.h"], to: phaseRemoved, targets: ["AppKit"], phase: .sources, seed: 4)
        try phaseRemoved.setAttribute("buildPhases", of: "DD0000000000000000000004", to: .array([
            phaseRemoved.reference(to: "CC0000000000000000000007"), phaseRemoved.reference(to: "CC0000000000000000000009"),
        ]))
        try phaseRemoved.deleteObject("CC0000000000000000000008")

        let conflict = try MergeFixture.attributeConflict()
        let sharedArray = try MergeEngineTests.sharedArraySides()
        let packages = try MergeEngineTests.packageObjectSides()

        return [
            ("both-add", nil, try MergeFixture.add(["App/Views/Bar.swift"], to: base, seed: 1),
             try MergeFixture.add(["App/Services/New.swift"], to: base, platforms: ["ios"], seed: 2)),
            ("rename", nil, try MergeFixture.add(["App/Views/Bar.swift"], to: base, seed: 1),
             try MergeFixture.move("App/Views/Foo.swift", to: "App/Features/Foo.swift", in: base)),
            ("conflicting-setting", nil, try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: base),
             try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a1, of: base)),
            ("settings-residual", nil, base, settings),
            ("theirs-adds-target", nil, base, try MergeEngineTests.addingTarget("Widget", to: base)),
            ("phase-removed", nil, base, phaseRemoved),
            ("shared-array", nil, sharedArray.ours, sharedArray.theirs),
            ("both-regions", nil, try MergeFixture.knownRegions(["de", "en", "Base"], of: base),
             try MergeFixture.knownRegions(["fr", "en", "Base"], of: base)),
            ("both-objects", packages.base, packages.ours, packages.theirs),
            ("attribute-conflict", nil, conflict.ours, conflict.theirs),
        ]
    }

    func testTheCommittedFixturesAreWhatTheRecipeBuilds() throws {
        let write = ProcessInfo.processInfo.environment[MergeFixtureFileTests.writeVariable] == "1"
        for scenario in try MergeFixtureFileTests.scenarios() {
            let directory = Fixtures.directory.appendingPathComponent("merge/\(scenario.name)")
            let baseBytes = try scenario.base?.serialize() ?? MergeFixture.baseBytes()
            let files = [("base", baseBytes), ("ours", scenario.ours.serialize()), ("theirs", scenario.theirs.serialize())]
            if write { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            for (name, bytes) in files {
                let url = directory.appendingPathComponent("\(name).pbxproj")
                if write {
                    try Data(bytes).write(to: url)
                } else {
                    XCTAssertTrue(try Fixtures.load("merge/\(scenario.name)/\(name).pbxproj") == bytes,
                                  "merge/\(scenario.name)/\(name).pbxproj is stale; rerun with \(MergeFixtureFileTests.writeVariable)=1")
                }
            }
        }
    }

    /// What each committed scenario comes to, as the command tests rely on.
    func testEachScenarioEndsAsTheCommandTestsExpect() throws {
        let expected: [String: MergeReport.Status] = [
            "both-add": .merged, "rename": .merged, "conflicting-setting": .decisionsNeeded, "settings-residual": .decisionsNeeded,
            "theirs-adds-target": .unsupported, "phase-removed": .decisionsNeeded, "shared-array": .decisionsNeeded,
            "both-regions": .decisionsNeeded, "both-objects": .decisionsNeeded, "attribute-conflict": .decisionsNeeded,
        ]
        for scenario in try MergeFixtureFileTests.scenarios() {
            let baseBytes = try scenario.base?.serialize() ?? MergeFixture.baseBytes()
            let report = MergeEngine().run(base: baseBytes, ours: scenario.ours.serialize(), theirs: scenario.theirs.serialize())
            XCTAssertEqual(report.status, expected[scenario.name], "\(scenario.name): \(report.error ?? "")")
            if scenario.name == "phase-removed" {
                let decided = MergeEngine(decisions: try MergeFixture.decide(report, hunks: { _ in "theirs" }))
                    .run(base: baseBytes, ours: scenario.ours.serialize(), theirs: scenario.theirs.serialize())
                XCTAssertEqual(decided.status, .failed)
                XCTAssertEqual(decided.checks.last?.check, .F)
            }
        }
    }
}
