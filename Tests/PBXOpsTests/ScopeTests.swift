import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Task 6.1: scoped evaluation (design D2).
final class ScopeTests: XCTestCase {
    /// A project with `orphans` ungrouped references and one correctly
    /// grouped, correctly built reference `F0` with build file `B0`.
    private func damaged(orphans: Int) throws -> Project {
        var objects = """
            P1 = {isa = PBXProject; mainGroup = G1; targets = (T1, ); };
            G1 = {isa = PBXGroup; children = (G2, ); sourceTree = "<group>"; };
            G2 = {isa = PBXGroup; children = (F0, ); path = App; sourceTree = "<group>"; };
            F0 = {isa = PBXFileReference; path = New.swift; sourceTree = "<group>"; };
            B0 = {isa = PBXBuildFile; fileRef = F0; };
            S1 = {isa = PBXSourcesBuildPhase; files = (B0, ); };
            T1 = {isa = PBXNativeTarget; name = App; buildPhases = (S1, ); };

            """
        for index in 1...orphans {
            objects += "F\(index) = {isa = PBXFileReference; path = Old\(index).swift; sourceTree = SOURCE_ROOT; };\n"
        }
        return try Project.load(Array("{ objects = {\n\(objects)}; rootObject = P1; }".utf8))
    }

    // Spec: Scoped evaluation — Unrelated damage is ignored.
    func testUnrelatedDamageIsIgnored() throws {
        let project = try damaged(orphans: 600)
        let all = RuleSet.standard.evaluate(project)
        XCTAssertEqual(all.count, 600)
        XCTAssertTrue(all.allSatisfy { $0.rule == .M3 })
        XCTAssertEqual(RuleSet.standard.evaluate(project, scope: ["F0", "B0"]), [])
    }

    func testAScopedObjectCollidingWithAnUnscopedOneIsReported() throws {
        // F0 is new and in scope; F1 (unscoped, pre-existing) resolves to the same path.
        var project = try damaged(orphans: 1)
        try project.setAttribute("path", of: "F1", to: .string("App/New.swift"))
        let scoped = RuleSet.standard.evaluate(project, scope: ["F0", "B0"])
        XCTAssertEqual(scoped.map(\.rule), [.M4], "\(scoped)")
        XCTAssertEqual(scoped.first?.object, "F1", "the finding is on the pre-existing reference")
        XCTAssertEqual(scoped.first?.related, ["F0"], "and it is kept because it names the scoped one")
        // The orphan's own M3 is not in scope.
        XCTAssertEqual(RuleSet.standard.evaluate(project).map(\.rule), [.M3, .M4])
    }

    func testAFindingWithNoObjectNeverMatchesAScope() throws {
        let source = "{ archiveVersion = \"1\"; objects = { P1 = {isa = PBXProject; mainGroup = G1; }; G1 = {isa = PBXGroup; children = (); }; }; rootObject = P1; }"
        let project = try Project.load(Array(source.utf8))
        XCTAssertEqual(RuleSet.standard.evaluate(project).map(\.rule), [.S5])
        XCTAssertEqual(RuleSet.standard.evaluate(project, scope: ["P1", "G1"]), [])
    }

    func testTheBytesFormAndTheProjectFormAgreeUnderAScope() throws {
        let project = try damaged(orphans: 3)
        let bytes = project.serialize()
        XCTAssertEqual(RuleSet.standard.evaluate(bytes: bytes, scope: ["F2"]).map(\.object), ["F2"])
        XCTAssertEqual(RuleSet.standard.evaluate(project, scope: ["F2"]).map(\.object), ["F2"])
    }
}
