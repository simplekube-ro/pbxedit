import Foundation
import XCTest
import PBXModel
@testable import PBXOps

/// Task 2.1: `MembershipReport` built from the shipped fixtures (design D2).
final class MembershipReportTests: XCTestCase {
    private static let app = ObjectRef(id: "DD0000000000000000000001", name: "App")
    private static let appExtension = ObjectRef(id: "DD0000000000000000000002", name: "AppExtension")
    private static let appSources = ObjectRef(id: "CC0000000000000000000001", name: "Sources")
    private static let extensionSources = ObjectRef(id: "CC0000000000000000000004", name: "Sources")

    // Spec: Membership of a path — Ordinary member.
    func testOrdinaryMember() throws {
        let project = try loadProject("model/app.pbxproj")
        let report = MembershipReport(project: project, path: "App/Views/Foo.swift")
        XCTAssertEqual(report, MembershipReport(
            path: "App/Views/Foo.swift",
            member: true,
            fileReference: "AA0000000000000000000120",
            groupPath: "App/Views",
            groups: ["AA0000000000000000000003"],
            memberships: [
                MembershipReport.Entry(target: Self.app, phase: Self.appSources, buildFile: "BB0000000000000000000020", platformFilters: []),
            ],
            synchronized: nil))
    }

    // Spec: Membership of a path — Shared source with platform filters.
    func testSharedSourceIsOrderedByTargetNameAndCarriesFilters() throws {
        let project = try loadProject("model/app.pbxproj")
        let report = MembershipReport(project: project, path: "App/Shared.swift")
        XCTAssertTrue(report.member)
        XCTAssertEqual(report.fileReference, "AA0000000000000000000130")
        XCTAssertEqual(report.groupPath, "App")
        XCTAssertEqual(report.memberships, [
            MembershipReport.Entry(target: Self.app, phase: Self.appSources, buildFile: "BB0000000000000000000030", platformFilters: []),
            MembershipReport.Entry(target: Self.appExtension, phase: Self.extensionSources, buildFile: "BB0000000000000000000040", platformFilters: ["ios", "maccatalyst"]),
        ])
    }

    func testMembershipsAreOrderedByTargetNameNotObjectOrder() throws {
        // Target Z is defined before target A; the report lists A first. The
        // older single-value `platformFilter` becomes a one-element array.
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; targets = (TZ, TA, ); };
                G1 = {isa = PBXGroup; children = (F1, ); sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = x.c; sourceTree = "<group>"; };
                B1 = {isa = PBXBuildFile; fileRef = F1; platformFilter = ios; };
                B2 = {isa = PBXBuildFile; fileRef = F1; };
                SZ = {isa = PBXSourcesBuildPhase; files = (B1, ); };
                SA = {isa = PBXSourcesBuildPhase; files = (B2, ); };
                TZ = {isa = PBXNativeTarget; name = Z; buildPhases = (SZ, ); };
                TA = {isa = PBXNativeTarget; name = A; buildPhases = (SA, ); };
            }; rootObject = P1; }
            """
        let report = MembershipReport(project: try Project.load(Array(source.utf8)), path: "x.c")
        XCTAssertEqual(report.groupPath, "", "a child of the main group has an empty group path")
        XCTAssertEqual(report.memberships, [
            MembershipReport.Entry(target: ObjectRef(id: "TA", name: "A"), phase: ObjectRef(id: "SA", name: "Sources"), buildFile: "B2", platformFilters: []),
            MembershipReport.Entry(target: ObjectRef(id: "TZ", name: "Z"), phase: ObjectRef(id: "SZ", name: "Sources"), buildFile: "B1", platformFilters: ["ios"]),
        ])
    }

    // Spec: Membership of a path — Build file in no phase.
    func testBuildFileInNoPhase() throws {
        let project = try loadProject("rules/m1-no-phase.pbxproj")
        let report = MembershipReport(project: project, path: "AppTests/FooTests.swift")
        XCTAssertEqual(report, MembershipReport(
            path: "AppTests/FooTests.swift",
            member: true,
            fileReference: "AB12",
            groupPath: "AppTests",
            groups: ["G002"],
            memberships: [MembershipReport.Entry(target: nil, phase: nil, buildFile: "BF01", platformFilters: [])],
            synchronized: nil))
    }

    // Spec: Membership of a path — Reference with no group.
    func testReferenceWithNoGroup() throws {
        let project = try loadProject("rules/m3-orphan.pbxproj")
        let report = MembershipReport(project: project, path: "AppTests/Views/FooTests.swift")
        XCTAssertEqual(report, MembershipReport(
            path: "AppTests/Views/FooTests.swift",
            member: true,
            fileReference: "AB12",
            groupPath: nil,
            groups: [],
            memberships: [
                MembershipReport.Entry(
                    target: ObjectRef(id: "T001", name: "App"), phase: ObjectRef(id: "S001", name: "Sources"),
                    buildFile: "BF01", platformFilters: []),
            ],
            synchronized: nil))
    }

    func testAPhaseOwnedByNoTargetAndAReferenceInTwoGroups() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; targets = (); };
                G1 = {isa = PBXGroup; children = (G2, G3, ); sourceTree = "<group>"; };
                G2 = {isa = PBXGroup; children = (F1, ); path = Lib; sourceTree = "<group>"; };
                G3 = {isa = PBXGroup; children = (F1, ); name = Other; sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = x.c; sourceTree = "<group>"; };
                B1 = {isa = PBXBuildFile; fileRef = F1; };
                S1 = {isa = PBXSourcesBuildPhase; files = (B1, ); name = "Own Sources"; };
            }; rootObject = P1; }
            """
        let report = MembershipReport(project: try Project.load(Array(source.utf8)), path: "Lib/x.c")
        XCTAssertEqual(report.groupPath, "Lib")
        XCTAssertEqual(report.groups, ["G2", "G3"])
        XCTAssertEqual(report.memberships, [
            MembershipReport.Entry(target: nil, phase: ObjectRef(id: "S1", name: "Own Sources"), buildFile: "B1", platformFilters: []),
        ])
    }

    // Spec: Paths outside the project — Unknown path.
    func testUnknownPath() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertEqual(MembershipReport(project: project, path: "App/Nope.swift"), MembershipReport(
            path: "App/Nope.swift", member: false, fileReference: nil, groupPath: nil, groups: [], memberships: [], synchronized: nil))
        XCTAssertFalse(MembershipReport(project: project, path: "Foo.swift").member, "never by basename")
    }

    // Spec: Paths outside the project — Synchronized folder.
    func testSynchronizedFolder() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertEqual(MembershipReport(project: project, path: "App/Generated/User.swift"), MembershipReport(
            path: "App/Generated/User.swift", member: false, fileReference: nil, groupPath: nil, groups: [], memberships: [],
            synchronized: MembershipReport.SynchronizedCoverage(group: "AA0000000000000000000301", path: "App/Generated", targets: [Self.app])))
    }

    func testJSONKeepsAbsentValuesAsNull() throws {
        let project = try loadProject("rules/m1-no-phase.pbxproj")
        let report = MembershipReport(project: project, path: "AppTests/FooTests.swift")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(report), as: UTF8.self)
        XCTAssertEqual(text, """
            {"fileReference":"AB12","groupPath":"AppTests","groups":["G002"],"member":true,\
            "memberships":[{"buildFile":"BF01","phase":null,"platformFilters":[],"target":null}],\
            "path":"AppTests/FooTests.swift","synchronized":null}
            """)
        let unknown = MembershipReport(project: project, path: "Nope.swift")
        let unknownText = String(decoding: try encoder.encode(unknown), as: UTF8.self)
        XCTAssertEqual(unknownText, """
            {"fileReference":null,"groupPath":null,"groups":[],"member":false,"memberships":[],"path":"Nope.swift","synchronized":null}
            """)
        let covered = MembershipReport(project: try loadProject("model/app.pbxproj"), path: "App/Generated/User.swift")
        let coveredText = String(decoding: try encoder.encode(covered), as: UTF8.self)
        XCTAssertTrue(coveredText.contains("\"synchronized\":{\"group\":\"AA0000000000000000000301\",\"path\":\"App/Generated\",\"targets\":[{\"id\":\"DD0000000000000000000001\",\"name\":\"App\"}]}"), coveredText)
    }
}
