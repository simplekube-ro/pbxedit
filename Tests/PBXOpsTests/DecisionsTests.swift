import CryptoKit
import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command task 7.2: the decisions round trip (design D10).
final class DecisionsTests: XCTestCase {
    private let a1: ObjectID = "1000000000000000000000A1"

    private func sha256(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Ours and theirs conflict on a setting and differ on one file.
    private func sides() throws -> (Project, Project) {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.remove(["App/Filtered/F1.swift"], from: try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: base))
        let theirs = try MergeFixture.move("App/Filtered/F1.swift", to: "App/Views/F1.swift",
                                           in: try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a1, of: base))
        return (ours, theirs)
    }

    func testTheTemplateIsBoundToTheInputs() throws {
        let (ours, theirs) = try sides()
        let report = try MergeFixture.merge(ours: ours, theirs: theirs)
        XCTAssertEqual(report.status, .decisionsNeeded)
        let template = try XCTUnwrap(report.template)
        XCTAssertEqual(template.inputs.base, sha256(try MergeFixture.baseBytes()))
        XCTAssertEqual(template.inputs.ours, sha256(ours.serialize()))
        XCTAssertEqual(template.inputs.theirs, sha256(theirs.serialize()))
        XCTAssertEqual(template.units.count, 1)
        XCTAssertEqual(template.hunks.count, 1)
        XCTAssertTrue(template.units.values.allSatisfy { $0 == nil })
        let json = String(decoding: try JSONEncoder().encode(template), as: UTF8.self)
        XCTAssertTrue(json.contains("\"\(report.units[0].key)\":null"), json)
        XCTAssertTrue(json.contains("\"\(report.hunks[0].key)\":null"), json)
        XCTAssertEqual(try MergeDecisions.decode(Data(json.utf8)), template, "the template decodes as a decisions file")
    }

    func testTemplateThenReRunMerges() throws {
        let (ours, theirs) = try sides()
        let open = try MergeFixture.merge(ours: ours, theirs: theirs)
        var decisions = try MergeFixture.decide(open, units: { _ in "ours" })
        let partial = try MergeFixture.merge(ours: ours, theirs: theirs, decisions: decisions)
        XCTAssertEqual(partial.status, .decisionsNeeded, "the hunk is still open")
        XCTAssertEqual(partial.template?.units.values.compactMap { $0 }, ["ours"], "decided choices stay in the template")
        decisions = try MergeFixture.decide(open, units: { _ in "ours" }, hunks: { _ in "theirs" })
        let report = try MergeFixture.merge(ours: ours, theirs: theirs, decisions: decisions)
        XCTAssertEqual(report.status, .merged, report.error ?? "\(report.checks)")
        XCTAssertEqual(report.hunks.map(\.decision), [.theirs])
        XCTAssertEqual(report.units.map(\.decision), [.ours])
        XCTAssertNil(report.template)
    }

    // Spec: Stale decisions.
    func testStaleInputsAreUnsupported() throws {
        let (ours, theirs) = try sides()
        var decisions = try MergeFixture.decide(try MergeFixture.merge(ours: ours, theirs: theirs), units: { _ in "ours" }, hunks: { _ in "ours" })
        decisions.inputs = MergeDecisions.Inputs(base: decisions.inputs.base, ours: String(repeating: "0", count: 64), theirs: decisions.inputs.theirs)
        let report = try MergeFixture.merge(ours: ours, theirs: theirs, decisions: decisions)
        XCTAssertEqual(report.status, .unsupported)
        XCTAssertTrue(report.error?.contains("for other inputs") == true, report.error ?? "")
        XCTAssertTrue(report.result == nil)
    }

    // Spec: Unknown key or refused choice.
    func testAnUnknownKeyIsUnsupported() throws {
        let (ours, theirs) = try sides()
        var decisions = try XCTUnwrap(try MergeFixture.merge(ours: ours, theirs: theirs).template)
        decisions.hunks["h000000000000"] = .some("ours")
        let report = try MergeFixture.merge(ours: ours, theirs: theirs, decisions: decisions)
        XCTAssertEqual(report.status, .unsupported)
        XCTAssertTrue(report.error?.contains("h000000000000") == true, report.error ?? "")
    }

    func testARefusedChoiceIsUnsupported() throws {
        let (ours, theirs) = try sides()
        let open = try MergeFixture.merge(ours: ours, theirs: theirs)
        let key = open.hunks[0].key
        let report = try MergeFixture.merge(ours: ours, theirs: theirs, decisions: try MergeFixture.decide(open, hunks: { _ in "both" }))
        XCTAssertEqual(report.status, .unsupported)
        XCTAssertTrue(report.error?.contains(key) == true && report.error?.contains("both") == true, report.error ?? "")
        let unit = try MergeFixture.merge(ours: ours, theirs: theirs, decisions: try MergeFixture.decide(open, units: { _ in "theirs-membership" }))
        XCTAssertEqual(unit.status, .unsupported, "theirs-membership is offered only with a residual")
    }

    func testADecisionForAReplayedUnitIsAnUnknownKey() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"])
        let replayed = try MergeFixture.merge(ours: base, theirs: theirs)
        XCTAssertEqual(replayed.units.map(\.classified.outcome), [.replayed])
        let key = replayed.units[0].key
        let decisions = MergeDecisions(inputs: replayed.inputs, units: [key: .some("theirs")])
        let report = try MergeFixture.merge(ours: base, theirs: theirs, decisions: decisions)
        XCTAssertEqual(report.status, .unsupported)
        XCTAssertEqual(report.error, MergeDecisionsError.unknownKey(key).description)
    }

    func testAMalformedFileSaysSo() {
        XCTAssertThrowsError(try MergeDecisions.decode(Data("{\"units\": {}}".utf8))) { error in
            guard case MergeDecisionsError.malformed = error else { return XCTFail("\(error)") }
        }
    }
}
