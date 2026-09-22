import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// Task 5.4: annotation comments (design D6).
final class AnnotationTests: XCTestCase {
    func testAnnotationsMatchXcodeForEveryKindTheModelKnows() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertEqual(project.annotation(for: "AA0000000000000000000120"), "Foo.swift", "a reference: path")
        XCTAssertEqual(project.annotation(for: "AA0000000000000000000140"), "FooTests.swift", "a reference: name before path")
        XCTAssertEqual(project.annotation(for: "AA0000000000000000000002"), "App", "a group: path")
        XCTAssertEqual(project.annotation(for: "AA0000000000000000000004"), "Tests", "a group: name")
        XCTAssertNil(project.annotation(for: "AA0000000000000000000001"), "the main group has neither")
        XCTAssertEqual(project.annotation(for: "AA0000000000000000000201"), "Localizable.strings")
        XCTAssertEqual(project.annotation(for: "AA0000000000000000000301"), "Generated")
        XCTAssertEqual(project.annotation(for: "BB0000000000000000000020"), "Foo.swift in Sources")
        XCTAssertEqual(project.annotation(for: "BB0000000000000000000080"), "Foundation.framework in Frameworks")
        XCTAssertEqual(project.annotation(for: "BB0000000000000000000090"), "Localizable.strings in Resources")
        XCTAssertEqual(project.annotation(for: "CC0000000000000000000001"), "Sources")
        XCTAssertEqual(project.annotation(for: "DD0000000000000000000002"), "AppExtension")
        XCTAssertEqual(project.annotation(for: "EE0000000000000000000001"), "Project object")
        XCTAssertNil(project.annotation(for: "FF0000000000000000000001"), "a kind the model does not write has none")
        XCTAssertNil(project.annotation(for: "nope"))
    }

    func testBuildFileAnnotationsFollowThePhaseAndTheProduct() throws {
        let broken = try loadProject("model/broken.pbxproj")
        XCTAssertNil(broken.annotation(for: "BB0000000000000000000020"), "a build file in no phase has no Xcode comment")
        XCTAssertNil(broken.annotation(for: "BB0000000000000000000010"), "a dangling fileRef has no name")
        let source = """
            { objects = {
                P1 = {isa = PBXProject; };
                D1 = {isa = XCSwiftPackageProductDependency; productName = Alamofire; };
                B1 = {isa = PBXBuildFile; productRef = D1; };
                B2 = {isa = PBXBuildFile; fileRef = F1; };
                F1 = {isa = PBXFileReference; path = "x.c"; };
                S1 = {isa = PBXFrameworksBuildPhase; files = (B1, ); };
                S2 = {isa = PBXCopyFilesBuildPhase; files = (B2, ); name = "Embed Frameworks"; };
                S3 = {isa = PBXCopyFilesBuildPhase; files = (); };
                S4 = {isa = PBXShellScriptBuildPhase; files = (); };
                S5 = {isa = PBXRezBuildPhase; files = (); };
                S6 = {isa = PBXHeadersBuildPhase; files = (); };
                S7 = {isa = PBXResourcesBuildPhase; files = (); };
            }; rootObject = P1; }
            """
        let project = try Project.load(Array(source.utf8))
        XCTAssertEqual(project.annotation(for: "B1"), "Alamofire in Frameworks")
        XCTAssertEqual(project.annotation(for: "B2"), "x.c in Embed Frameworks")
        XCTAssertEqual(["S1", "S2", "S3", "S4", "S5", "S6", "S7"].map { project.annotation(for: $0) },
                       ["Frameworks", "Embed Frameworks", "CopyFiles", "ShellScript", "Rez", "Headers", "Resources"])
    }

    // Spec: Annotation comments match Xcode — Rename.
    func testRenamingAFileReferenceRefreshesEveryComment() throws {
        let source = try Fixtures.text("model/app.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try project.setAttribute("path", of: "AA0000000000000000000120", to: .string("New.swift"))
        let output = serialized(project)
        XCTAssertFalse(output.contains("Foo.swift"), output)
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.removed.count, 4)
        XCTAssertEqual(diff.added, [
            "\t\tBB0000000000000000000020 /* New.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000120 /* New.swift */; };\n",
            "\t\tAA0000000000000000000120 /* New.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = New.swift; sourceTree = \"<group>\"; };\n",
            "\t\t\t\tAA0000000000000000000120 /* New.swift */,\n",
            "\t\t\t\tBB0000000000000000000020 /* New.swift in Sources */,\n",
        ])
        XCTAssertEqual(project.fileReferences(at: "App/Views/New.swift").map(\.id), ["AA0000000000000000000120"])
    }

    func testRenamingAPhaseRefreshesItsBuildFilesAndTargets() throws {
        let source = try Fixtures.text("model/app.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try project.setAttribute("name", of: "CC0000000000000000000004", to: .string("Compile"))
        let output = serialized(project)
        let diff = lineDiff(source, output)
        XCTAssertEqual(Set(diff.added), [
            "\t\t\t\tBB0000000000000000000040 /* Shared.swift in Compile */,\n",
            "\t\t\t\tBB0000000000000000000050 /* ExtensionMain.swift in Compile */,\n",
            "\t\t\t\tCC0000000000000000000004 /* Compile */,\n",
            "\t\tBB0000000000000000000040 /* Shared.swift in Compile */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000130 /* Shared.swift */; platformFilters = (ios, maccatalyst, ); };\n",
            "\t\tBB0000000000000000000050 /* ExtensionMain.swift in Compile */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000200 /* ExtensionMain.swift */; };\n",
            "\t\tCC0000000000000000000004 /* Compile */ = {\n",
            "\t\t\tname = Compile;\n",
        ])
        XCTAssertEqual(diff.removed.count, 6)
        XCTAssertEqual(diff.added.count, 7)
        XCTAssertTrue(output.contains("BB0000000000000000000030 /* Shared.swift in Sources */,"), "the other target's entry is untouched")
    }

    func testRefreshOnlyRewritesExistingComments() throws {
        // `mainGroup = X;` is bare in Xcode's files and must stay bare.
        let source = "{\n\tobjects = {\n\t\tP1 = {\n\t\t\tisa = PBXProject;\n\t\t\tmainGroup = G1;\n\t\t\tproductRefGroup = G1 /* Old */;\n\t\t};\n\t\tG1 /* Old */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t\tname = Old;\n\t\t};\n\t};\n\trootObject = P1;\n}\n"
        var project = try Project.load(Array(source.utf8))
        try project.setAttribute("name", of: "G1", to: .string("New"))
        XCTAssertEqual(
            serialized(project),
            source.replacingOccurrences(of: "/* Old */", with: "/* New */").replacingOccurrences(of: "name = Old;", with: "name = New;"))
    }

    func testRefreshAnnotationsIsExplicitlyCallable() throws {
        let source = try Fixtures.text("model/app.pbxproj")
        var project = try Project.load(Array(source.utf8))
        try project.refreshAnnotations(for: "AA0000000000000000000120")
        XCTAssertEqual(serialized(project), source, "nothing changes when every comment is already right")
        XCTAssertThrowsError(try project.refreshAnnotations(for: "nope"))
    }
}
