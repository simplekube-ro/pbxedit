import Foundation
import XCTest
import PBXModel
@testable import PBXOps

/// Task 7.4: the baseline value (design D6), independent of the command.
final class BaselineTests: XCTestCase {
    func testEntriesAreKeyedByRuleAndObjectOrPath() {
        let findings = [
            Finding(rule: .M3, object: "B", path: "b.swift", message: "x"),
            Finding(rule: .M3, object: "A", path: "a.swift", message: "x"),
            Finding(rule: .S2, object: "G", related: ["DEAD1"], message: "x"),
            Finding(rule: .S2, object: "G", related: ["DEAD2"], message: "y"),
            Finding(rule: .D2, object: nil, path: "App/Loose.swift", message: "x"),
        ]
        let baseline = Baseline(findings: findings)
        XCTAssertEqual(baseline.entries, [
            Baseline.Entry(rule: "D2", object: "App/Loose.swift"),
            Baseline.Entry(rule: "M3", object: "A"),
            Baseline.Entry(rule: "M3", object: "B"),
            Baseline.Entry(rule: "S2", object: "G"),
        ], "sorted by rule then key; two findings with one key are one entry")
    }

    func testEncodingIsOneEntryPerLineAndDecodesBack() throws {
        let baseline = Baseline(entries: [Baseline.Entry(rule: "M3", object: "AB12"), Baseline.Entry(rule: "S5", object: "AB13")])
        let text = baseline.encoded()
        XCTAssertEqual(text, """
            {
              "schemaVersion": 1,
              "entries": [
                { "rule": "M3", "object": "AB12" },
                { "rule": "S5", "object": "AB13" }
              ]
            }

            """)
        XCTAssertEqual(try Baseline(data: Data(text.utf8)), baseline)
        XCTAssertEqual(try Baseline(data: Data("{\"schemaVersion\":1,\"entries\":[]}".utf8)).entries, [])
        XCTAssertThrowsError(try Baseline(data: Data("{\"schemaVersion\":2,\"entries\":[]}".utf8)))
        XCTAssertThrowsError(try Baseline(data: Data("nope".utf8)))
        XCTAssertEqual(Baseline(entries: []).encoded(), "{\n  \"schemaVersion\": 1,\n  \"entries\": [\n  ]\n}\n")
    }

    func testApplySplitsNewBaselinedAndResolved() {
        let baseline = Baseline(entries: [Baseline.Entry(rule: "M3", object: "A"), Baseline.Entry(rule: "M3", object: "GONE")])
        let findings = [
            Finding(rule: .M3, object: "A", message: "old"),
            Finding(rule: .M3, object: "B", message: "new"),
            Finding(rule: .S5, object: "A", message: "a different rule on a baselined object is new"),
        ]
        let result = baseline.apply(to: findings)
        XCTAssertEqual(result.findings.map(\.object), ["B", "A"])
        XCTAssertEqual(result.findings.map(\.rule), [.M3, .S5])
        XCTAssertEqual(result.baselined, 1)
        XCTAssertEqual(result.resolved, [Baseline.Entry(rule: "M3", object: "GONE")])
    }
}
