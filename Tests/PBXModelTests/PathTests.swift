import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// Task 3.1: path resolution and lookup by resolved path (design D4).
final class PathTests: XCTestCase {
    // Spec: Path resolution — Group-relative reference.
    func testGroupRelativeReferenceResolvesThroughItsParents() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000120"), .relative("App/Views/Foo.swift"))
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000003"), .relative("App/Views"))
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000001"), .relative(""), "the main group is the source root")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000210"), .relative("App/Resources/en.lproj/Localizable.strings"))
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000301"), .relative("App/Generated"))
    }

    // Spec: Path resolution — Source-root reference in a pathless group.
    func testSourceRootReferenceIgnoresItsParents() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000140"), .relative("AppTests/Views/FooTests.swift"))
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000004"), .relative(""), "a pathless group contributes nothing")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000150"), .relative("AppTests/Foo/Bar.swift"))
    }

    // Spec: Path resolution — Reference with no parent group.
    func testOrphanResolvesRelativeToTheSourceRoot() throws {
        let project = try loadProject("model/broken.pbxproj")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000100"), .relative("Foo.swift"))
        XCTAssertEqual(project.parents(of: "AA0000000000000000000100"), [])
    }

    // Spec: Path resolution — SDK reference.
    func testSDKReferenceIsNotProjectRelative() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000160"), .notProjectRelative(sourceTree: "SDKROOT"))
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000170"), .notProjectRelative(sourceTree: "BUILT_PRODUCTS_DIR"))
        XCTAssertEqual(project.fileReferences(at: "System/Library/Frameworks/Foundation.framework"), [])
        XCTAssertEqual(project.fileReferences(at: "Foundation.framework"), [])
        XCTAssertNil(project.resolvedPath(of: "BB0000000000000000000010"), "a build file has no path")
        XCTAssertNil(project.resolvedPath(of: "nope"))
    }

    func testAbsoluteAndParentRelativePaths() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; };
                G1 = {isa = PBXGroup; children = (G2, F1, F2, G3, ); sourceTree = "<group>"; };
                G2 = {isa = PBXGroup; children = (F3, F4, ); path = "/opt/shared"; sourceTree = "<absolute>"; };
                G3 = {isa = PBXGroup; children = (F5, ); path = "../Sibling/./src"; sourceTree = SOURCE_ROOT; };
                F1 = {isa = PBXFileReference; path = "./App/../Lib/x.c"; sourceTree = "<group>"; };
                F2 = {isa = PBXFileReference; path = "/usr/lib/libz.dylib"; sourceTree = "<absolute>"; };
                F3 = {isa = PBXFileReference; path = "y.c"; sourceTree = "<group>"; };
                F4 = {isa = PBXFileReference; path = "z.c"; sourceTree = SOURCE_ROOT; };
                F5 = {isa = PBXFileReference; path = "w.c"; sourceTree = "<group>"; };
            }; rootObject = P1; }
            """
        let project = try Project.load(Array(source.utf8))
        XCTAssertEqual(project.resolvedPath(of: "F1"), .relative("Lib/x.c"))
        XCTAssertEqual(project.resolvedPath(of: "F2"), .absolute("/usr/lib/libz.dylib"))
        XCTAssertEqual(project.resolvedPath(of: "G2"), .absolute("/opt/shared"))
        XCTAssertEqual(project.resolvedPath(of: "F3"), .absolute("/opt/shared/y.c"))
        XCTAssertEqual(project.resolvedPath(of: "F4"), .relative("z.c"), "SOURCE_ROOT ignores an absolute parent")
        XCTAssertEqual(project.resolvedPath(of: "G3"), .relative("../Sibling/src"))
        XCTAssertEqual(project.resolvedPath(of: "F5"), .relative("../Sibling/src/w.c"))
        XCTAssertEqual(project.fileReferences(at: "Lib/x.c").map(\.id), ["F1"])
        XCTAssertEqual(project.fileReferences(at: "/opt/shared/y.c").map(\.id), ["F3"])
        XCTAssertEqual(project.fileReferences(at: "../Sibling/src/w.c").map(\.id), ["F5"])
    }

    func testCyclicGroupsDoNotResolve() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; };
                G1 = {isa = PBXGroup; children = (G2, ); path = a; sourceTree = "<group>"; };
                G2 = {isa = PBXGroup; children = (G1, F1, ); path = b; sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = "x.c"; sourceTree = "<group>"; };
            }; rootObject = P1; }
            """
        let project = try Project.load(Array(source.utf8))
        XCTAssertNil(project.resolvedPath(of: "G1"))
        XCTAssertNil(project.resolvedPath(of: "F1"))
        XCTAssertEqual(project.fileReferences(at: "a/b/x.c"), [])
    }

    // Spec: Lookup by resolved path — Same basename in two targets. Motivation table, row 5.
    func testLookupIsByResolvedPathNotBasename() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertEqual(project.fileReferences(at: "AppTests/Foo/Bar.swift").map(\.id), ["AA0000000000000000000150"])
        XCTAssertEqual(project.fileReferences(at: "AppSlowTests/Foo/Bar.swift"), [])
        XCTAssertEqual(project.fileReferences(at: "Bar.swift"), [])
        XCTAssertEqual(project.fileReferences(at: "Foo/Bar.swift"), [])
        XCTAssertEqual(project.fileReferences(at: "apptests/Foo/Bar.swift"), [], "paths are compared case-sensitively")
    }

    // Spec: Lookup by resolved path — Equivalent spellings.
    func testLookupNormalizesTheQuery() throws {
        let project = try loadProject("model/app.pbxproj")
        for spelling in ["./App/Views/../Views/Foo.swift", "App//Views/Foo.swift", "App/Views/Foo.swift/", "App/./Views/Foo.swift"] {
            XCTAssertEqual(project.fileReferences(at: spelling).map(\.id), ["AA0000000000000000000120"], spelling)
        }
    }

    func testTwoReferencesToOnePathAreBothReturned() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; };
                G1 = {isa = PBXGroup; children = (F1, G2, ); sourceTree = "<group>"; };
                G2 = {isa = PBXGroup; children = (F2, ); path = Lib; sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = "Lib/x.c"; sourceTree = "<group>"; };
                F2 = {isa = PBXFileReference; path = "x.c"; sourceTree = "<group>"; };
            }; rootObject = P1; }
            """
        let project = try Project.load(Array(source.utf8))
        XCTAssertEqual(project.fileReferences(at: "Lib/x.c").map(\.id), ["F1", "F2"], "rule M4's input, in object order")
    }

    func testGroupsAreFoundByDirectoryOrderedByDepth() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertEqual(project.groups(at: "App/Views").map(\.id), ["AA0000000000000000000003"])
        XCTAssertEqual(project.groups(at: "AppTests").map(\.id), ["AA0000000000000000000005"])
        XCTAssertEqual(project.groups(at: "").map(\.id), ["AA0000000000000000000001", "AA0000000000000000000004", "AA0000000000000000000007", "AA0000000000000000000008"],
                       "the main group first, then the pathless groups in object order")
        XCTAssertEqual(project.groups(at: "App/Views/Foo.swift"), [])
        // A group nested deeper than another at the same directory comes later.
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; };
                G1 = {isa = PBXGroup; children = (G3, G2, ); sourceTree = "<group>"; };
                G2 = {isa = PBXGroup; children = (); path = Lib; sourceTree = "<group>"; };
                G3 = {isa = PBXGroup; children = (G4, ); name = Wrapper; sourceTree = "<group>"; };
                G4 = {isa = PBXGroup; children = (); path = Lib; sourceTree = SOURCE_ROOT; };
            }; rootObject = P1; }
            """
        let nested = try Project.load(Array(source.utf8))
        XCTAssertEqual(nested.groups(at: "Lib").map(\.id), ["G2", "G4"])
    }
}
