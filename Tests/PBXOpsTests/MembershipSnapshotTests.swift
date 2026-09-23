import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 3.1–3.2: what a version's membership is (design D2).
final class MembershipSnapshotTests: XCTestCase {
    func testManagedReferencesByPathWithSpellingParentsAndAttributes() throws {
        let snapshot = MembershipSnapshot(try MergeFixture.base())
        let foo = try XCTUnwrap(snapshot.references["App/Views/Foo.swift"])
        XCTAssertEqual(foo.id, "AA0000000000000000000120")
        XCTAssertEqual(foo.path, "Foo.swift")
        XCTAssertNil(foo.name)
        XCTAssertEqual(foo.sourceTree, "<group>")
        XCTAssertEqual(foo.parents, ["AA0000000000000000000003"])
        XCTAssertEqual(foo.groupPath, "App/Views")
        XCTAssertEqual(foo.attributes, ["lastKnownFileType": .string("sourcecode.swift")])

        let tests = try XCTUnwrap(snapshot.references["AppTests/Views/FooTests.swift"])
        XCTAssertEqual(tests.path, "AppTests/Views/FooTests.swift")
        XCTAssertEqual(tests.name, "FooTests.swift")
        XCTAssertEqual(tests.sourceTree, "SOURCE_ROOT")
        XCTAssertEqual(tests.groupPath, "AppTests", "the name-only Views group resolves to its parent's directory")

        let entitlements = try XCTUnwrap(snapshot.references["App/App.entitlements"], "a reference no target builds is managed")
        XCTAssertEqual(entitlements.rows, [])
        XCTAssertEqual(snapshot.collisions, [])
    }

    func testRowsForSourcesResourcesAndHeaders() throws {
        let snapshot = MembershipSnapshot(try MergeFixture.base())
        let cache = try XCTUnwrap(snapshot.references["App/Services/Cache.swift"])
        XCTAssertEqual(cache.rows.map(\.masked), [
            MembershipSnapshot.MaskedRow(target: "App", phase: .sources, filters: [], settings: nil),
            MembershipSnapshot.MaskedRow(target: "AppExtension", phase: .sources, filters: [], settings: nil),
        ])
        XCTAssertEqual(cache.rows.map(\.buildFile), ["BB0000000000000000000112", "BB0000000000000000000113"])
        XCTAssertEqual(snapshot.references["App/Filtered/F1.swift"]?.rows.map(\.filters), [["ios"]], "the singular key")
        XCTAssertEqual(snapshot.references["App/Shared.swift"]?.rows.map(\.filters), [[], ["ios", "maccatalyst"]], "the plural key")
        let header = try XCTUnwrap(snapshot.references["AppKit/AppKit.h"]?.rows.first)
        XCTAssertEqual(header.target, "AppKit")
        XCTAssertEqual(header.phase, .headers)
        XCTAssertEqual(header.settings, .dictionary([.init(key: "ATTRIBUTES", value: .array([.string("Public")]))]))
        XCTAssertEqual(snapshot.references["App/Resources/Assets.xcassets"]?.rows.map(\.masked),
                       [MembershipSnapshot.MaskedRow(target: "App", phase: .resources, filters: [], settings: nil)])
    }

    func testWhatIsNotManaged() throws {
        var project = try MergeFixture.base()
        // A reference inside the synchronized folder, spelled against the source root.
        try project.createObject("AB0000000000000000000001", isa: Kind.fileReference, attributes: [
            NewEntry("path", .string("App/Generated/Made.swift")), NewEntry("sourceTree", .string("SOURCE_ROOT")),
        ])
        try project.addChild("AB0000000000000000000001", to: "AA0000000000000000000002")
        let snapshot = MembershipSnapshot(project)
        let paths = Set(snapshot.references.keys)
        XCTAssertFalse(paths.contains("System/Library/Frameworks/Foundation.framework"), "SDKROOT")
        XCTAssertFalse(paths.contains { $0.hasSuffix(".app") || $0.hasSuffix(".appex") || $0.hasSuffix(".xctest") }, "products: \(paths.sorted())")
        XCTAssertFalse(paths.contains("App/Resources/en.lproj/Localizable.strings"), "a variant group's child")
        XCTAssertFalse(paths.contains { $0.hasPrefix("App/Generated/") }, "the synchronized folder")
        XCTAssertEqual(paths.count, 32, "\(paths.sorted())")
    }

    func testAFrameworksRowMakesAReferenceUnmanaged() throws {
        var project = try MergeFixture.base()
        try project.createObject("BB0000000000000000000999", isa: Kind.buildFile, attributes: [NewEntry("fileRef", .string("AA0000000000000000000110"))])
        try project.addPhaseEntry("BB0000000000000000000999", to: "CC0000000000000000000002")
        XCTAssertNil(MembershipSnapshot(project).references["App/AppMain.swift"])
    }

    func testTwoManagedReferencesAtOnePathAreACollision() throws {
        let project = try loadProject("add/m4-collision.pbxproj")
        XCTAssertEqual(MembershipSnapshot(project).collisions, ["App/Foo.swift"])
    }

    func testMaskedStatesAreEqualAcrossVersionsThatDifferOnlyInIDs() throws {
        let base = try MergeFixture.base()
        let one = MembershipSnapshot(try MergeFixture.add(["App/Views/Bar.swift"], to: base, seed: 1))
        let two = MembershipSnapshot(try MergeFixture.add(["App/Views/Bar.swift"], to: base, seed: 2))
        let first = try XCTUnwrap(one.references["App/Views/Bar.swift"])
        let second = try XCTUnwrap(two.references["App/Views/Bar.swift"])
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.rows.map(\.buildFile), second.rows.map(\.buildFile))
        XCTAssertEqual(first.masked, second.masked)
        XCTAssertEqual(one.masked(at: "App/Views/Bar.swift"), two.masked(at: "App/Views/Bar.swift"))
        XCTAssertNil(MembershipSnapshot(base).masked(at: "App/Views/Bar.swift"))
        XCTAssertNotEqual(first.masked, MembershipSnapshot(try MergeFixture.add(["App/Views/Bar.swift"], to: base, platforms: ["ios"])).masked(at: "App/Views/Bar.swift"))
    }
}
