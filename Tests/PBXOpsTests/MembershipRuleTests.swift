import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Task 4.1: one fixture per M-rule scenario, exact findings asserted.
final class MembershipRuleTests: XCTestCase {
    private func lint(_ fixture: String) throws -> [Finding] {
        RuleSet.standard.evaluate(bytes: try Fixtures.load("rules/\(fixture)"))
    }

    private func lint(source: String) -> [Finding] {
        RuleSet.standard.evaluate(bytes: Array(source.utf8))
    }

    // Spec: Membership rules — M1 on a build file that never builds.
    func testM1OnABuildFileInNoPhase() throws {
        let findings = try lint("m1-no-phase.pbxproj")
        XCTAssertEqual(findings, [
            Finding(rule: .M1, object: "BF01", path: "AppTests/FooTests.swift", related: ["AB12"],
                    message: "build file BF01 (AppTests/FooTests.swift) is listed in no build phase"),
        ])
    }

    func testM1OnABuildFileInTwoPhases() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; targets = (T1, ); };
                G1 = {isa = PBXGroup; children = (F1, ); sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = x.c; sourceTree = "<group>"; };
                B1 = {isa = PBXBuildFile; fileRef = F1; };
                S1 = {isa = PBXSourcesBuildPhase; files = (B1, ); };
                S2 = {isa = PBXSourcesBuildPhase; files = (B1, ); };
                T1 = {isa = PBXNativeTarget; name = A; buildPhases = (S1, S2, ); };
            }; rootObject = P1; }
            """
        XCTAssertEqual(lint(source: source), [
            Finding(rule: .M1, object: "B1", path: "x.c", related: ["F1", "S1", "S2"],
                    message: "build file B1 (x.c) is listed in 2 build phases: S1, S2"),
        ])
    }

    // Spec: Membership rules — M2 (a dangling entry, and a build file whose file is gone).
    func testM2OnADanglingEntryAndOnAnUnresolvedFileRef() throws {
        let findings = try lint("m2-dangling-entry.pbxproj")
        XCTAssertEqual(findings, [
            Finding(rule: .S2, object: "BF01", related: ["AB99"],
                    message: "build file BF01 (AB99) refers to AB99 in 'fileRef', which does not exist"),
            Finding(rule: .S2, object: "S001", related: ["DEAD0001"],
                    message: "build phase S001 (Sources) refers to DEAD0001 in 'files', which does not exist"),
            Finding(rule: .M2, object: "BF01", related: ["AB99", "S001"],
                    message: "build file BF01 in build phase S001 (Sources) has a 'fileRef' AB99 that does not resolve"),
            Finding(rule: .M2, object: "S001", related: ["DEAD0001"],
                    message: "build phase S001 (Sources) lists DEAD0001, which is not a build file"),
        ])
    }

    func testM2OnAnEntryThatIsNotABuildFile() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; targets = (T1, ); };
                G1 = {isa = PBXGroup; children = (F1, ); sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = x.c; sourceTree = "<group>"; };
                S1 = {isa = PBXSourcesBuildPhase; files = (F1, ); };
                T1 = {isa = PBXNativeTarget; name = A; buildPhases = (S1, ); };
            }; rootObject = P1; }
            """
        XCTAssertEqual(lint(source: source), [
            Finding(rule: .M2, object: "S1", related: ["F1"],
                    message: "build phase S1 (Sources) lists F1, which is not a build file"),
        ])
    }

    // Spec: Membership rules — M3 exemption for products (m3-orphan holds
    // App.app in the Products group only, and FindingTests asserts the one
    // finding is the orphan). Here: a reference in two groups.
    func testM3OnAReferenceInTwoGroups() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; targets = (); };
                G1 = {isa = PBXGroup; children = (F1, G2, ); sourceTree = "<group>"; };
                G2 = {isa = PBXGroup; children = (F1, ); path = Lib; sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = x.c; sourceTree = "<group>"; };
            }; rootObject = P1; }
            """
        XCTAssertEqual(lint(source: source), [
            Finding(rule: .M3, object: "F1", path: "x.c", related: ["G1", "G2"],
                    message: "file reference F1 (x.c) has 2 parent groups: G1, G2"),
        ])
    }

    func testM3ExemptsProductsEvenWhenUngrouped() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; targets = (T1, ); };
                G1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
                T1 = {isa = PBXNativeTarget; name = App; buildPhases = (); productReference = F1; };
            }; rootObject = P1; }
            """
        XCTAssertEqual(lint(source: source), [], "tuist's ProjectWithoutProductsGroup is this shape")
    }

    // Spec: Membership rules — M4 on a duplicate reference.
    func testM4OnADuplicateReference() throws {
        let findings = try lint("m4-duplicate-reference.pbxproj")
        XCTAssertEqual(findings, [
            Finding(rule: .M4, object: "AB13", path: "App/Foo.swift", related: ["AB12"],
                    message: "file reference AB13 resolves to App/Foo.swift, the same path as AB12"),
        ])
    }

    func testM4IgnoresReferencesThatAreNotProjectRelative() throws {
        // Two targets, two SDK references to the same framework: what Xcode writes.
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; targets = (); };
                G1 = {isa = PBXGroup; children = (F1, F2, ); sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; name = Foundation.framework; path = System/Library/Frameworks/Foundation.framework; sourceTree = SDKROOT; };
                F2 = {isa = PBXFileReference; name = Foundation.framework; path = System/Library/Frameworks/Foundation.framework; sourceTree = SDKROOT; };
            }; rootObject = P1; }
            """
        XCTAssertEqual(lint(source: source), [])
    }

    // Spec: Membership rules — M5 on a double add.
    func testM5OnADoubleAdd() throws {
        let findings = try lint("m5-double-add.pbxproj")
        XCTAssertEqual(findings, [
            Finding(rule: .M5, object: "BF02", path: "App/Foo.swift", related: ["BF01", "AB12", "S001"],
                    message: "build file BF02 shares file reference AB12 (App/Foo.swift) with BF01 in build phase S001 (Sources)"),
        ])
    }

    func testM5AllowsTheSameFileInDifferentPhasesOfDifferentTargets() throws {
        XCTAssertEqual(RuleSet.standard.evaluate(try loadProject("model/app.pbxproj")).filter { $0.rule == .M5 }, [])
    }

    // Spec: Membership rules — M6 on a file in the wrong target.
    func testM6OnAFileInTheWrongTarget() throws {
        let findings = try lint("m6-wrong-target.pbxproj")
        XCTAssertEqual(findings, [
            Finding(rule: .M6, object: "BF10", path: "AppSlowTests/Foo.swift", related: ["AB10", "T001", "T002"],
                    message: "AppSlowTests/Foo.swift is in the Sources phase of target T001 (App), but AppSlowTests/ is the root of target T002 (AppSlowTests)"),
        ])
        XCTAssertEqual(findings.first?.severity, .warning)
    }

    // Spec: Membership rules — Shared sources are not M6.
    func testM6IsSilentOnSharedSources() throws {
        XCTAssertEqual(try lint("m6-shared-sources.pbxproj"), [])
    }

    func testM6IsSilentWhenNoTargetOwnsTheDirectory() throws {
        // App/ holds files of App and AppExtension in a 3:2 split: nobody's root.
        XCTAssertEqual(RuleSet.standard.evaluate(try loadProject("model/app.pbxproj")).filter { $0.rule == .M6 }, [])
    }

    func testRuleFixturesAreValidPropertyLists() throws {
        for url in Fixtures.projectFiles(under: "rules") where url.lastPathComponent.hasPrefix("m") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            process.arguments = ["-lint", url.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "plutil -lint rejects \(url.lastPathComponent)")
        }
    }
}
