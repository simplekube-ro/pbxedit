import Foundation
import XCTest
import PBXModel
@testable import PBXOps

/// Task 3.1: `--target` listing (spec: Members of a target; design D2).
final class TargetMembersTests: XCTestCase {
    // Spec: Members of a target — Target listing.
    func testTargetListingIsOrderedByPhaseThenPath() throws {
        let project = try loadProject("model/app.pbxproj")
        let listing = try XCTUnwrap(TargetMembers(project: project, target: "AppTests"))
        XCTAssertEqual(listing.target, ObjectRef(id: "DD0000000000000000000003", name: "AppTests"))
        XCTAssertEqual(listing.members, [
            TargetMembers.Member(
                buildFile: "BB0000000000000000000070", fileReference: "AA0000000000000000000150", path: "AppTests/Foo/Bar.swift",
                phase: ObjectRef(id: "CC0000000000000000000005", name: "Sources"), platformFilters: []),
            TargetMembers.Member(
                buildFile: "BB0000000000000000000060", fileReference: "AA0000000000000000000140", path: "AppTests/Views/FooTests.swift",
                phase: ObjectRef(id: "CC0000000000000000000005", name: "Sources"), platformFilters: []),
        ])
    }

    func testPhasesSortByNameAndAnSDKFrameworkShowsItsSourceTree() throws {
        let project = try loadProject("model/app.pbxproj")
        let listing = try XCTUnwrap(TargetMembers(project: project, target: "App"))
        XCTAssertEqual(listing.members.map(\.phase.name), ["Frameworks", "Resources", "Sources", "Sources", "Sources"])
        XCTAssertEqual(listing.members.map(\.path), [
            "$(SDKROOT)/System/Library/Frameworks/Foundation.framework",
            "App/Resources/Localizable.strings",
            "App/AppMain.swift",
            "App/Shared.swift",
            "App/Views/Foo.swift",
        ])
        XCTAssertEqual(listing.members[0].fileReference, "AA0000000000000000000160")
        XCTAssertEqual(listing.members[0].buildFile, "BB0000000000000000000080")
    }

    func testFiltersAndEntriesThatResolveToNothing() throws {
        let listing = try XCTUnwrap(TargetMembers(project: try loadProject("model/app.pbxproj"), target: "AppExtension"))
        XCTAssertEqual(listing.members.map(\.platformFilters), [[], ["ios", "maccatalyst"]])
        XCTAssertEqual(listing.members.map(\.path), ["App/Extension/ExtensionMain.swift", "App/Shared.swift"])

        // A dangling entry (M2) and a build file whose fileRef is gone: facts, path absent, sorted last.
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; targets = (T1, ); };
                G1 = {isa = PBXGroup; children = (F1, ); sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = x.c; sourceTree = "<group>"; };
                B1 = {isa = PBXBuildFile; fileRef = F1; };
                B2 = {isa = PBXBuildFile; fileRef = GONE; };
                S1 = {isa = PBXSourcesBuildPhase; files = (B2, DEAD, B1, ); };
                T1 = {isa = PBXNativeTarget; name = A; buildPhases = (S1, ); };
            }; rootObject = P1; }
            """
        let broken = try XCTUnwrap(TargetMembers(project: try Project.load(Array(source.utf8)), target: "A"))
        XCTAssertEqual(broken.members.map(\.buildFile), ["B1", "B2", "DEAD"])
        XCTAssertEqual(broken.members.map(\.path), ["x.c", nil, nil])
        XCTAssertEqual(broken.members.map(\.fileReference), ["F1", "GONE", nil])
    }

    // Spec: Members of a target — Unknown target (the model side: nothing to list).
    func testUnknownTargetYieldsNothingAndNamesAreListed() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertNil(TargetMembers(project: project, target: "Apptests"), "names match exactly")
        XCTAssertEqual(TargetMembers.targetNames(in: project), ["App", "AppExtension", "AppTests"])
    }

    func testJSONKeepsAbsentValuesAsNull() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; targets = (T1, ); };
                G1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
                S1 = {isa = PBXSourcesBuildPhase; files = (DEAD, ); };
                T1 = {isa = PBXNativeTarget; buildPhases = (S1, ); };
            }; rootObject = P1; }
            """
        let project = try Project.load(Array(source.utf8))
        XCTAssertNil(TargetMembers(project: project, target: "T1"), "a nameless target cannot be named on the command line")
        let listing = TargetMembers(project: project, target: try XCTUnwrap(project.target("T1")))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(listing), as: UTF8.self)
        XCTAssertEqual(text, """
            {"members":[{"buildFile":"DEAD","fileReference":null,"path":null,"phase":{"id":"S1","name":"Sources"},"platformFilters":[]}],\
            "target":{"id":"T1","name":null}}
            """)
    }
}
