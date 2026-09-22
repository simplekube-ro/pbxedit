import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// Task 4.1: the membership indexes (design D2–D3) and synchronized root groups.
final class MembershipTests: XCTestCase {
    // Spec: Membership indexes — Shared source.
    func testSharedSourceReportsBothTargets() throws {
        let project = try loadProject("model/app.pbxproj")
        let report = project.membership(of: "AA0000000000000000000130")
        XCTAssertEqual(report.fileReference, "AA0000000000000000000130")
        XCTAssertEqual(report.parents.map(\.id), ["AA0000000000000000000002"])
        XCTAssertEqual(report.buildFiles.map(\.buildFile.id), ["BB0000000000000000000030", "BB0000000000000000000040"])
        XCTAssertEqual(report.buildFiles.map { $0.phases.map(\.phase.id) }, [["CC0000000000000000000001"], ["CC0000000000000000000004"]])
        XCTAssertEqual(report.buildFiles.map { $0.phases.flatMap { $0.targets.map(\.name) } }, [["App"], ["AppExtension"]])
        XCTAssertEqual(report.buildFiles.map(\.platformFilters), [nil, ["ios", "maccatalyst"]])
        XCTAssertEqual(report.targets.map(\.name), ["App", "AppExtension"])
        XCTAssertEqual(report.targets.map(\.id), ["DD0000000000000000000001", "DD0000000000000000000002"])
    }

    // Spec: Membership indexes — Build file listed in no phase (rule M1's input).
    func testBuildFileInNoPhaseIsReportedWithoutPhaseOrTarget() throws {
        let project = try loadProject("model/broken.pbxproj")
        let report = project.membership(of: "AA0000000000000000000100")
        XCTAssertEqual(report.buildFiles.map(\.buildFile.id), ["BB0000000000000000000020"])
        XCTAssertEqual(report.buildFiles.first?.phases.count, 0)
        XCTAssertEqual(report.targets, [])
        XCTAssertEqual(report.parents, [], "and it is an orphan (rule M3's input)")
        XCTAssertEqual(project.phases(of: "BB0000000000000000000020"), [])
        XCTAssertEqual(project.buildFiles(for: "AA0000000000000000000100").map(\.id), ["BB0000000000000000000020"])
    }

    func testIndividualIndexes() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertEqual(project.buildFiles(for: "AA0000000000000000000110").map(\.id), ["BB0000000000000000000010"])
        XCTAssertEqual(project.buildFiles(for: "AA0000000000000000000201").map(\.id), ["BB0000000000000000000090"], "a variant group can be a fileRef")
        XCTAssertEqual(project.buildFiles(for: "AA0000000000000000000170"), [], "a product has no build file")
        XCTAssertEqual(project.phases(of: "BB0000000000000000000080").map(\.id), ["CC0000000000000000000002"])
        XCTAssertEqual(project.targets(owning: "CC0000000000000000000002").map(\.name), ["App"])
        XCTAssertEqual(project.targets(owning: "CC0000000000000000000006").map(\.name), ["AppExtension"])
        XCTAssertEqual(project.targets(owning: "AA0000000000000000000001"), [])
        XCTAssertEqual(project.parents(of: "AA0000000000000000000210").map(\.id), ["AA0000000000000000000201"], "a variant group is a parent")
        XCTAssertEqual(project.parents(of: "AA0000000000000000000301").map(\.id), ["AA0000000000000000000002"])
        XCTAssertEqual(project.membership(of: "nope").buildFiles, [])
    }

    func testMultiplicityIsData() throws {
        // One build file in two phases, one reference in two groups, a phase in two targets.
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; };
                G1 = {isa = PBXGroup; children = (F1, G2, ); sourceTree = "<group>"; };
                G2 = {isa = PBXGroup; children = (F1, ); path = Lib; sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = "x.c"; sourceTree = "<group>"; };
                B1 = {isa = PBXBuildFile; fileRef = F1; platformFilter = ios; };
                S1 = {isa = PBXSourcesBuildPhase; files = (B1, ); };
                S2 = {isa = PBXSourcesBuildPhase; files = (B1, B1, ); name = "Other Sources"; };
                T1 = {isa = PBXNativeTarget; name = A; buildPhases = (S1, S2, ); };
                T2 = {isa = PBXAggregateTarget; name = B; buildPhases = (S1, ); };
            }; rootObject = P1; }
            """
        let project = try Project.load(Array(source.utf8))
        XCTAssertEqual(project.parents(of: "F1").map(\.id), ["G1", "G2"])
        XCTAssertEqual(project.phases(of: "B1").map(\.id), ["S1", "S2", "S2"], "a phase listing the file twice reports it twice (rule S3)")
        XCTAssertEqual(project.targets(owning: "S1").map(\.id), ["T1", "T2"])
        let report = project.membership(of: "F1")
        XCTAssertEqual(report.buildFiles.first?.platformFilter, "ios")
        XCTAssertEqual(report.buildFiles.first?.phases.map(\.phase.displayName), ["Sources", "Other Sources", "Other Sources"])
        XCTAssertEqual(report.targets.map(\.id), ["T1", "T2"], "each target once, in object order")
    }

    func testIndexesAreRebuiltAfterAMutation() throws {
        var project = try loadProject("model/broken.pbxproj")
        XCTAssertEqual(project.parents(of: "AA0000000000000000000100"), [])
        XCTAssertEqual(project.fileReferences(at: "TVOS/Foo.swift"), [])
        try project.addChild("AA0000000000000000000100", to: "TVOSTEST00020")
        XCTAssertEqual(project.parents(of: "AA0000000000000000000100").map(\.id), ["TVOSTEST00020"])
        XCTAssertEqual(project.resolvedPath(of: "AA0000000000000000000100"), .relative("TVOS/Foo.swift"))
        XCTAssertEqual(project.fileReferences(at: "TVOS/Foo.swift").map(\.id), ["AA0000000000000000000100"])
        XCTAssertEqual(project.fileReferences(at: "Foo.swift"), [])
    }

    func testACopyTakenBeforeAMutationIsUnaffected() throws {
        var project = try loadProject("model/broken.pbxproj")
        let before = project
        try project.addChild("AA0000000000000000000100", to: "TVOSTEST00020")
        XCTAssertEqual(before.parents(of: "AA0000000000000000000100"), [])
        XCTAssertEqual(before.serialize(), try Fixtures.load("model/broken.pbxproj"))
        XCTAssertNotEqual(project.serialize(), before.serialize())
    }

    // Spec: Synchronized root groups are visible — Path inside a synchronized folder.
    func testPathInsideASynchronizedFolderIsCovered() throws {
        let project = try loadProject("model/app.pbxproj")
        let group = try XCTUnwrap(project.synchronizedRootGroup(covering: "App/Generated/Models/User.swift"))
        XCTAssertEqual(group.id, "AA0000000000000000000301")
        XCTAssertEqual(project.resolvedPath(of: group.id), .relative("App/Generated"))
        XCTAssertEqual(project.targets(synchronizing: group.id).map(\.name), ["App"])
        XCTAssertNotNil(project.synchronizedRootGroup(covering: "App/Generated/x.swift"))
        XCTAssertNotNil(project.synchronizedRootGroup(covering: "./App//Generated/../Generated/x.swift"))
        XCTAssertNil(project.synchronizedRootGroup(covering: "App/Generated"), "the folder itself is not a member")
        XCTAssertNil(project.synchronizedRootGroup(covering: "App/GeneratedX/y.swift"))
        XCTAssertNil(project.synchronizedRootGroup(covering: "App/Views/Foo.swift"))
        XCTAssertNil(project.synchronizedRootGroup(covering: "Generated/x.swift"))
    }
}
