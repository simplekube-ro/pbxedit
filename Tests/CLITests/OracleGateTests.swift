import XCTest

/// release-distribution task 3.1 (design D3): the decision behind the oracle
/// lane's skip-or-fail, testable on a machine with or without Xcode. The
/// observable behaviour (a skipped versus a failed `OracleTests` run) can
/// only be seen where `xcodebuild` is missing; see the change's design.md.
final class OracleGateTests: XCTestCase {
    func testWithXcodebuildTheSuiteRunsWhateverTheVariableSays() {
        for required in [nil, "", "1", "true", "0"] {
            XCTAssertEqual(OracleTests.gate(xcodebuildAvailable: true, required: required), .run, "ORACLE_REQUIRED=\(required.debugDescription)")
        }
    }

    func testWithoutXcodebuildTheSuiteSkipsUnlessRequired() {
        XCTAssertEqual(OracleTests.gate(xcodebuildAvailable: false, required: nil), .skip)
        XCTAssertEqual(OracleTests.gate(xcodebuildAvailable: false, required: ""), .skip)
    }

    func testWithoutXcodebuildAndRequiredTheSuiteFails() {
        for required in ["1", "true", "0", "yes"] {
            XCTAssertEqual(OracleTests.gate(xcodebuildAvailable: false, required: required), .fail, "ORACLE_REQUIRED=\(required)")
        }
    }

    func testTheVariableIsTheDocumentedOne() {
        XCTAssertEqual(OracleTests.requiredVariable, "ORACLE_REQUIRED")
    }
}
