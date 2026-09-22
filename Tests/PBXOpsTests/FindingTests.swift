import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Task 2.1: what a finding carries, and the order findings come out in.
final class FindingTests: XCTestCase {
    // Spec: Findings are identified and addressable — Finding for an ungrouped file.
    func testFindingForAnUngroupedFile() throws {
        let project = try loadProject("rules/m3-orphan.pbxproj")
        let findings = RuleSet.standard.evaluate(project)
        XCTAssertEqual(findings.count, 1, "\(findings)")
        let finding = try XCTUnwrap(findings.first)
        XCTAssertEqual(finding.rule, .M3)
        XCTAssertEqual(finding.severity, .error)
        XCTAssertEqual(finding.object, "AB12")
        XCTAssertEqual(finding.path, "AppTests/Views/FooTests.swift")
        XCTAssertEqual(finding.related, [])
        XCTAssertTrue(finding.message.contains("no parent group"), finding.message)
    }

    func testSeverityIsFixedPerRule() {
        XCTAssertEqual(RuleID.allCases.map(\.rawValue), ["S1", "S2", "S3", "S4", "S5", "M1", "M2", "M3", "M4", "M5", "M6", "D1", "D2"])
        for rule in RuleID.allCases {
            let expected: Severity = [.S5, .M6, .D1, .D2].contains(rule) ? .warning : .error
            XCTAssertEqual(rule.severity, expected, rule.rawValue)
        }
    }

    // Design D2: errors before warnings, then rule, object, path, message.
    func testFindingsAreOrderedDeterministically() {
        let unordered = [
            Finding(rule: .S5, object: "B", message: "z"),
            Finding(rule: .M3, object: "B", path: "b", message: "m"),
            Finding(rule: .D2, object: nil, path: "z/on/disk", message: "d"),
            Finding(rule: .M3, object: "A", path: "a", message: "m"),
            Finding(rule: .S2, object: "Z", related: ["DEAD"], message: "s"),
            Finding(rule: .M3, object: "A", path: "a", message: "l"),
            Finding(rule: .M6, object: "A", message: "w"),
            Finding(rule: .D2, object: nil, path: "a/on/disk", message: "d"),
        ]
        let expected = [
            Finding(rule: .S2, object: "Z", related: ["DEAD"], message: "s"),
            Finding(rule: .M3, object: "A", path: "a", message: "l"),
            Finding(rule: .M3, object: "A", path: "a", message: "m"),
            Finding(rule: .M3, object: "B", path: "b", message: "m"),
            Finding(rule: .S5, object: "B", message: "z"),
            Finding(rule: .M6, object: "A", message: "w"),
            Finding(rule: .D2, object: nil, path: "a/on/disk", message: "d"),
            Finding(rule: .D2, object: nil, path: "z/on/disk", message: "d"),
        ]
        XCTAssertEqual(RuleSet.ordered(unordered), expected)
        XCTAssertEqual(RuleSet.ordered(unordered.reversed()), expected)
    }

    func testObjectOrderIsByteOrderNotPrefixOrder() {
        // The order Xcode sorts sections by: "TVOSTEST0002" < "TVOSTEST00020".
        let findings = [
            Finding(rule: .M3, object: "TVOSTEST00020", message: "m"),
            Finding(rule: .M3, object: "TVOSTEST0002", message: "m"),
            Finding(rule: .M3, object: "a", message: "m"),
            Finding(rule: .M3, object: "Z", message: "m"),
        ]
        XCTAssertEqual(RuleSet.ordered(findings).map(\.object), ["TVOSTEST0002", "TVOSTEST00020", "Z", "a"])
    }
}
