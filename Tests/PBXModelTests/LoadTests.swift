import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// Tasks 2.1 and 2.3: loading, the object table, exact-ID lookup, pass-through.
final class LoadTests: XCTestCase {
    // Spec: Exact-ID lookup — One ID is a prefix of another. Motivation table, row 1.
    func testLookupIsByCompleteID() throws {
        let project = try loadProject("model/broken.pbxproj")
        let group = try XCTUnwrap(project.object("TVOSTEST00020"))
        XCTAssertEqual(group.isa, "PBXGroup")
        XCTAssertEqual(group.id, "TVOSTEST00020")
        let reference = try XCTUnwrap(project.object("TVOSTEST0002"))
        XCTAssertEqual(reference.isa, "PBXFileReference")
        XCTAssertNotNil(project.group("TVOSTEST00020"))
        XCTAssertNil(project.group("TVOSTEST0002"))
        XCTAssertNotNil(project.fileReference("TVOSTEST0002"))
        XCTAssertNil(project.fileReference("TVOSTEST00020"))
    }

    // Spec: Exact-ID lookup — Unknown ID (prefix, suffix and case variants do not match).
    func testUnknownIDDoesNotResolve() throws {
        let project = try loadProject("model/broken.pbxproj")
        for id: ObjectID in ["TVOSTEST000", "TVOSTEST00020X", "VOSTEST0002", "tvostest0002", ""] {
            XCTAssertNil(project.object(id), "\(id) must not resolve")
            XCTAssertFalse(project.contains(id))
        }
        XCTAssertTrue(project.contains("TVOSTEST0002"))
    }

    // Spec: IDs are opaque — Synthetic IDs.
    func testSyntheticIDsLoadAndAreReferencedByOtherObjects() throws {
        let project = try loadProject("model/broken.pbxproj")
        let group = try XCTUnwrap(project.group("SPLASH00000001"))
        XCTAssertEqual(group.path, "SlowTests")
        XCTAssertEqual(group.children, ["5L0WTSTSP000000000000SRC"])
        let reference = try XCTUnwrap(project.fileReference("5L0WTSTSP000000000000SRC"))
        XCTAssertEqual(reference.path, "Splash.swift")
        XCTAssertEqual(project.mainGroup?.children, ["TVOSTEST00020", "SPLASH00000001", "TVOSTEST00020"])
    }

    // Spec: Broken projects load — Dangling file reference.
    func testDanglingFileReferenceIsObservable() throws {
        let project = try loadProject("model/broken.pbxproj")
        let buildFile = try XCTUnwrap(project.buildFile("BB0000000000000000000010"))
        XCTAssertEqual(buildFile.fileRef, "AA0000000000000000000999")
        XCTAssertNil(project.object("AA0000000000000000000999"))
        XCTAssertNil(project.fileReference(of: buildFile))
        // The other build file resolves.
        let other = try XCTUnwrap(project.buildFile("BB0000000000000000000020"))
        XCTAssertEqual(project.fileReference(of: other)?.path, "Foo.swift")
    }

    // Spec: Broken projects load — No root object.
    func testMissingRootObjectFailsToLoad() throws {
        let source = "{ objects = { A1 = {isa = PBXProject; }; }; rootObject = ZZ; }"
        XCTAssertThrowsError(try Project.load(Array(source.utf8))) { error in
            XCTAssertEqual(error as? LoadError, .rootObjectNotFound("ZZ"))
            XCTAssertTrue("\(error)".contains("root object"), "\(error)")
        }
        XCTAssertThrowsError(try Project.load(Array("{ objects = { }; }".utf8))) { error in
            XCTAssertEqual(error as? LoadError, .missingRootObject)
        }
        XCTAssertThrowsError(try Project.load(Array("{ rootObject = A1; }".utf8))) { error in
            XCTAssertEqual(error as? LoadError, .missingObjects)
        }
        XCTAssertThrowsError(try Project.load(Array("(a, b)".utf8))) { error in
            XCTAssertEqual(error as? LoadError, .rootIsNotADictionary)
        }
        XCTAssertThrowsError(try Project.load(Array("{ objects = ".utf8))) { error in
            XCTAssertNotNil(error as? ParseError)
        }
    }

    func testObjectsAreEnumeratedInSourceOrderWithTheirKinds() throws {
        let project = try loadProject("model/broken.pbxproj")
        XCTAssertEqual(project.objects.count, 16)
        XCTAssertEqual(project.objects.first?.id, "BB0000000000000000000010")
        XCTAssertEqual(project.rootObject?.isa, "PBXProject")
        XCTAssertEqual(project.objects.filter { $0.isa == "PBXSomethingNew" }.map(\.id), ["EE0000000000000000000002"])
        XCTAssertEqual(project.fileReferences.map(\.id), ["5L0WTSTSP000000000000SRC", "AA0000000000000000000100", "TVOSTEST0002"])
        XCTAssertEqual(project.groups.map(\.id), ["AA0000000000000000000001", "SPLASH00000001", "TVOSTEST00020"])
        XCTAssertEqual(project.buildFiles.count, 2)
        XCTAssertEqual(project.buildPhases.map(\.id), ["CC0000000000000000000001"])
        XCTAssertEqual(project.targets.map(\.name), ["App"])
        XCTAssertEqual(project.duplicateIDs, [])
    }

    func testDuplicateObjectIDsAreObservableAndTheFirstWins() throws {
        let source = "{ objects = { P1 = {isa = PBXProject; }; A1 = {isa = PBXGroup; path = first; }; A1 = {isa = PBXGroup; path = second; }; }; rootObject = P1; }"
        let project = try Project.load(Array(source.utf8))
        XCTAssertEqual(project.duplicateIDs, ["A1"])
        XCTAssertEqual(project.group("A1")?.path, "first")
        XCTAssertEqual(project.objects.count, 3, "every entry is enumerated, duplicates included")
    }

    func testTypedViewsReadTheirAttributes() throws {
        let project = try loadProject("model/app.pbxproj")
        let reference = try XCTUnwrap(project.fileReference("AA0000000000000000000140"))
        XCTAssertEqual(reference.name, "FooTests.swift")
        XCTAssertEqual(reference.path, "AppTests/Views/FooTests.swift")
        XCTAssertEqual(reference.sourceTree, "SOURCE_ROOT")
        XCTAssertEqual(reference.lastKnownFileType, "sourcecode.swift")
        let buildFile = try XCTUnwrap(project.buildFile("BB0000000000000000000040"))
        XCTAssertEqual(buildFile.platformFilters, ["ios", "maccatalyst"])
        XCTAssertNil(project.buildFile("BB0000000000000000000030")?.platformFilters)
        let phase = try XCTUnwrap(project.buildPhase("CC0000000000000000000001"))
        XCTAssertEqual(phase.isa, "PBXSourcesBuildPhase")
        XCTAssertEqual(phase.files.count, 3)
        XCTAssertEqual(phase.displayName, "Sources")
        let target = try XCTUnwrap(project.target("DD0000000000000000000001"))
        XCTAssertEqual(target.name, "App")
        XCTAssertEqual(target.buildPhases, ["CC0000000000000000000001", "CC0000000000000000000002", "CC0000000000000000000003"])
        XCTAssertEqual(target.productReference, "AA0000000000000000000170")
        XCTAssertEqual(target.fileSystemSynchronizedGroups, ["AA0000000000000000000301"])
        let variant = try XCTUnwrap(project.group("AA0000000000000000000201"))
        XCTAssertEqual(variant.isa, "PBXVariantGroup")
        XCTAssertEqual(variant.name, "Localizable.strings")
        XCTAssertNil(variant.path)
        let synchronized = try XCTUnwrap(project.synchronizedRootGroup("AA0000000000000000000301"))
        XCTAssertEqual(synchronized.path, "Generated")
        XCTAssertEqual(project.mainGroup?.id, "AA0000000000000000000001")
        XCTAssertEqual(project.nativeTargets.map(\.name), ["App", "AppExtension", "AppTests"])
        XCTAssertEqual(project.variantGroups.map(\.id), ["AA0000000000000000000201"])
        XCTAssertEqual(project.synchronizedRootGroups.map(\.id), ["AA0000000000000000000301"])
    }

    // Spec: Unknown kinds pass through — Newer project format.
    func testUnknownKindsPassThroughUntouched() throws {
        let source = try Fixtures.text("model/broken.pbxproj")
        var project = try Project.load(Array(source.utf8))
        XCTAssertEqual(project.objectVersion, "999")
        let unknown = try XCTUnwrap(project.object("EE0000000000000000000002"))
        XCTAssertEqual(unknown.isa, "PBXSomethingNew")
        XCTAssertEqual(unknown.attributes?.keys, ["isa", "futureAttribute", "target"])
        try project.addChild("AA0000000000000000000100", to: "AA0000000000000000000001")
        let output = serialized(project)
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.added, ["\t\t\t\tAA0000000000000000000100 /* Foo.swift */,\n"])
    }
}
