import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// Task 5.2: objects are placed where Xcode places them (design D5).
final class SectionTests: XCTestCase {
    private func newBuildFile(_ project: inout Project, _ id: ObjectID) throws {
        try project.createObject(
            id, isa: "PBXBuildFile",
            attributes: [NewEntry("fileRef", project.reference(to: "AA0000000000000000000110"))])
    }

    // Spec: Primitive mutations place content where Xcode does — New build file in a sorted section.
    func testNewObjectInASortedSectionGoesBetweenItsNeighbours() throws {
        let source = try Fixtures.text("model/app.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try newBuildFile(&project, "BB0000000000000000000025")
        let output = serialized(project)
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.added, [
            "\t\tBB0000000000000000000025 = {isa = PBXBuildFile; fileRef = AA0000000000000000000110 /* AppMain.swift */; };\n"
        ])
        XCTAssertTrue(output.contains(
            "/* Foo.swift */; };\n\t\tBB0000000000000000000025 = {isa = PBXBuildFile; fileRef = AA0000000000000000000110 /* AppMain.swift */; };\n\t\tBB0000000000000000000030 /*"))
        XCTAssertEqual(project.buildFile("BB0000000000000000000025")?.fileRef, "AA0000000000000000000110")
    }

    func testNewObjectSortingFirstInheritsTheBeginMarker() throws {
        let source = try Fixtures.text("model/app.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try newBuildFile(&project, "BB0000000000000000000005")
        let output = serialized(project)
        XCTAssertEqual(lineDiff(source, output).added.count, 1)
        XCTAssertTrue(output.contains("/* Begin PBXBuildFile section */\n\t\tBB0000000000000000000005 = {isa = PBXBuildFile;"))
        XCTAssertTrue(output.contains("/* AppMain.swift */; };\n\t\tBB0000000000000000000010 /* AppMain.swift in Sources */"))
    }

    func testNewObjectSortingLastGoesBeforeTheEndMarker() throws {
        let source = try Fixtures.text("model/app.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try newBuildFile(&project, "BB0000000000000000000095")
        let output = serialized(project)
        XCTAssertEqual(lineDiff(source, output).added.count, 1)
        XCTAssertTrue(output.contains("/* Localizable.strings */; };\n\t\tBB0000000000000000000095 = {isa = PBXBuildFile; fileRef = AA0000000000000000000110 /* AppMain.swift */; };\n/* End PBXBuildFile section */"))
    }

    func testNewObjectInAnUnsortedSectionGoesLast() throws {
        let source = "{\n\tobjects = {\n\n/* Begin PBXGroup section */\n\t\tG2 /* b */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t\tpath = b;\n\t\t};\n\t\tG1 /* a */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t\tpath = a;\n\t\t};\n/* End PBXGroup section */\n\n/* Begin PBXProject section */\n\t\tP1 /* Project object */ = {\n\t\t\tisa = PBXProject;\n\t\t\tmainGroup = G1 /* a */;\n\t\t};\n/* End PBXProject section */\n\t};\n\trootObject = P1 /* Project object */;\n}\n"
        var project = try Project.load(Array(source.utf8))
        try project.createObject("G0", isa: "PBXGroup", attributes: [
            NewEntry("children", .array([])), NewEntry("path", .string("c")), NewEntry("sourceTree", .string("<group>")),
        ])
        let output = serialized(project)
        XCTAssertEqual(
            output,
            replacing(source, "\t\t\tpath = a;\n\t\t};\n/* End PBXGroup section */", with: "\t\t\tpath = a;\n\t\t};\n\t\tG0 /* c */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t\tpath = c;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n/* End PBXGroup section */"))
    }

    // Spec: Primitive mutations place content where Xcode does — First object of a kind.
    func testFirstObjectOfAKindGetsANewSectionInAlphabeticalPosition() throws {
        let source = try Fixtures.text("model/broken.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try project.createObject("VV0000000000000000000001", isa: "PBXVariantGroup", attributes: [
            NewEntry("sourceTree", .string("<group>")),
            NewEntry("name", .string("Localizable.strings")),
            NewEntry("children", .array([project.reference(to: "AA0000000000000000000100")])),
        ])
        let output = serialized(project)
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.added.count, 11)
        XCTAssertTrue(output.contains(
            "/* End PBXSourcesBuildPhase section */\n\n/* Begin PBXVariantGroup section */\n"
            + "\t\tVV0000000000000000000001 /* Localizable.strings */ = {\n\t\t\tisa = PBXVariantGroup;\n\t\t\tchildren = (\n"
            + "\t\t\t\tAA0000000000000000000100 /* Foo.swift */,\n\t\t\t);\n\t\t\tname = Localizable.strings;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"
            + "/* End PBXVariantGroup section */\n\n/* Begin XCBuildConfiguration section */\n\t\t1000000000000000000000A1"), output)
        XCTAssertEqual(project.group("VV0000000000000000000001")?.children, ["AA0000000000000000000100"])
        XCTAssertEqual(project.parents(of: "AA0000000000000000000100").map(\.id), ["VV0000000000000000000001"])
    }

    func testFirstSectionOfTheFile() throws {
        let source = try Fixtures.text("model/app.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try project.createObject("A00000000000000000000001", isa: "PBXAggregateTarget", attributes: [
            NewEntry("name", .string("All")), NewEntry("buildPhases", .array([])),
        ])
        let output = serialized(project)
        XCTAssertEqual(lineDiff(source, output).removed, [])
        XCTAssertTrue(output.contains(
            "\tobjects = {\n\n/* Begin PBXAggregateTarget section */\n\t\tA00000000000000000000001 /* All */ = {\n\t\t\tisa = PBXAggregateTarget;\n"
            + "\t\t\tbuildPhases = (\n\t\t\t);\n\t\t\tname = All;\n\t\t};\n/* End PBXAggregateTarget section */\n\n/* Begin PBXBuildFile section */\n\t\tBB0000000000000000000010"), output)
    }

    func testLastSectionOfTheFileIsSingleLineForASingleLineKind() throws {
        let source = try Fixtures.text("model/broken.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try project.createObject("SS0000000000000000000001", isa: "PBXFileSystemSynchronizedRootGroup", attributes: [
            NewEntry("path", .string("Generated")), NewEntry("sourceTree", .string("<group>")),
        ])
        let output = serialized(project)
        XCTAssertEqual(lineDiff(source, output).removed, [])
        XCTAssertTrue(output.contains(
            "/* End PBXFileReference section */\n\n/* Begin PBXFileSystemSynchronizedRootGroup section */\n"
            + "\t\tSS0000000000000000000001 /* Generated */ = {isa = PBXFileSystemSynchronizedRootGroup; path = Generated; sourceTree = \"<group>\"; };\n"
            + "/* End PBXFileSystemSynchronizedRootGroup section */\n\n/* Begin PBXGroup section */"), output)
        // And a kind sorting after every existing section.
        try project.createObject("XV000000000000000000001", isa: "XCVersionGroup", attributes: [
            NewEntry("path", .string("Model.xcdatamodeld")), NewEntry("sourceTree", .string("<group>")), NewEntry("children", .array([])),
        ])
        let last = serialized(project)
        XCTAssertTrue(last.contains(
            "/* End XCConfigurationList section */\n\n/* Begin XCVersionGroup section */\n\t\tXV000000000000000000001 /* Model.xcdatamodeld */ = {\n"
            + "\t\t\tisa = XCVersionGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t\tpath = Model.xcdatamodeld;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"
            + "/* End XCVersionGroup section */\n\t};\n\trootObject"), last)
    }

    func testFileWithoutSectionMarkersAppendsToObjects() throws {
        let source = "{\n\tobjects = {\n\t\tP1 = {\n\t\t\tisa = PBXProject;\n\t\t};\n\t\tF1 = {isa = PBXFileReference; path = a.c; };\n\t};\n\trootObject = P1;\n}\n"
        var project = try Project.load(Array(source.utf8))
        try project.createObject("B1", isa: "PBXBuildFile", attributes: [NewEntry("fileRef", project.reference(to: "F1"))])
        try project.createObject("G1", isa: "PBXGroup", attributes: [NewEntry("children", .array([project.reference(to: "F1")]))])
        let output = serialized(project)
        XCTAssertEqual(
            output,
            replacing(source, "path = a.c; };\n", with: "path = a.c; };\n\t\tB1 = {isa = PBXBuildFile; fileRef = F1 /* a.c */; };\n\t\tG1 = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\tF1 /* a.c */,\n\t\t\t);\n\t\t};\n"))
        XCTAssertFalse(output.contains("section"))
    }

    func testEmptyObjectsDictionary() throws {
        var project = try Project.load(Array("{ objects = { P1 = {isa = PBXProject; }; }; rootObject = P1; }".utf8))
        try project.createObject("F1", isa: "PBXFileReference", attributes: [NewEntry("path", .string("a.c"))])
        XCTAssertEqual(serialized(project), "{ objects = { P1 = {isa = PBXProject; }; F1 /* a.c */ = {isa = PBXFileReference; path = a.c; }; }; rootObject = P1; }")
    }

    func testCreatingAnExistingIDIsRefused() throws {
        var project = try loadProject("model/app.pbxproj")
        XCTAssertThrowsError(try newBuildFile(&project, "BB0000000000000000000010")) { error in
            XCTAssertEqual(error as? MutationError, .objectExists("BB0000000000000000000010"))
        }
        XCTAssertEqual(project.serialize(), try Fixtures.load("model/app.pbxproj"))
    }

    // Spec: Primitive mutations place content where Xcode does — Last object of a kind.
    func testDeletingTheLastObjectOfAKindRemovesItsSection() throws {
        let source = try Fixtures.text("model/app.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try project.deleteObject("AA0000000000000000000201")
        let output = serialized(project)
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.added, [])
        XCTAssertEqual(diff.removed.count, 11, "the object's eight lines, both markers and one blank line: \(diff.removed)")
        XCTAssertTrue(output.contains("/* End PBXSourcesBuildPhase section */\n\n/* Begin XCBuildConfiguration section */\n"))
        XCTAssertFalse(output.contains("PBXVariantGroup"))
        XCTAssertNil(project.object("AA0000000000000000000201"))
    }

    func testDeletingTheLastObjectOfTheFirstAndLastSections() throws {
        let source = "{\n\tobjects = {\n\n/* Begin PBXBuildFile section */\n\t\tB1 = {isa = PBXBuildFile; };\n/* End PBXBuildFile section */\n\n/* Begin PBXProject section */\n\t\tP1 = {isa = PBXProject; };\n/* End PBXProject section */\n\n/* Begin XCVersionGroup section */\n\t\tV1 = {isa = XCVersionGroup; };\n/* End XCVersionGroup section */\n\t};\n\trootObject = P1;\n}\n"
        var project = try Project.load(Array(source.utf8))
        try project.deleteObject("B1")
        XCTAssertEqual(
            serialized(project),
            "{\n\tobjects = {\n\n/* Begin PBXProject section */\n\t\tP1 = {isa = PBXProject; };\n/* End PBXProject section */\n\n/* Begin XCVersionGroup section */\n\t\tV1 = {isa = XCVersionGroup; };\n/* End XCVersionGroup section */\n\t};\n\trootObject = P1;\n}\n")
        try project.deleteObject("V1")
        XCTAssertEqual(
            serialized(project),
            "{\n\tobjects = {\n\n/* Begin PBXProject section */\n\t\tP1 = {isa = PBXProject; };\n/* End PBXProject section */\n\t};\n\trootObject = P1;\n}\n")
        try project.deleteObject("P1")
        XCTAssertEqual(serialized(project), "{\n\tobjects = {\n\t};\n\trootObject = P1;\n}\n")
    }

    /// The section map is patched after every create and delete rather than
    /// rebuilt; it must always equal the map computed from the tree.
    func testPatchedSectionMapEqualsAFreshOne() throws {
        var project = try loadProject("model/app.pbxproj")
        func check(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(project.sections, SectionMap(project.tree), step, file: file, line: line)
            XCTAssertEqual(project.objects.map(\.id), project.objects.map { $0.id }.filter { project.contains($0) }, step, file: file, line: line)
        }
        try newBuildFile(&project, "BB0000000000000000000005"); check("first of section")
        try newBuildFile(&project, "BB0000000000000000000095"); check("last of section")
        try newBuildFile(&project, "BB0000000000000000000045"); check("middle of section")
        try project.createObject("A00000000000000000000001", isa: "PBXAggregateTarget", attributes: []); check("new first section")
        try project.createObject("XV000000000000000000001", isa: "XCVersionGroup", attributes: []); check("new last section")
        try project.createObject("PP000000000000000000001", isa: "PBXTargetDependency", attributes: []); check("new middle section")
        try project.createObject("PP000000000000000000002", isa: "PBXTargetDependency", attributes: []); check("second in new section")
        try project.deleteObject("PP000000000000000000001"); check("delete one of two")
        try project.deleteObject("PP000000000000000000002"); check("delete last of kind, middle")
        try project.deleteObject("A00000000000000000000001"); check("delete last of kind, first section")
        try project.deleteObject("XV000000000000000000001"); check("delete last of kind, last section")
        try project.deleteObject("BB0000000000000000000005"); check("delete first of section")
        try project.deleteObject("AA0000000000000000000201"); check("delete only variant group")
        try project.addChild("AA0000000000000000000120", to: "AA0000000000000000000002"); check("value mutation")
        XCTAssertNil(project.object("PP000000000000000000001"))
        XCTAssertNotNil(project.object("BB0000000000000000000045"))
        XCTAssertNotNil(project.object("DD0000000000000000000003"), "an entry shifted by insertions and deletions is still found")
        assertPlutilLints(project.serialize())
    }

    /// The parent and path indexes are patched for new leaves and for orphans
    /// gaining a parent; they must always equal the indexes built from scratch.
    func testPatchedIndexesEqualFreshOnes() throws {
        var project = try loadProject("model/broken.pbxproj")
        func check(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
            let parents = ParentIndex(project)
            XCTAssertEqual(project.parentIndex, parents, step, file: file, line: line)
            XCTAssertEqual(project.pathIndex, PathIndex(project, parents: parents), step, file: file, line: line)
        }
        _ = project.fileReferences(at: "Foo.swift")  // build the indexes so that they are patched, not rebuilt
        try project.createObject("AA0000000000000000000200", isa: "PBXFileReference", attributes: [
            NewEntry("path", .string("Foo.swift")), NewEntry("sourceTree", .string("<group>")),
        ])
        check("a second reference to the same path, later in object order")
        XCTAssertEqual(project.fileReferences(at: "Foo.swift").map(\.id), ["AA0000000000000000000100", "AA0000000000000000000200"])
        try project.createObject("A00000000000000000000001", isa: "PBXFileReference", attributes: [
            NewEntry("path", .string("Foo.swift")), NewEntry("sourceTree", .string("<group>")),
        ])
        check("a third, earlier in object order")
        XCTAssertEqual(project.fileReferences(at: "Foo.swift").map(\.id), ["A00000000000000000000001", "AA0000000000000000000100", "AA0000000000000000000200"])
        try project.addChild("AA0000000000000000000100", to: "TVOSTEST00020")
        check("an orphan gains its first parent")
        XCTAssertEqual(project.fileReferences(at: "TVOS/Foo.swift").map(\.id), ["AA0000000000000000000100"])
        XCTAssertEqual(project.fileReferences(at: "Foo.swift").map(\.id), ["A00000000000000000000001", "AA0000000000000000000200"])
        try project.addChild("AA0000000000000000000100", to: "SPLASH00000001")
        check("a second parent: dropped and rebuilt")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000100"), .relative("SlowTests/Foo.swift"), "the first parent in object order wins")
        try project.createObject("SS0000000000000000000001", isa: "PBXFileSystemSynchronizedRootGroup", attributes: [
            NewEntry("path", .string("Generated")), NewEntry("sourceTree", .string("<group>")),
        ])
        check("a new synchronized root group")
        try project.addChild("SS0000000000000000000001", to: "TVOSTEST00020")
        check("the synchronized root group gains a parent")
        XCTAssertEqual(project.synchronizedRootGroup(covering: "TVOS/Generated/x.swift")?.id, "SS0000000000000000000001")
        try project.createObject("GG0000000000000000000001", isa: "PBXGroup", attributes: [
            NewEntry("children", .array([project.reference(to: "AA0000000000000000000200")])), NewEntry("path", .string("Sub")), NewEntry("sourceTree", .string("<group>")),
        ])
        check("a new group with a child: dropped and rebuilt")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000200"), .relative("Sub/Foo.swift"))
        try project.addChild("GG0000000000000000000001", to: "AA0000000000000000000001")
        check("a group gains a parent: dropped and rebuilt")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000200"), .relative("Sub/Foo.swift"))
        try project.addChild("ZZ0000000000000000000001", to: "AA0000000000000000000001")
        check("a dangling child")
        try project.createObject("ZZ0000000000000000000001", isa: "PBXFileReference", attributes: [
            NewEntry("path", .string("Late.swift")), NewEntry("sourceTree", .string("<group>")),
        ])
        check("the dangling child is created: it resolves through its parent")
        XCTAssertEqual(project.resolvedPath(of: "ZZ0000000000000000000001"), .relative("Late.swift"))
        try project.deleteObject("AA0000000000000000000200")
        check("delete")
    }

    func testDeletingOneOfSeveralObjectsKeepsTheSection() throws {
        let source = try Fixtures.text("model/app.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try project.deleteObject("BB0000000000000000000010")
        let diff = lineDiff(source, serialized(project))
        XCTAssertEqual(diff.added, [])
        XCTAssertEqual(diff.removed, ["\t\tBB0000000000000000000010 /* AppMain.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000110 /* AppMain.swift */; };\n"])
    }
}
