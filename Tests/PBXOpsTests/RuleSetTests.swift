import XCTest
@testable import PBXOps

/// The composition of the standard rule set: every rule once, S1 only as the
/// loading step of the bytes form, D1 and D2 only behind a reader.
final class RuleSetTests: XCTestCase {
    func testStandardRuleSetHoldsEveryRuleOnce() {
        XCTAssertEqual(RuleSet.standard.rules.map(\.id), [.S2, .S3, .S4, .S5, .M1, .M2, .M3, .M4, .M5, .M6])
        XCTAssertEqual(RuleSet.standard.diskRules.map(\.id), [.D1, .D2])
        let covered = Set(RuleSet.standard.rules.map(\.id) + RuleSet.standard.diskRules.map(\.id) + [.S1])
        XCTAssertEqual(covered, Set(RuleID.allCases))
    }
}
