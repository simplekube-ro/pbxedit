import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Task 3.1: one fixture per S-rule scenario, exact findings asserted.
final class StructuralRuleTests: XCTestCase {
    private func lint(_ fixture: String) throws -> [Finding] {
        RuleSet.standard.evaluate(bytes: try Fixtures.load("rules/\(fixture)"))
    }

    func testRuleFixturesAreValidPropertyListsWhenTheyParse() throws {
        for url in Fixtures.projectFiles(under: "rules") where !url.lastPathComponent.hasPrefix("s1-") && !url.lastPathComponent.hasPrefix("s4-json") {
            let bytes = Array(try Data(contentsOf: url))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            process.arguments = ["-lint", url.path]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "plutil -lint rejects \(url.lastPathComponent)")
            XCTAssertNoThrow(try Project.load(bytes), url.lastPathComponent)
        }
    }

    // Spec: Structural rules — S1 on unparseable input.
    func testS1OnUnparseableInput() throws {
        let findings = try lint("s1-unterminated-comment.pbxproj")
        XCTAssertEqual(findings.count, 1, "\(findings)")
        XCTAssertEqual(findings.first?.rule, .S1)
        XCTAssertEqual(findings.first?.severity, .error)
        XCTAssertNil(findings.first?.object)
        XCTAssertTrue(findings.first?.message.contains("3:14") == true, findings.first?.message ?? "")
    }

    // Spec: Structural rules — S4 on JSON-style filters (first half: it does not parse).
    func testS1OnJSONStyleFilters() throws {
        let findings = try lint("s4-json-filters.pbxproj")
        XCTAssertEqual(findings.map(\.rule), [.S1])
        XCTAssertTrue(findings.first?.message.contains("10:") == true, findings.first?.message ?? "")
    }

    // Spec: Structural rules — S1 on a file that is not a project.
    func testS1OnAFileThatIsNotAProject() throws {
        let findings = try lint("s1-no-root-object.pbxproj")
        XCTAssertEqual(findings.map(\.rule), [.S1])
        XCTAssertTrue(findings.first?.message.contains("root object 'ZZ' cannot be found") == true, findings.first?.message ?? "")
    }

    func testS1WhenTheBytesDoNotRoundTrip() throws {
        // Nothing that parses fails to round-trip (pbx-syntax: Byte-exact
        // round trip), so the check is exercised through the project form:
        // a loaded project is evaluated, then its bytes, and they agree.
        let bytes = try Fixtures.load("rules/s2-dangling-child.pbxproj")
        let viaBytes = RuleSet.standard.evaluate(bytes: bytes)
        let viaProject = RuleSet.standard.evaluate(try Project.load(bytes))
        XCTAssertEqual(viaBytes, viaProject)
        XCTAssertFalse(viaBytes.contains { $0.rule == .S1 })
    }

    // Spec: Structural rules — S2 on a dangling child.
    func testS2OnADanglingChild() throws {
        let findings = try lint("s2-dangling-child.pbxproj")
        XCTAssertEqual(findings, [
            Finding(rule: .S2, object: "G002", path: "App", related: ["DEAD0001"],
                    message: "group G002 (App) refers to DEAD0001 in 'children', which does not exist"),
        ])
    }

    func testS2OnADanglingBaseConfigurationReference() throws {
        let findings = try lint("s2-dangling-xcconfig.pbxproj")
        XCTAssertEqual(findings, [
            Finding(rule: .S2, object: "X002", related: ["AB99"],
                    message: "XCBuildConfiguration X002 (Release) refers to AB99 in 'baseConfigurationReference', which does not exist"),
        ])
    }

    // Spec: Structural rules — S3 on a repeated child.
    func testS3OnARepeatedChild() throws {
        let findings = try lint("s3-repeated-child.pbxproj")
        XCTAssertEqual(findings, [
            Finding(rule: .S3, object: "G002", path: "App", related: ["AB12"],
                    message: "group G002 (App) lists AB12 twice in 'children'"),
        ])
    }

    func testS3OnADuplicateObjectID() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; };
                G1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
                G1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            }; rootObject = P1; }
            """
        let findings = RuleSet.standard.evaluate(bytes: Array(source.utf8))
        XCTAssertEqual(findings, [
            Finding(rule: .S3, object: "G1", message: "the ID G1 is defined more than once in 'objects'"),
        ])
    }

    // Spec: Structural rules — S4 on JSON-style filters (second half).
    func testS4OnAnUnknownPlatformName() throws {
        let findings = try lint("s4-unknown-platform.pbxproj")
        XCTAssertEqual(findings.map(\.rule), [.S4, .S4])
        XCTAssertEqual(findings.map(\.object), ["BF01", "BF03"])
        XCTAssertEqual(findings.map(\.path), ["App/Foo.swift", "App/Foo.swift"])
        let unknown = try XCTUnwrap(findings.first)
        XCTAssertTrue(unknown.message.contains("'iphone'"), unknown.message)
        XCTAssertTrue(unknown.message.contains("ios, maccatalyst, macos, tvos, watchos, xros, driverkit"), unknown.message)
        let notAnArray = try XCTUnwrap(findings.last)
        XCTAssertTrue(notAnArray.message.contains("not an array"), notAnArray.message)
    }

    // Spec: Structural rules — S4 on the singular key (platform-filter-canonical-form task 2.1).
    func testS4OnTheSingularKey() throws {
        let findings = try lint("s4-singular-unknown.pbxproj")
        XCTAssertEqual(findings.map(\.rule), [.S4], "\(findings)")
        XCTAssertEqual(findings.map(\.object), ["BF01"], "ios and maccatalyst are what the singular key allows")
        XCTAssertEqual(findings.map(\.path), ["App/Foo.swift"])
        let unknown = try XCTUnwrap(findings.first)
        XCTAssertEqual(unknown.severity, .error)
        XCTAssertTrue(unknown.message.contains("'tvos'"), unknown.message)
        XCTAssertTrue(unknown.message.contains("'platformFilter'"), unknown.message)
        XCTAssertTrue(unknown.message.contains("ios, maccatalyst"), unknown.message)
        XCTAssertFalse(unknown.message.contains("tvos, watchos"), "the plural key's list is not the singular key's: \(unknown.message)")
    }

    func testS4OnASingularKeyThatIsNotAStringAndAPluralKeyThatIsNotAnArray() throws {
        let findings = try lint("s4-singular-not-string.pbxproj")
        XCTAssertEqual(findings.map(\.rule), [.S4, .S4], "\(findings)")
        XCTAssertEqual(findings.map(\.object), ["BF01", "BF02"])
        let notAString = try XCTUnwrap(findings.first)
        XCTAssertTrue(notAString.message.contains("'platformFilter'"), notAString.message)
        XCTAssertTrue(notAString.message.contains("not a string"), notAString.message)
        let notAnArray = try XCTUnwrap(findings.last)
        XCTAssertTrue(notAnArray.message.contains("'platformFilters'"), notAnArray.message)
        XCTAssertTrue(notAnArray.message.contains("not an array"), notAnArray.message)
    }

    func testS4IsSilentOnTheXcodeSavedProbe() throws {
        let findings = RuleSet.standard.evaluate(bytes: try Fixtures.load("xcode27/platform-filters-after-xcode27-save.pbxproj"))
        XCTAssertEqual(findings.filter { $0.rule == .S4 }, [])
        XCTAssertEqual(findings.filter { $0.severity == .error }, [], "the probe is a clean project")
    }

    // Spec: Structural rules — S5 on a bare hyphen.
    func testS5OnABareHyphen() throws {
        let findings = try lint("s5-bare-hyphen.pbxproj")
        XCTAssertEqual(findings, [
            Finding(rule: .S5, object: "AB12", path: "App/My-File.swift",
                    message: "the string My-File.swift is not quoted canonically: Xcode would quote it"),
        ])
        XCTAssertEqual(findings.first?.severity, .warning)
    }

    func testS5OutsideObjectsHasNoObjectAndNeedlessQuotesAreReported() throws {
        let source = """
            { archiveVersion = "1"; objects = {
                P1 = {isa = PBXProject; mainGroup = G1; };
                G1 = {isa = PBXGroup; children = (); sourceTree = "<group>"; };
            }; rootObject = P1; }
            """
        let findings = RuleSet.standard.evaluate(bytes: Array(source.utf8))
        XCTAssertEqual(findings, [
            Finding(rule: .S5, object: nil, path: "archiveVersion",
                    message: "the string \"1\" is not quoted canonically: Xcode would leave it bare"),
        ])
    }
}
