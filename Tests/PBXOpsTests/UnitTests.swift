import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 3.3–3.4: linking the paths theirs changed into units,
/// and the units' keys (design D3).
final class UnitTests: XCTestCase {
    private func units(ours: Project? = nil, theirs: Project, base: Project? = nil) throws -> [MergeUnit] {
        let base = try base ?? MergeFixture.base()
        return MergeUnit.discover(base: MembershipSnapshot(base), ours: MembershipSnapshot(ours ?? base), theirs: MembershipSnapshot(theirs))
    }

    // Spec: Rename is one unit.
    func testARenameIsOneUnitOfTwoPaths() throws {
        let theirs = try MergeFixture.move("App/Views/Foo.swift", to: "App/Features/Foo.swift", in: try MergeFixture.base())
        let found = try units(theirs: theirs)
        XCTAssertEqual(found.map(\.paths), [["App/Features/Foo.swift", "App/Views/Foo.swift"]])
    }

    func testOursRenameOfAPathTheirsRemovesJoinsTheUnit() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.move("App/Filtered/F1.swift", to: "App/Views/F1.swift", in: base)
        let theirs = try MergeFixture.remove(["App/Filtered/F1.swift"], from: base)
        XCTAssertEqual(try units(ours: ours, theirs: theirs).map(\.paths), [["App/Filtered/F1.swift", "App/Views/F1.swift"]])
    }

    // Spec: A file no target builds.
    func testAReferenceWithNoBuildFileIsAUnit() throws {
        let theirs = try MergeFixture.add(["App/Notes.md"], to: try MergeFixture.base())
        XCTAssertEqual(try units(theirs: theirs).map(\.paths), [["App/Notes.md"]])
    }

    // Spec: Unmanaged changes are not units.
    func testAnSDKReferenceAndItsFrameworksBuildFileAreNoUnit() throws {
        var theirs = try MergeFixture.base()
        try theirs.createObject("AB0000000000000000000010", isa: Kind.fileReference, attributes: [
            NewEntry("lastKnownFileType", .string("wrapper.framework")), NewEntry("name", .string("Combine.framework")),
            NewEntry("path", .string("System/Library/Frameworks/Combine.framework")), NewEntry("sourceTree", .string("SDKROOT")),
        ])
        try theirs.addChild("AB0000000000000000000010", to: "AA0000000000000000000007")
        try theirs.createObject("AB0000000000000000000011", isa: Kind.buildFile, attributes: [NewEntry("fileRef", theirs.reference(to: "AB0000000000000000000010"))])
        try theirs.addPhaseEntry("AB0000000000000000000011", to: "CC0000000000000000000002")
        XCTAssertEqual(try units(theirs: theirs), [])
    }

    func testReCreatedIDsWithAnEqualMaskedStateAreAUnit() throws {
        let base = try MergeFixture.base()
        let removed = try MergeFixture.remove(["App/Views/Foo.swift"], from: base)
        let theirs = try MergeFixture.add(["App/Views/Foo.swift"], to: removed, targets: ["App"])
        XCTAssertEqual(MembershipSnapshot(theirs).masked(at: "App/Views/Foo.swift"), MembershipSnapshot(base).masked(at: "App/Views/Foo.swift"))
        XCTAssertNotEqual(MembershipSnapshot(theirs).references["App/Views/Foo.swift"]?.id, "AA0000000000000000000120")
        XCTAssertEqual(try units(theirs: theirs).map(\.paths), [["App/Views/Foo.swift"]])
    }

    func testUnitsAreOrderedBySmallestPath() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.add(["App/Views/Bar.swift", "App/Services/New.swift"], to: base, targets: ["App"])
        XCTAssertEqual(try units(theirs: theirs).map(\.paths), [["App/Services/New.swift"], ["App/Views/Bar.swift"]])
    }

    func testKeysAreStableAndFollowTheState() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"])
        let first = try units(theirs: theirs)
        let second = try units(theirs: try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"], seed: 9))
        XCTAssertEqual(first.map(\.key), second.map(\.key), "IDs do not enter the key")
        XCTAssertTrue(first[0].key.hasPrefix("u"))
        XCTAssertEqual(first[0].key.count, 13)
        let filtered = try units(theirs: try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"], platforms: ["ios"]))
        XCTAssertNotEqual(filtered.map(\.key), first.map(\.key), "theirs' state changed")
        let oursToo = try units(ours: try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["AppExtension"]), theirs: theirs)
        XCTAssertNotEqual(oursToo.map(\.key), first.map(\.key), "ours' state changed")
    }
}
