import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// Task 6.1: one diff-based test per primitive. Every assertion is on the
/// exact lines that changed; `serialized` also checks `plutil -lint`.
final class MutationTests: XCTestCase {
    private var source = ""
    private var project: Project!

    override func setUpWithError() throws {
        source = try Fixtures.text("model/app.pbxproj")
        project = try Project.load(Array(source.utf8))
    }

    private func diff() -> (removed: [String], added: [String]) {
        lineDiff(source, serialized(project))
    }

    // Spec: Mutations change only what they name — create object.
    func testCreateObject() throws {
        try project.createObject("AA0000000000000000000125", isa: "PBXFileReference", attributes: [
            NewEntry("sourceTree", .string("<group>")),
            NewEntry("path", .string("New Item.swift")),
            NewEntry("lastKnownFileType", .string("sourcecode.swift")),
        ])
        let changes = diff()
        XCTAssertEqual(changes.removed, [])
        XCTAssertEqual(changes.added, [
            "\t\tAA0000000000000000000125 /* New Item.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"New Item.swift\"; sourceTree = \"<group>\"; };\n"
        ])
        XCTAssertEqual(project.fileReference("AA0000000000000000000125")?.path, "New Item.swift")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000125"), .relative("New Item.swift"), "an orphan resolves at the root")
    }

    // Spec: Mutations change only what they name — delete object.
    func testDeleteObject() throws {
        try project.deleteObject("AA0000000000000000000009")
        let changes = diff()
        XCTAssertEqual(changes.added, [])
        XCTAssertEqual(changes.removed, [
            "\t\tAA0000000000000000000009 /* Extension */ = {\n", "\t\t\tisa = PBXGroup;\n", "\t\t\tchildren = (\n",
            "\t\t\t\tAA0000000000000000000200 /* ExtensionMain.swift */,\n", "\t\t\t);\n", "\t\t\tpath = Extension;\n",
            "\t\t\tsourceTree = \"<group>\";\n", "\t\t};\n",
        ])
        XCTAssertNil(project.group("AA0000000000000000000009"))
        XCTAssertEqual(project.group("AA0000000000000000000002")?.children.contains("AA0000000000000000000009"), true,
                       "the reference from the parent is left for rule S2")
        XCTAssertEqual(project.parents(of: "AA0000000000000000000200"), [], "the child is now an orphan (rule M3)")
        XCTAssertThrowsError(try project.deleteObject("AA0000000000000000000009")) { error in
            XCTAssertEqual(error as? MutationError, .noSuchObject("AA0000000000000000000009"))
        }
    }

    // Spec: Mutations change only what they name — Add a child to a group.
    func testAddChild() throws {
        var large = try Project.load(Array(MutationTests.groupWithFortyChildren.utf8))
        try large.addChild("F40", to: "G1")
        let changes = lineDiff(MutationTests.groupWithFortyChildren, serialized(large))
        XCTAssertEqual(changes.removed, [])
        XCTAssertEqual(changes.added, ["\t\t\t\tF40 /* f40.c */,\n"])
        XCTAssertEqual(large.group("G1")?.children.count, 41)

        try project.addChild("AA0000000000000000000200", to: "AA0000000000000000000003", position: .first)
        let positioned = diff()
        XCTAssertEqual(positioned.removed, [])
        XCTAssertEqual(positioned.added, ["\t\t\t\tAA0000000000000000000200 /* ExtensionMain.swift */,\n"])
        XCTAssertEqual(project.group("AA0000000000000000000003")?.children, ["AA0000000000000000000200", "AA0000000000000000000120"])
        XCTAssertEqual(project.parents(of: "AA0000000000000000000200").map(\.id), ["AA0000000000000000000003", "AA0000000000000000000009"],
                       "both parents, in object order (rule M3's input)")
        XCTAssertThrowsError(try project.addChild("AA0000000000000000000200", to: "AA0000000000000000000120")) { error in
            XCTAssertEqual(error as? MutationError, .notAGroup("AA0000000000000000000120"))
        }
        XCTAssertThrowsError(try project.addChild("AA0000000000000000000200", to: "nope"))
    }

    // Spec: Mutations change only what they name — remove child.
    func testRemoveChild() throws {
        try project.removeChild("AA0000000000000000000130", from: "AA0000000000000000000002")
        let changes = diff()
        XCTAssertEqual(changes.added, [])
        XCTAssertEqual(changes.removed, ["\t\t\t\tAA0000000000000000000130 /* Shared.swift */,\n"])
        XCTAssertEqual(project.parents(of: "AA0000000000000000000130"), [])
        XCTAssertNotNil(project.fileReference("AA0000000000000000000130"), "the reference itself stays")
        XCTAssertThrowsError(try project.removeChild("AA0000000000000000000130", from: "AA0000000000000000000002")) { error in
            XCTAssertEqual(error as? MutationError, .notAChild("AA0000000000000000000130", of: "AA0000000000000000000002"))
        }
    }

    // Spec: Mutations change only what they name — add phase entry.
    func testAddPhaseEntry() throws {
        try project.createObject("BB0000000000000000000045", isa: "PBXBuildFile", attributes: [
            NewEntry("fileRef", project.reference(to: "AA0000000000000000000150")),
        ])
        try project.addPhaseEntry("BB0000000000000000000045", to: "CC0000000000000000000004")
        let changes = diff()
        XCTAssertEqual(changes.removed, [])
        XCTAssertEqual(changes.added, [
            "\t\tBB0000000000000000000045 /* Bar.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000150 /* Bar.swift */; };\n",
            "\t\t\t\tBB0000000000000000000045 /* Bar.swift in Sources */,\n",
        ])
        XCTAssertEqual(project.phases(of: "BB0000000000000000000045").map(\.id), ["CC0000000000000000000004"])
        XCTAssertEqual(project.membership(of: "AA0000000000000000000150").targets.map(\.name), ["AppExtension", "AppTests"],
                       "in the order of the build files")
        XCTAssertThrowsError(try project.addPhaseEntry("BB0000000000000000000045", to: "AA0000000000000000000002")) { error in
            XCTAssertEqual(error as? MutationError, .notABuildPhase("AA0000000000000000000002"))
        }
    }

    func testAddPhaseEntryIntoAnEmptyPhaseAndAtAPosition() throws {
        try project.addPhaseEntry("BB0000000000000000000080", to: "CC0000000000000000000006")
        try project.addPhaseEntry("BB0000000000000000000030", to: "CC0000000000000000000001", position: .before("BB0000000000000000000010"))
        let changes = diff()
        XCTAssertEqual(changes.removed, [])
        XCTAssertEqual(changes.added, [
            "\t\t\t\tBB0000000000000000000080 /* Foundation.framework in Frameworks */,\n",
            "\t\t\t\tBB0000000000000000000030 /* Shared.swift in Sources */,\n",
        ])
        XCTAssertEqual(project.phases(of: "BB0000000000000000000030").map(\.id), ["CC0000000000000000000001", "CC0000000000000000000001"], "rule M5's input")
    }

    // Spec: Mutations change only what they name — remove phase entry.
    func testRemovePhaseEntry() throws {
        try project.removePhaseEntry("BB0000000000000000000020", from: "CC0000000000000000000001")
        let changes = diff()
        XCTAssertEqual(changes.added, [])
        XCTAssertEqual(changes.removed, ["\t\t\t\tBB0000000000000000000020 /* Foo.swift in Sources */,\n"])
        XCTAssertEqual(project.phases(of: "BB0000000000000000000020"), [], "rule M1's input")
        XCTAssertNotNil(project.buildFile("BB0000000000000000000020"), "the build file itself stays")
        XCTAssertThrowsError(try project.removePhaseEntry("BB0000000000000000000020", from: "CC0000000000000000000001")) { error in
            XCTAssertEqual(error as? MutationError, .notInPhase("BB0000000000000000000020", phase: "CC0000000000000000000001"))
        }
    }

    // Spec: Mutations change only what they name — set attribute.
    func testSetAttributeReplacesAddsInKeyOrderAndRemoves() throws {
        try project.setAttribute("platformFilters", of: "BB0000000000000000000040", to: .array([.string("ios")]))
        var changes = diff()
        XCTAssertEqual(changes.removed.count, 1)
        XCTAssertEqual(changes.added, [
            "\t\tBB0000000000000000000040 /* Shared.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000130 /* Shared.swift */; platformFilters = (ios, ); };\n"
        ])
        XCTAssertEqual(project.buildFile("BB0000000000000000000040")?.platformFilters, ["ios"])

        try project.setAttribute("platformFilters", of: "BB0000000000000000000040", to: nil)
        try project.setAttribute("platformFilter", of: "BB0000000000000000000030", to: .string("ios"))
        try project.setAttribute("settings", of: "BB0000000000000000000030", to: .dictionary([NewEntry("ATTRIBUTES", .array([.string("Public")]))]))
        try project.setAttribute("name", of: "AA0000000000000000000003", to: .string("Views"))
        try project.setAttribute("wrapsLines", of: "AA0000000000000000000120", to: .string("1"))
        changes = diff()
        XCTAssertEqual(changes.removed.count, 3)
        XCTAssertEqual(changes.added, [
            "\t\tBB0000000000000000000030 /* Shared.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000130 /* Shared.swift */; platformFilter = ios; settings = {ATTRIBUTES = (Public, ); }; };\n",
            "\t\tBB0000000000000000000040 /* Shared.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000130 /* Shared.swift */; };\n",
            "\t\tAA0000000000000000000120 /* Foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = \"<group>\"; wrapsLines = 1; };\n",
            "\t\t\tname = Views;\n",
        ])
        XCTAssertNil(project.buildFile("BB0000000000000000000040")?.platformFilters)
        XCTAssertEqual(project.group("AA0000000000000000000003")?.name, "Views")
        XCTAssertThrowsError(try project.setAttribute("isa", of: "AA0000000000000000000003", to: .string("PBXVariantGroup"))) { error in
            XCTAssertEqual(error as? MutationError, .isaIsImmutable("AA0000000000000000000003"))
        }
        XCTAssertThrowsError(try project.setAttribute("name", of: "nope", to: .string("x")))
    }

    func testSetAttributeOnAMultiLineObjectKeepsItsLayout() throws {
        try project.setAttribute("buildActionMask", of: "CC0000000000000000000006", to: .string("12"))
        try project.setAttribute("inputPaths", of: "CC0000000000000000000006", to: .array([.string("$(SRCROOT)/a"), .string("b")]))
        let changes = diff()
        XCTAssertEqual(changes.removed, ["\t\t\tbuildActionMask = 2147483647;\n"])
        XCTAssertEqual(changes.added.sorted(), [
            "\t\t\tbuildActionMask = 12;\n", "\t\t\tinputPaths = (\n", "\t\t\t\t\"$(SRCROOT)/a\",\n", "\t\t\t\tb,\n", "\t\t\t);\n",
        ].sorted())
        XCTAssertTrue(serialized(project).contains("\t\t\tinputPaths = (\n\t\t\t\t\"$(SRCROOT)/a\",\n\t\t\t\tb,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing"))
    }

    /// A group with forty children for the spec's add-child scenario.
    static let groupWithFortyChildren: String = {
        var lines = ["// !$*UTF8*$!", "{", "\tobjects = {", "", "/* Begin PBXFileReference section */"]
        for index in 0...40 {
            lines.append("\t\tF\(index) /* f\(index).c */ = {isa = PBXFileReference; path = f\(index).c; sourceTree = \"<group>\"; };")
        }
        lines.append(contentsOf: ["/* End PBXFileReference section */", "", "/* Begin PBXGroup section */", "\t\tG1 = {", "\t\t\tisa = PBXGroup;", "\t\t\tchildren = ("])
        for index in 0..<40 { lines.append("\t\t\t\tF\(index) /* f\(index).c */,") }
        lines.append(contentsOf: ["\t\t\t);", "\t\t\tsourceTree = \"<group>\";", "\t\t};", "/* End PBXGroup section */", "", "/* Begin PBXProject section */", "\t\tP1 /* Project object */ = {", "\t\t\tisa = PBXProject;", "\t\t\tmainGroup = G1;", "\t\t};", "/* End PBXProject section */", "\t};", "\trootObject = P1 /* Project object */;", "}", ""])
        return lines.joined(separator: "\n")
    }()
}
