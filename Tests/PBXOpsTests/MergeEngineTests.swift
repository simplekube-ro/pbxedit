import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command task 7.1: the spec scenarios of `merge` through the engine.
/// Every merged result is asserted on its model, checked as the header of
/// `tasks.md` says: check A (the rule set relative to the inputs) passed,
/// and `plutil -lint` accepts the bytes.
final class MergeEngineTests: XCTestCase {
    private let a1: ObjectID = "1000000000000000000000A1"
    private let a2: ObjectID = "1000000000000000000000A2"

    /// The merged project, after asserting the status and the checks.
    private func merged(_ report: MergeReport, file: StaticString = #filePath, line: UInt = #line) throws -> Project {
        XCTAssertEqual(report.status, .merged, "\(report.error ?? "") \(report.checks.filter { !$0.passed })", file: file, line: line)
        if !report.nothingToMerge {
            XCTAssertEqual(report.checks.map(\.check), [.C, .F, .D, .E, .B, .A], file: file, line: line)
            XCTAssertTrue(report.checks.allSatisfy(\.passed), file: file, line: line)
        }
        let bytes = try XCTUnwrap(report.result, file: file, line: line)
        assertPlutilLints(bytes, file: file, line: line)
        return try Project.load(bytes)
    }

    private func text(_ project: Project) -> String { String(decoding: project.serialize(), as: UTF8.self) }

    // Spec: Both sides add different files.
    func testBothSidesAddDifferentFiles() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.add(["App/Views/Bar.swift"], to: base)
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: base, platforms: ["ios"], seed: 2)
        let report = try MergeFixture.merge(ours: ours, theirs: theirs)
        let result = try merged(report)
        XCTAssertEqual(report.units.map { $0.classified.outcome }, [.replayed])
        let sources = try XCTUnwrap(result.buildPhase("CC0000000000000000000001"))
        let new = try XCTUnwrap(result.fileReferences(at: "App/Services/New.swift").first)
        let newBuildFile = try XCTUnwrap(result.buildFiles(for: new.id).first)
        XCTAssertEqual(newBuildFile.platformFilter, "ios")
        XCTAssertTrue(sources.files.contains(newBuildFile.id))
        let bar = try XCTUnwrap(MembershipSnapshot(ours).references["App/Views/Bar.swift"])
        XCTAssertEqual(result.fileReferences(at: "App/Views/Bar.swift").map(\.id), [bar.id], "ours' IDs")
        XCTAssertEqual(result.buildFiles(for: bar.id).map(\.id), bar.buildFiles)
        XCTAssertTrue(sources.files.contains(bar.buildFiles[0]))
        XCTAssertFalse(report.units[0].changes.isEmpty, "the replay's changes are reported")
    }

    // Spec: Rename is one unit.
    func testRenameIsOneUnit() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.move("App/Views/Foo.swift", to: "App/Features/Foo.swift", in: base)
        let report = try MergeFixture.merge(ours: base, theirs: theirs)
        let result = try merged(report)
        XCTAssertEqual(report.units.map(\.classified.unit.paths), [["App/Features/Foo.swift", "App/Views/Foo.swift"]])
        XCTAssertEqual(report.units.first?.classified.outcome, .replayed)
        XCTAssertEqual(result.fileReferences(at: "App/Features/Foo.swift").map(\.id), ["AA0000000000000000000120"])
        XCTAssertEqual(result.phases(of: "BB0000000000000000000020").map(\.id), ["CC0000000000000000000001"])
    }

    // Spec: A file no target builds.
    func testAFileNoTargetBuilds() throws {
        let base = try MergeFixture.base()
        let report = try MergeFixture.merge(ours: base, theirs: try MergeFixture.add(["App/Notes.md"], to: base))
        let result = try merged(report)
        XCTAssertEqual(report.units.map(\.classified.unit.paths), [["App/Notes.md"]])
        let notes = try XCTUnwrap(result.fileReferences(at: "App/Notes.md").first)
        XCTAssertEqual(result.parents(of: notes.id).map(\.id), ["AA0000000000000000000002"])
        XCTAssertEqual(result.buildFiles(for: notes.id), [])
    }

    // Spec: Unmanaged changes are not units.
    func testUnmanagedChangesTravelAsText() throws {
        let base = try MergeFixture.base()
        var theirs = base
        try theirs.createObject("AB0000000000000000000010", isa: Kind.fileReference, attributes: [
            NewEntry("lastKnownFileType", .string("wrapper.framework")), NewEntry("name", .string("Combine.framework")),
            NewEntry("path", .string("System/Library/Frameworks/Combine.framework")), NewEntry("sourceTree", .string("SDKROOT")),
        ])
        try theirs.addChild("AB0000000000000000000010", to: "AA0000000000000000000007")
        try theirs.createObject("AB0000000000000000000011", isa: Kind.buildFile, attributes: [NewEntry("fileRef", theirs.reference(to: "AB0000000000000000000010"))])
        try theirs.addPhaseEntry("AB0000000000000000000011", to: "CC0000000000000000000002")
        let report = try MergeFixture.merge(ours: base, theirs: theirs)
        let result = try merged(report)
        XCTAssertEqual(report.units, [])
        XCTAssertEqual(result.fileReference("AB0000000000000000000010"), theirs.fileReference("AB0000000000000000000010"))
        XCTAssertEqual(result.buildFile("AB0000000000000000000011"), theirs.buildFile("AB0000000000000000000011"))
        XCTAssertEqual(result.serialize(), theirs.serialize(), "ours is the base: the merge is theirs")
    }

    // Spec: Both sides made the same change.
    func testBothSidesMadeTheSameChange() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.add(["App/Views/Bar.swift"], to: base, seed: 1)
        let theirs = try MergeFixture.add(["App/Views/Bar.swift"], to: base, seed: 2)
        let report = try MergeFixture.merge(ours: ours, theirs: theirs)
        let result = try merged(report)
        XCTAssertEqual(report.units.map(\.classified.outcome), [.skipped])
        XCTAssertEqual(result.serialize(), ours.serialize())
    }

    // Spec: Different changes to one file.
    func testDifferentChangesToOneFileNeedADecision() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.move("App/Filtered/F1.swift", to: "App/Views/F1.swift", in: base)
        let theirs = try MergeFixture.remove(["App/Filtered/F1.swift"], from: base)
        let report = try MergeFixture.merge(ours: ours, theirs: theirs)
        XCTAssertEqual(report.status, .decisionsNeeded)
        XCTAssertTrue(report.result == nil)
        XCTAssertEqual(report.units.map(\.classified.choices), [[.ours, .theirs]])
        XCTAssertEqual(report.template?.units.keys.sorted(), [report.units[0].key])
    }

    // Spec: Keep theirs on delete against move.
    func testKeepTheirsOnDeleteAgainstMove() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.remove(["App/Filtered/F1.swift"], from: base)
        let theirs = try MergeFixture.move("App/Filtered/F1.swift", to: "App/Views/F1.swift", in: base)
        let open = try MergeFixture.merge(ours: ours, theirs: theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        let report = try MergeFixture.merge(ours: ours, theirs: theirs, decisions: try MergeFixture.decide(open, units: { _ in "theirs" }))
        let result = try merged(report)
        XCTAssertEqual(report.units.map(\.decision), [.theirs])
        let reference = try XCTUnwrap(result.fileReferences(at: "App/Views/F1.swift").first)
        let buildFiles = result.buildFiles(for: reference.id)
        XCTAssertEqual(buildFiles.map(\.platformFilter), ["ios"])
        XCTAssertEqual(buildFiles.flatMap { result.phases(of: $0.id).flatMap { result.targets(owning: $0.id).map(\.name) } }, ["App"])
        XCTAssertEqual(result.fileReferences(at: "App/Filtered/F1.swift"), [])
    }

    // Spec: A re-filter keeps ours' attribute.
    func testAReFilterKeepsOursAttribute() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.attribute("fileEncoding", .string("4"), of: "AA0000000000000000000260", in: base)
        let detached = try MergeFixture.remove(["App/Filtered/F1.swift"], from: base, target: "App")
        let theirs = try MergeFixture.add(["App/Filtered/F1.swift"], to: detached, targets: ["App"], platforms: ["ios", "macos"])
        let report = try MergeFixture.merge(ours: ours, theirs: theirs)
        let result = try merged(report)
        XCTAssertEqual(report.units.map(\.classified.outcome), [.replayed])
        XCTAssertEqual(result.fileReference("AA0000000000000000000260")?.object.string("fileEncoding"), "4")
        XCTAssertEqual(result.buildFiles(for: "AA0000000000000000000260").map(\.id), ["BB0000000000000000000140"])
        XCTAssertTrue(text(result).contains("BB0000000000000000000140 /* F1.swift in Sources */ = {isa = PBXBuildFile; fileRef = "
            + "AA0000000000000000000260 /* F1.swift */; platformFilters = (ios, macos, ); };"), text(result))
    }

    // Spec: A conflicting attribute makes a unit a decision.
    // Spec: Theirs-membership owes the conflicting attribute.
    func testAConflictingAttributeMakesAUnitADecision() throws {
        let sides = try MergeFixture.attributeConflict()
        let open = try MergeFixture.merge(ours: sides.ours, theirs: sides.theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertTrue(open.result == nil, "nothing is written")
        XCTAssertEqual(open.units.map(\.classified.outcome), [.decision])
        XCTAssertEqual(open.units.map(\.classified.choices), [[.ours, .theirsMembership]])
        let residual = try XCTUnwrap(open.units.first?.classified.residuals.first { $0.conflicting },
                                     "\(open.units.first?.classified.residuals ?? [])")
        XCTAssertEqual(residual.kind, .attribute("fileEncoding"))
        XCTAssertEqual(residual.object, "AA0000000000000000000260")
        XCTAssertEqual([residual.ours, residual.theirs], ["4", "10"])

        let report = try MergeFixture.merge(ours: sides.ours, theirs: sides.theirs,
                                            decisions: try MergeFixture.decide(open, units: { _ in "theirs-membership" }))
        let result = try merged(report)
        XCTAssertEqual(report.owed.map(\.kind), [.attribute("fileEncoding")])
        XCTAssertEqual(report.owed.first?.ours, "4")
        XCTAssertEqual(result.fileReference("AA0000000000000000000260")?.object.string("fileEncoding"), "4", "ours' value, owed")
        XCTAssertEqual(MembershipSnapshot(result).references["App/Filtered/F1.swift"]?.rows.map(\.filters), [["ios", "macos"]], "theirs' membership")
    }

    // Spec: Both sides re-filter and conflict.
    func testBothSidesReFilterAndConflict() throws {
        let sides = try MergeFixture.attributeConflict(oursFilters: ["macos"])
        let open = try MergeFixture.merge(ours: sides.ours, theirs: sides.theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertEqual(open.units.map(\.classified.choices), [[.ours, .theirsMembership]], "not theirs")
        let report = try MergeFixture.merge(ours: sides.ours, theirs: sides.theirs,
                                            decisions: try MergeFixture.decide(open, units: { _ in "theirs-membership" }))
        let result = try merged(report)
        XCTAssertEqual(report.owed.map(\.kind), [.attribute("fileEncoding")])
        XCTAssertEqual(MembershipSnapshot(result).references["App/Filtered/F1.swift"]?.rows.map(\.filters), [["ios", "macos"]])
        XCTAssertEqual(result.fileReference("AA0000000000000000000260")?.object.string("fileEncoding"), "4")
    }

    // Spec: The same membership change with a conflicting attribute is not skipped.
    func testTheSameMembershipChangeWithAConflictingAttributeIsNotSkipped() throws {
        let base = try MergeFixture.base()
        let oursAdded = try MergeFixture.add(["App/Views/Bar.swift"], to: base)
        let theirsAdded = try MergeFixture.add(["App/Views/Bar.swift"], to: base, seed: 2)
        let reference = { (project: Project) in MembershipSnapshot(project).references["App/Views/Bar.swift"]?.id }
        let ours = try MergeFixture.attribute("fileEncoding", .string("4"), of: try XCTUnwrap(reference(oursAdded)), in: oursAdded)
        let theirs = try MergeFixture.attribute("fileEncoding", .string("10"), of: try XCTUnwrap(reference(theirsAdded)), in: theirsAdded)
        XCTAssertEqual(try MergeFixture.merge(ours: oursAdded, theirs: theirsAdded).units.map(\.classified.outcome), [.skipped],
                       "without the conflict the unit is skipped")
        let open = try MergeFixture.merge(ours: ours, theirs: theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertEqual(open.units.map(\.classified.outcome), [.decision])
        XCTAssertEqual(open.units.map(\.classified.choices), [[.ours, .theirsMembership]])
        XCTAssertEqual(open.units.first?.classified.residuals.filter(\.conflicting).map(\.kind), [.attribute("fileEncoding")])
        let report = try MergeFixture.merge(ours: ours, theirs: theirs,
                                            decisions: try MergeFixture.decide(open, units: { _ in "theirs-membership" }))
        let result = try merged(report)
        XCTAssertEqual(report.owed.map(\.kind), [.attribute("fileEncoding")])
        XCTAssertEqual(MembershipSnapshot(result).references["App/Views/Bar.swift"]?.id, reference(ours), "ours' objects")
    }

    // Spec: Build-file settings are a residual.
    func testTheirsMembershipOwesTheSettings() throws {
        let base = try MergeFixture.base()
        let added = try MergeFixture.add(["AppKit/Extra.h"], to: base, targets: ["AppKit"])
        let buildFile = try XCTUnwrap(MembershipSnapshot(added).references["AppKit/Extra.h"]?.rows.first?.buildFile)
        let theirs = try MergeFixture.attribute("settings", .dictionary([NewEntry("ATTRIBUTES", .array([.string("Public")]))]), of: buildFile, in: added)
        let open = try MergeFixture.merge(ours: base, theirs: theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertEqual(open.units.map(\.classified.choices), [[.ours, .theirsMembership]])
        let report = try MergeFixture.merge(ours: base, theirs: theirs, decisions: try MergeFixture.decide(open, units: { _ in "theirs-membership" }))
        let result = try merged(report)
        XCTAssertEqual(report.owed.map(\.path), ["AppKit/Extra.h"])
        XCTAssertEqual(report.owed.map(\.kind), [.settings(target: "AppKit")])
        let extra = try XCTUnwrap(MembershipSnapshot(result).references["AppKit/Extra.h"])
        XCTAssertEqual(extra.rows.map(\.masked), [MembershipSnapshot.MaskedRow(target: "AppKit", phase: .headers, filters: [], settings: nil)])
    }

    // Spec: A setting and a file merge cleanly.
    func testASettingAndAFileMergeCleanly() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: base)
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: try MergeFixture.setting("PRODUCT_BUNDLE_IDENTIFIER", "com.example.App2", in: a2, of: base),
                                          targets: ["App"])
        let result = try merged(try MergeFixture.merge(ours: ours, theirs: theirs))
        let leaves = PlistLeaves(result)
        XCTAssertEqual(leaves[["objects", a1.rawValue, "buildSettings", "SWIFT_VERSION"]], .string("5.10"))
        XCTAssertEqual(leaves[["objects", a2.rawValue, "buildSettings", "PRODUCT_BUNDLE_IDENTIFIER"]], .string("com.example.App2"))
        XCTAssertEqual(result.fileReferences(at: "App/Services/New.swift").count, 1)
    }

    // Spec: Conflicting setting values.
    func testConflictingSettingValues() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: base)
        let theirs = try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a1, of: base)
        let open = try MergeFixture.merge(ours: ours, theirs: theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertEqual(open.hunks.count, 1)
        XCTAssertEqual(open.hunks[0].analysed.choices, [.ours, .theirs])
        let report = try MergeFixture.merge(ours: ours, theirs: theirs, decisions: try MergeFixture.decide(open, hunks: { _ in "theirs" }))
        let result = try merged(report)
        XCTAssertEqual(PlistLeaves(result)[["objects", a1.rawValue, "buildSettings", "SWIFT_VERSION"]], .string("6.2"))
    }

    // Spec: Adjacent insertions.
    func testAdjacentInsertionsWithBoth() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("OTHER_SWIFT_FLAGS", "-DOURS", in: a1, of: base)
        let theirs = try MergeFixture.setting("OTHER_LDFLAGS", "-ObjC", in: a1, of: base)
        let open = try MergeFixture.merge(ours: ours, theirs: theirs)
        XCTAssertEqual(open.hunks.map(\.analysed.choices), [[.ours, .theirs, .both]])
        let result = try merged(try MergeFixture.merge(ours: ours, theirs: theirs, decisions: try MergeFixture.decide(open, hunks: { _ in "both" })))
        let leaves = PlistLeaves(result)
        XCTAssertEqual(leaves[["objects", a1.rawValue, "buildSettings", "OTHER_SWIFT_FLAGS"]], .string("-DOURS"))
        XCTAssertEqual(leaves[["objects", a1.rawValue, "buildSettings", "OTHER_LDFLAGS"]], .string("-ObjC"))
    }

    /// Issue #12: both sides change both ends of `knownRegions`, which gives
    /// two hunks governing the one leaf, beside an unrelated conflicting
    /// setting. Every combination of the two decisions is a valid resolution.
    static func sharedArraySides() throws -> (ours: Project, theirs: Project) {
        let base = try MergeFixture.base()
        let a1: ObjectID = "1000000000000000000000A1"
        let ours = try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: MergeFixture.knownRegions(["de", "en", "Base", "it"], of: base))
        let theirs = try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a1, of: MergeFixture.knownRegions(["fr", "en", "Base", "es"], of: base))
        return (ours, theirs)
    }

    // Spec: Two decided hunks govern one array.
    func testTwoDecidedHunksGoverningOneArrayAcceptEveryCombination() throws {
        let (ours, theirs) = try MergeEngineTests.sharedArraySides()
        let project: ObjectID = "EE0000000000000000000001"
        let open = try MergeFixture.merge(ours: ours, theirs: theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        let regions = open.hunks.filter { $0.analysed.governed.contains(["objects", project.rawValue, "knownRegions"]) }
        XCTAssertEqual(regions.map(\.analysed.number), [1, 2], "the head and the tail are two hunks")
        let (head, tail) = (regions[0].key, regions[1].key)
        let elements = ["ours": (head: "de", tail: "it"), "theirs": (head: "fr", tail: "es")]
        for headChoice in ["ours", "theirs"] {
            for tailChoice in ["ours", "theirs"] {
                let decisions = try MergeFixture.decide(open, hunks: { hunk in
                    hunk.key == head ? headChoice : hunk.key == tail ? tailChoice : "ours"
                })
                let result = try merged(try MergeFixture.merge(ours: ours, theirs: theirs, decisions: decisions))
                let expected: [PlistValue] = [elements[headChoice]!.head, "en", "Base", elements[tailChoice]!.tail].map { .string($0) }
                XCTAssertEqual(PlistLeaves(result)[["objects", project.rawValue, "knownRegions"]], .array(expected), "\(headChoice)/\(tailChoice)")
            }
        }
    }

    // Spec: Different insertions into one unordered array (issue #13).
    func testDifferentInsertionsIntoOneUnorderedArrayMergeWithBoth() throws {
        let base = try MergeFixture.base()
        let project: ObjectID = "EE0000000000000000000001"
        let ours = try MergeFixture.knownRegions(["de", "en", "Base"], of: base)
        let theirs = try MergeFixture.knownRegions(["fr", "en", "Base"], of: base)
        let open = try MergeFixture.merge(ours: ours, theirs: theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertEqual(open.hunks.map(\.analysed.governed), [[["objects", project.rawValue, "knownRegions"]]])
        XCTAssertEqual(open.hunks.map(\.analysed.choices), [[.ours, .theirs, .both]])
        let result = try merged(try MergeFixture.merge(ours: ours, theirs: theirs, decisions: try MergeFixture.decide(open, hunks: { _ in "both" })))
        XCTAssertEqual(PlistLeaves(result)[["objects", project.rawValue, "knownRegions"]], .array(["de", "fr", "en", "Base"].map { .string($0) }))
    }

    /// Issue #17: base holds one `XCRemoteSwiftPackageReference`, ours and
    /// theirs each add another after it. The list is one hunk, the two
    /// multi-line objects another.
    static func packageObjectSides() throws -> (base: Project, ours: Project, theirs: Project) {
        let plain = try MergeFixture.base()
        let zero = (id: "EF0000000000000000000001", url: "https://example.com/zero")
        return (try MergeFixture.packages([zero], of: plain),
                try MergeFixture.packages([zero, ("EF0000000000000000000002", "https://example.com/a")], of: plain),
                try MergeFixture.packages([zero, ("EF0000000000000000000003", "https://example.com/b")], of: plain))
    }

    // Spec: Two packages added on both sides keep their objects (issue #17).
    func testTwoPackageObjectsAddedAtOnePlaceMergeWithBoth() throws {
        let (base, ours, theirs) = try MergeEngineTests.packageObjectSides()
        let project: ObjectID = "EE0000000000000000000001"
        let open = try MergeFixture.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertEqual(open.hunks.map(\.analysed.choices), [[.ours, .theirs, .both], [.ours, .theirs, .both]])
        let result = try merged(try MergeFixture.merge(base: base, ours: ours, theirs: theirs,
                                                      decisions: try MergeFixture.decide(open, hunks: { _ in "both" })))
        let leaves = PlistLeaves(result)
        XCTAssertEqual(leaves[["objects", project.rawValue, "packageReferences"]],
                       .array(["EF0000000000000000000001", "EF0000000000000000000002", "EF0000000000000000000003"].map { .string($0) }))
        for (id, url) in [("EF0000000000000000000001", "zero"), ("EF0000000000000000000002", "a"), ("EF0000000000000000000003", "b")] {
            XCTAssertEqual(leaves[["objects", id, "isa"]], .string("XCRemoteSwiftPackageReference"))
            XCTAssertEqual(leaves[["objects", id, "repositoryURL"]], .string("https://example.com/\(url)"))
            XCTAssertEqual(leaves[["objects", id, "requirement", "minimumVersion"]], .string("1.0.0"))
        }
    }

    // MARK: Issue #24 — a reorder against an insertion

    /// The issue's repro: ours swaps base's two regions, theirs inserts a third.
    static func reorderedArraySides() throws -> (base: Project, ours: Project, theirs: Project) {
        let plain = try MergeFixture.base()
        return (try MergeFixture.knownRegions(["en", "Base"], of: plain),
                try MergeFixture.knownRegions(["Base", "en"], of: plain),
                try MergeFixture.knownRegions(["en", "Base", "fr"], of: plain))
    }

    // Spec: A reorder against an insertion keeps ours and theirs.
    func testAReorderAgainstAnInsertionIsNeverBoth() throws {
        let (base, ours, theirs) = try MergeEngineTests.reorderedArraySides()
        let open = try MergeFixture.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertTrue(open.result == nil, "nothing is written")
        let hunk = try XCTUnwrap(open.hunks.first { $0.analysed.governed.contains(["objects", "EE0000000000000000000001", "knownRegions"]) })
        XCTAssertEqual(hunk.analysed.choices, [.ours, .theirs])

        // Asking for the choice it does not offer is a usage error, not an exit 1 later.
        var asking = try XCTUnwrap(open.template)
        asking.hunks[hunk.key] = .some("both")
        let refused = try MergeFixture.merge(base: base, ours: ours, theirs: theirs, decisions: asking)
        XCTAssertEqual(refused.status, .unsupported)
        XCTAssertTrue(refused.error?.contains("both is not offered") == true, refused.error ?? "")

        // And ours or theirs resolves it. The line merge reads ours' move as a
        // deletion of the head line plus an insertion after `Base`, and only the
        // insertion point conflicts, so `theirs` keeps that deletion: `(Base, fr)`.
        for (choice, regions) in [("ours", ["Base", "en"]), ("theirs", ["Base", "fr"])] {
            let result = try merged(try MergeFixture.merge(base: base, ours: ours, theirs: theirs,
                                                          decisions: try MergeFixture.decide(open, hunks: { _ in choice })))
            XCTAssertEqual(PlistLeaves(result)[["objects", "EE0000000000000000000001", "knownRegions"]],
                           .array(regions.map { .string($0) }), choice)
        }
    }

    // Spec: An insertion against a removal still merges with both.
    func testAnInsertionAgainstARemovalStillMergesWithBoth() throws {
        let plain = try MergeFixture.base()
        let base = try MergeFixture.knownRegions(["en", "Base", "it"], of: plain)
        let ours = try MergeFixture.knownRegions(["de", "en", "Base"], of: plain)
        let theirs = try MergeFixture.knownRegions(["fr", "en", "Base", "it"], of: plain)
        let open = try MergeFixture.merge(base: base, ours: ours, theirs: theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertTrue(open.hunks.contains { $0.analysed.choices.contains(.both) }, "\(open.hunks.map(\.analysed.choices))")
        let result = try merged(try MergeFixture.merge(base: base, ours: ours, theirs: theirs,
                                                      decisions: try MergeFixture.decide(open, hunks: { _ in "both" })))
        XCTAssertEqual(PlistLeaves(result)[["objects", "EE0000000000000000000001", "knownRegions"]],
                       .array(["de", "fr", "en", "Base"].map { .string($0) }))
    }

    // MARK: Issue #21 — different links inserted into one Frameworks phase

    // Spec: Different links inserted into one Frameworks phase.
    func testDifferentFrameworkLinksMergeWithBoth() throws {
        let sides = try MergeFixture.frameworkLinks()
        let open = try MergeFixture.merge(ours: sides.ours, theirs: sides.theirs)
        XCTAssertEqual(open.status, .decisionsNeeded)
        XCTAssertEqual(open.units.count, 0, "a Frameworks link is not membership")
        XCTAssertEqual(open.hunks.count, 4, open.hunks.map { $0.analysed.governed.map(\.description).joined(separator: ", ") }.joined(separator: " / "))
        XCTAssertTrue(open.hunks.allSatisfy { $0.analysed.choices == [.ours, .theirs, .both] },
                      "\(open.hunks.map { "\($0.analysed.governed.map(\.description)): \($0.analysed.choices)" })")

        let result = try merged(try MergeFixture.merge(ours: sides.ours, theirs: sides.theirs,
                                                      decisions: try MergeFixture.decide(open, hunks: { _ in "both" })))
        let leaves = PlistLeaves(result)
        XCTAssertEqual(leaves[["objects", "CC0000000000000000000002", "files"]],
                       .array(["BB0000000000000000000080", "AB0000000000000000000011", "AC0000000000000000000011"].map { .string($0) }),
                       "base's entry, then ours' link, then theirs'")
        XCTAssertEqual(leaves[["objects", "AA0000000000000000000007", "children"]],
                       .array(["AA0000000000000000000160", "AB0000000000000000000010", "AC0000000000000000000010"].map { .string($0) }))
        for (buildFile, reference, name) in [("AB0000000000000000000011", "AB0000000000000000000010", "CoreHaptics"),
                                             ("AC0000000000000000000011", "AC0000000000000000000010", "GameController")]
            as [(ObjectID, String, String)] {
            XCTAssertEqual(leaves[["objects", buildFile.rawValue, "fileRef"]], .string(reference))
            XCTAssertEqual(leaves[["objects", reference, "name"]], .string("\(name).framework"))
            XCTAssertEqual(leaves[["objects", reference, "sourceTree"]], .string("SDKROOT"))
            XCTAssertEqual(result.phases(of: buildFile).map(\.id), ["CC0000000000000000000002"])
        }
    }

    /// The trap the issue reports: `both` for the objects and the references
    /// while the phase keeps `ours` leaves theirs' build file in no phase,
    /// which is what 1.1.2 could only ever produce.
    func testBothWithoutThePhaseStillFailsCheckA() throws {
        let sides = try MergeFixture.frameworkLinks()
        let open = try MergeFixture.merge(ours: sides.ours, theirs: sides.theirs)
        let phase = try XCTUnwrap(open.hunks.first { $0.analysed.governed.contains(["objects", "CC0000000000000000000002", "files"]) }).key
        let report = try MergeFixture.merge(ours: sides.ours, theirs: sides.theirs,
                                           decisions: try MergeFixture.decide(open, hunks: { $0.key == phase ? "ours" : "both" }))
        XCTAssertEqual(report.status, .failed)
        let failed = try XCTUnwrap(report.checks.first { !$0.passed })
        XCTAssertEqual(failed.check, .A)
        XCTAssertTrue(failed.problems.contains { $0.message.contains("AC0000000000000000000011") }, "\(failed.problems.map(\.message))")
    }

    /// The trap the issue reports: the list decided `both` while the objects
    /// are decided `ours` leaves theirs' entry naming nothing.
    func testTheListBothWithTheObjectsOursStillFailsCheckA() throws {
        let (base, ours, theirs) = try MergeEngineTests.packageObjectSides()
        let open = try MergeFixture.merge(base: base, ours: ours, theirs: theirs)
        let list = try XCTUnwrap(open.hunks.first).key
        let decisions = try MergeFixture.decide(open, hunks: { $0.key == list ? "both" : "ours" })
        let report = try MergeFixture.merge(base: base, ours: ours, theirs: theirs, decisions: decisions)
        XCTAssertEqual(report.status, .failed)
        let failed = try XCTUnwrap(report.checks.first { !$0.passed })
        XCTAssertEqual(failed.check, .A)
        XCTAssertTrue(failed.problems.contains { $0.message.contains("S2") || $0.message.contains("EF0000000000000000000003") },
                      "\(failed.problems.map(\.message))")
        XCTAssertNil(report.result)
    }

    // Spec: Both ends of one unordered array decided both.
    func testBothEndsOfOneUnorderedArrayDecidedBoth() throws {
        let (ours, theirs) = try MergeEngineTests.sharedArraySides()
        let project: ObjectID = "EE0000000000000000000001"
        let open = try MergeFixture.merge(ours: ours, theirs: theirs)
        let regions = open.hunks.filter { $0.analysed.governed.contains(["objects", project.rawValue, "knownRegions"]) }
        XCTAssertEqual(regions.map(\.analysed.choices), [[.ours, .theirs, .both], [.ours, .theirs, .both]])
        let (head, tail) = (regions[0].key, regions[1].key)
        let expected = [("both", ["de", "fr", "en", "Base", "it", "es"]), ("theirs", ["de", "fr", "en", "Base", "es"])]
        for (tailChoice, elements) in expected {
            let decisions = try MergeFixture.decide(open, hunks: { hunk in
                hunk.key == head ? "both" : hunk.key == tail ? tailChoice : "ours"
            })
            let result = try merged(try MergeFixture.merge(ours: ours, theirs: theirs, decisions: decisions))
            XCTAssertEqual(PlistLeaves(result)[["objects", project.rawValue, "knownRegions"]], .array(elements.map { .string($0) }), "both/\(tailChoice)")
        }
    }

    // Spec: A target only ours added.
    func testATargetOnlyOursAdded() throws {
        let base = try MergeFixture.base()
        let ours = try MergeEngineTests.addingTarget("Widget", to: base)
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"])
        let result = try merged(try MergeFixture.merge(ours: ours, theirs: theirs))
        XCTAssertTrue(result.targets.contains { $0.name == "Widget" })
        XCTAssertEqual(result.fileReferences(at: "App/Services/New.swift").count, 1)
    }

    // Spec: Theirs adds a target.
    func testTheirsAddsATarget() throws {
        let base = try MergeFixture.base()
        let report = try MergeFixture.merge(ours: base, theirs: try MergeEngineTests.addingTarget("Widget", to: base))
        XCTAssertEqual(report.status, .unsupported)
        XCTAssertTrue(report.result == nil)
        XCTAssertTrue(report.error?.contains("Widget") == true && report.error?.contains("theirs") == true, report.error ?? "")
    }

    func testTargetsRemovedAreUnsupported() throws {
        let base = try MergeFixture.base()
        var without = base
        try without.setAttribute("targets", of: "EE0000000000000000000001", to: .array(
            ["DD0000000000000000000001", "DD0000000000000000000002", "DD0000000000000000000003", "DD0000000000000000000004"].map { base.reference(to: ObjectID($0)) }))
        try without.deleteObject("DD0000000000000000000005")
        XCTAssertEqual(try MergeFixture.merge(ours: base, theirs: without).status, .unsupported)
        XCTAssertEqual(try MergeFixture.merge(ours: without, theirs: base).status, .unsupported)
    }

    // Spec: Input does not parse.
    func testAnInputThatDoesNotParse() throws {
        let bytes = try MergeFixture.baseBytes()
        let text = String(decoding: bytes, as: UTF8.self)
        let cut = try XCTUnwrap(text.range(of: "isa = PBXGroup;"))
        let truncated = Array(text[..<cut.upperBound].utf8)
        let report = MergeEngine().run(base: bytes, ours: bytes, theirs: truncated)
        XCTAssertEqual(report.status, .unsupported)
        let error = try XCTUnwrap(report.error)
        XCTAssertTrue(error.hasPrefix("theirs: "), error)
        XCTAssertNotNil(error.range(of: #"\d+:\d+: "#, options: .regularExpression), "line and column: \(error)")
    }

    // Spec: Nothing to change.
    func testOursEqualsTheirs() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.add(["App/Views/Bar.swift"], to: base)
        let report = try MergeFixture.merge(ours: ours, theirs: ours)
        XCTAssertTrue(report.nothingToMerge)
        XCTAssertEqual(try merged(report).serialize(), ours.serialize())
    }

    /// Review finding: the target check ran before the identical-sides
    /// shortcut, so two sides that made the same target change were refused.
    func testIdenticalSidesThatBothAddATargetHaveNothingToMerge() throws {
        let base = try MergeFixture.base()
        let both = try MergeEngineTests.addingTarget("Widget", to: base)
        XCTAssertEqual(try MergeFixture.merge(ours: base, theirs: both).status, .unsupported, "theirs alone adding it is still refused")
        let report = try MergeFixture.merge(ours: both, theirs: both)
        XCTAssertEqual(report.status, .merged, report.error ?? "")
        XCTAssertTrue(report.nothingToMerge)
        XCTAssertEqual(try merged(report).serialize(), both.serialize())
    }

    func testAnM4CollisionInAUnitIsUnsupported() throws {
        let base = try MergeFixture.base()
        var theirs = base
        try theirs.createObject("AB0000000000000000000040", isa: Kind.fileReference, attributes: [
            NewEntry("path", .string("Foo.swift")), NewEntry("sourceTree", .string("<group>")),
        ])
        try theirs.addChild("AB0000000000000000000040", to: "AA0000000000000000000003")
        let report = try MergeFixture.merge(ours: base, theirs: theirs)
        XCTAssertEqual(report.status, .unsupported, "\(report.units.map(\.classified.unit.paths))")
        XCTAssertTrue(report.error?.contains("App/Views/Foo.swift") == true, report.error ?? "")
    }

    /// A native target with no phases, listed in the project's targets.
    static func addingTarget(_ name: String, to project: Project) throws -> Project {
        var result = project
        let id: ObjectID = "DD0000000000000000000099"
        try result.createObject(id, isa: Kind.nativeTarget, attributes: [
            NewEntry("buildPhases", .array([])), NewEntry("name", .string(name)), NewEntry("productName", .string(name)),
        ])
        let targets = (result.rootObject?.ids("targets") ?? []) + [id]
        try result.setAttribute("targets", of: result.rootObjectID, to: .array(targets.map { result.reference(to: $0) }))
        return result
    }
}
