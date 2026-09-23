import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 4.5–4.6: the trial replay against ours and the
/// per-path comparison with theirs (design D4, D9 E). What the replay
/// cannot reproduce is a residual.
final class ResidualTests: XCTestCase {
    private func trial(_ paths: [String], theirs: Project, ours: Project? = nil) throws -> Trial.Result {
        let base = try MergeFixture.base()
        return Trial.run(paths: paths, base: MembershipSnapshot(base), ours: try ours ?? base, theirs: MembershipSnapshot(theirs),
                         minter: IDMinter(generator: SplitMix(seed: 5)))
    }

    private func residuals(_ result: Trial.Result, file: StaticString = #filePath, line: UInt = #line) -> [Residual] {
        guard case .replayed(let residuals) = result else {
            XCTFail("the trial did not run: \(result)", file: file, line: line)
            return []
        }
        return residuals
    }

    // Spec: Build-file settings are a residual.
    func testBuildFileSettingsAreAResidual() throws {
        let added = try MergeFixture.add(["AppKit/Extra.h"], to: try MergeFixture.base(), targets: ["AppKit"])
        let buildFile = try XCTUnwrap(MembershipSnapshot(added).references["AppKit/Extra.h"]?.rows.first?.buildFile)
        let theirs = try MergeFixture.attribute(
            "settings", .dictionary([NewEntry("ATTRIBUTES", .array([.string("Public")]))]), of: buildFile, in: added)
        let found = residuals(try trial(["AppKit/Extra.h"], theirs: theirs))
        XCTAssertEqual(found.map(\.kind), [.settings(target: "AppKit")], "\(found)")
        XCTAssertEqual(found.first?.path, "AppKit/Extra.h")
        XCTAssertEqual(found.first?.theirs, "{ATTRIBUTES = (Public, ); }")
        XCTAssertNil(found.first?.merged)
    }

    // Spec: A group other than the directory's is a residual.
    func testAGroupOtherThanTheDirectorysIsAResidual() throws {
        var theirs = try MergeFixture.base()
        try theirs.createObject("AB0000000000000000000020", isa: Kind.fileReference, attributes: [
            NewEntry("lastKnownFileType", .string("sourcecode.swift")), NewEntry("path", .string("../Views/Bar.swift")),
            NewEntry("sourceTree", .string("<group>")),
        ])
        try theirs.addChild("AB0000000000000000000020", to: "AA0000000000000000000013")
        try theirs.createObject("AB0000000000000000000021", isa: Kind.buildFile, attributes: [NewEntry("fileRef", theirs.reference(to: "AB0000000000000000000020"))])
        try theirs.addPhaseEntry("AB0000000000000000000021", to: "CC0000000000000000000001")
        XCTAssertNotNil(MembershipSnapshot(theirs).references["App/Views/Bar.swift"])
        let found = residuals(try trial(["App/Views/Bar.swift"], theirs: theirs))
        XCTAssertTrue(found.contains { $0.kind == .parentGroup }, "\(found)")
        XCTAssertEqual(found.first { $0.kind == .parentGroup }?.theirs, "App/Services")
        XCTAssertEqual(found.first { $0.kind == .parentGroup }?.merged, "App/Views")
    }

    func testAnAttributeTheirsSetOnAnAddedReferenceIsAResidual() throws {
        let added = try MergeFixture.add(["App/Services/New.swift"], to: try MergeFixture.base(), targets: ["App"])
        let reference = try XCTUnwrap(MembershipSnapshot(added).references["App/Services/New.swift"]?.id)
        let theirs = try MergeFixture.attribute("includeInIndex", .string("0"), of: reference, in: added)
        let found = residuals(try trial(["App/Services/New.swift"], theirs: theirs))
        XCTAssertEqual(found.map(\.kind), [.attribute("includeInIndex")], "\(found)")
        XCTAssertEqual(found.first?.theirs, "0")
    }

    func testAReFilterWithOursAttributeHasNoResidual() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.attribute("fileEncoding", .string("4"), of: "AA0000000000000000000260", in: base)
        let detached = try MergeFixture.remove(["App/Filtered/F1.swift"], from: base, target: "App")
        let theirs = try MergeFixture.add(["App/Filtered/F1.swift"], to: detached, targets: ["App"], platforms: ["ios", "macos"])
        XCTAssertEqual(residuals(try trial(["App/Filtered/F1.swift"], theirs: theirs, ours: ours)), [])
    }

    func testATrialThatThrowsLeavesOnlyOurs() throws {
        var theirs = try MergeFixture.base()
        try theirs.createObject("CC0000000000000000000099", isa: "PBXResourcesBuildPhase", attributes: [
            NewEntry("buildActionMask", .string("2147483647")), NewEntry("files", .array([])),
            NewEntry("runOnlyForDeploymentPostprocessing", .string("0")),
        ])
        try theirs.setAttribute("buildPhases", of: "DD0000000000000000000002", to: .array([
            theirs.reference(to: "CC0000000000000000000004"), theirs.reference(to: "CC0000000000000000000006"),
            theirs.reference(to: "CC0000000000000000000099"),
        ]))
        theirs = try MergeFixture.add(["App/Extension/Data.json"], to: theirs, targets: ["AppExtension"])
        let result = try trial(["App/Extension/Data.json"], theirs: theirs)
        guard case .failed(let message) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(message.contains("has no Resources phase"), message)
    }

    // MARK: Conflicting attributes (issue #20)

    // Spec: A conflicting attribute is a difference whichever value the result holds.
    func testAConflictingAttributeIsAResidualWhicheverValueTheResultHolds() throws {
        let sides = try MergeFixture.attributeConflict()
        let found = residuals(try trial(["App/Filtered/F1.swift"], theirs: sides.theirs, ours: sides.ours))
        XCTAssertEqual(found.map(\.kind), [.attribute("fileEncoding")], "\(found)")
        let residual = try XCTUnwrap(found.first)
        XCTAssertTrue(residual.conflicting, "\(residual)")
        XCTAssertEqual(residual.object, "AA0000000000000000000260")
        XCTAssertEqual(residual.ours, "4")
        XCTAssertEqual(residual.theirs, "10")
        XCTAssertEqual(residual.merged, "4", "the replay keeps ours' reference")
        XCTAssertTrue(residual.description.contains("both sides changed fileEncoding"), residual.description)

        // The same conflict on a result that holds theirs' value.
        let asTheirs = PathComparison.compare(paths: ["App/Filtered/F1.swift"], base: MembershipSnapshot(sides.base),
                                              ours: MembershipSnapshot(sides.ours), theirs: MembershipSnapshot(sides.theirs),
                                              result: MembershipSnapshot(sides.theirs))
        let conflicts = asTheirs.filter(\.conflicting)
        XCTAssertEqual(conflicts.map(\.kind), [.attribute("fileEncoding")], "\(asTheirs)")
        XCTAssertEqual(conflicts.first?.ours, "4")
        XCTAssertEqual(conflicts.first?.merged, "10")
    }

    // Spec: A build-file attribute both sides changed is a conflict.
    func testABuildFileAttributeBothSidesChangedIsAConflict() throws {
        let base = try MergeFixture.base()
        let row = { (project: Project) in MembershipSnapshot(project).references["App/Filtered/F1.swift"]?.rows.first { $0.target == "App" } }
        let ours = try MergeFixture.attribute("compilerFlags", .string("-DOURS"), of: try XCTUnwrap(row(base)?.buildFile), in: base)
        let detached = try MergeFixture.remove(["App/Filtered/F1.swift"], from: base, target: "App")
        let refiltered = try MergeFixture.add(["App/Filtered/F1.swift"], to: detached, targets: ["App"], platforms: ["ios"])
        let theirs = try MergeFixture.attribute("compilerFlags", .string("-DTHEIRS"), of: try XCTUnwrap(row(refiltered)?.buildFile),
                                                in: refiltered)
        let found = residuals(try trial(["App/Filtered/F1.swift"], theirs: theirs, ours: ours))
        let conflict = try XCTUnwrap(found.first { $0.conflicting }, "\(found)")
        XCTAssertEqual(conflict.kind, .buildFileAttribute(target: "App", key: "compilerFlags"))
        XCTAssertEqual(conflict.ours, "\"-DOURS\"", "the value as the file spells it")
        XCTAssertEqual(conflict.theirs, "\"-DTHEIRS\"")
    }

    func testAnAttributeBothSidesChangedToTheSameValueHasNoResidual() throws {
        let sides = try MergeFixture.attributeConflict(ours: "4", theirs: "4")
        XCTAssertEqual(residuals(try trial(["App/Filtered/F1.swift"], theirs: sides.theirs, ours: sides.ours)), [])
    }

    /// The conflicts of design D3, found without a replay, are the
    /// conflicting residuals of the comparison.
    func testConflictsAreTheComparisonsConflictingResiduals() throws {
        let sides = try MergeFixture.attributeConflict()
        let found = PathComparison.conflicts(paths: ["App/Filtered/F1.swift"], base: MembershipSnapshot(sides.base),
                                             ours: MembershipSnapshot(sides.ours), theirs: MembershipSnapshot(sides.theirs))
        XCTAssertEqual(found.map(\.kind), [.attribute("fileEncoding")], "\(found)")
        XCTAssertTrue(found.allSatisfy(\.conflicting))
        let same = try MergeFixture.attributeConflict(ours: "4", theirs: "4")
        XCTAssertEqual(PathComparison.conflicts(paths: ["App/Filtered/F1.swift"], base: MembershipSnapshot(same.base),
                                                ours: MembershipSnapshot(same.ours), theirs: MembershipSnapshot(same.theirs)), [])
    }

    func testAFaithfulReplayHasNoResidual() throws {
        let theirs = try MergeFixture.move("App/Views/Foo.swift", to: "App/Features/Foo.swift", in: try MergeFixture.base())
        XCTAssertEqual(residuals(try trial(["App/Features/Foo.swift", "App/Views/Foo.swift"], theirs: theirs)), [])
    }
}
