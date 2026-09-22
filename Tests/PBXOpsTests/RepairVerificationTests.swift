import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Task 2.1: `OperationRunner` in `.wholeProject(before:selected:)` mode
/// (integrity-repair design D5), on project files in a temporary `.xcodeproj`.
final class RepairVerificationTests: XCTestCase {
    private var root: URL!
    private var pbxproj: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pbxedit-repair-\(UUID().uuidString)")
        let xcodeproj = root.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        pbxproj = xcodeproj.appendingPathComponent("project.pbxproj")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ fixture: String) throws -> [UInt8] {
        let bytes = try Fixtures.load(fixture)
        try Data(bytes).write(to: pbxproj)
        return bytes
    }

    private func bytesOnDisk() throws -> [UInt8] { Array(try Data(contentsOf: pbxproj)) }

    private func leftovers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: pbxproj.deletingLastPathComponent().path).sorted()
    }

    // The repair fixture's plan passes: every selected finding vanishes, nothing appears,
    // and the S2 on the phase whose dangling entry went vanishes as a side effect.
    func testARepairWhoseSelectedFindingsVanishAndNothingAppearsIsWritten() throws {
        let original = try write("repair/app.pbxproj")
        let runner = try OperationRunner(projectFile: pbxproj)
        let before = RuleSet.standard.evaluate(runner.project)
        let repair = RepairPlanner.plan(before, in: runner.project)
        let result = runner.run(repair.plan, dryRun: false, verification: .wholeProject(before: before, selected: repair.repaired))
        XCTAssertEqual(result.outcome, .ok, "\(result.findings)")
        XCTAssertTrue(result.modified)
        XCTAssertEqual(result.findings, [])
        XCTAssertEqual(result.warnings, [], "no warning is among the touched objects' business in this mode; the report evaluates the result")
        XCTAssertNotEqual(try bytesOnDisk(), original)
        XCTAssertEqual(try leftovers(), ["project.pbxproj"])
        let after = RuleSet.standard.evaluate(try XCTUnwrap(result.project))
        for finding in repair.repaired {
            XCTAssertFalse(after.contains { $0.identity == finding.identity }, "\(finding) survived")
        }
        XCTAssertFalse(after.contains { $0.rule == .S2 && $0.object == "CC0000000000000000000007" }, "vanished as a side effect")
        XCTAssertTrue(after.contains { $0.rule == .S2 && $0.object == "AA0000000000000000000007" }, "the unrelated S2 stays")
        XCTAssertEqual(after.count, before.count - repair.repaired.count - 3, "the three S2s on repaired objects went with them")
    }

    // Spec: A repair would cause new damage — an M3 fix that plants an M4.
    func testARepairThatIntroducesAFindingWritesNothingAndNamesIt() throws {
        let original = try write("rules/m3-orphan.pbxproj")
        let runner = try OperationRunner(projectFile: pbxproj)
        let before = RuleSet.standard.evaluate(runner.project)
        XCTAssertEqual(before.map(\.rule), [.M3])
        let twin: ObjectID = "0123456789ABCDEF01234567"
        let plan = Plan(
            steps: [
                .addChild("AB12", to: "G002", position: .last),
                .createFileReference(id: twin, path: "AppTests/Views/FooTests.swift", name: "FooTests.swift", sourceTree: "SOURCE_ROOT", lastKnownFileType: "sourcecode.swift"),
                .addChild(twin, to: "G002", position: .last),
            ],
            touched: ["AB12", "G002", twin])
        let result = runner.run(plan, dryRun: false, verification: .wholeProject(before: before, selected: before))
        XCTAssertEqual(result.outcome, .violations(stage: .beforeWrite))
        XCTAssertFalse(result.modified)
        XCTAssertEqual(result.findings.map(\.rule), [.M4])
        XCTAssertEqual(result.findings.first?.object, "AB12", "M4 names the second reference in object order; the twin's ID sorts first")
        XCTAssertEqual(result.findings.first?.related, [twin])
        XCTAssertEqual(try bytesOnDisk(), original)
        XCTAssertEqual(try leftovers(), ["project.pbxproj"])
        // The same plan passes the scoped check the ordinary commands use — which is
        // exactly why a repair does not use it — so the mode, not the plan, is what refuses.
        XCTAssertEqual(runner.run(plan, dryRun: true, verification: .scoped).outcome, .violations(stage: .beforeWrite),
                       "here the M4 names a touched object; the scoped check catches this one too")
        let dryRun = runner.run(plan, dryRun: true, verification: .wholeProject(before: before, selected: before))
        XCTAssertEqual(dryRun.outcome, .violations(stage: .beforeWrite), "a dry run has the outcome the real run would have")
        XCTAssertNil(dryRun.diff)
    }

    // A selected finding that survives the plan is a violation even though nothing new appeared.
    func testASelectedFindingThatSurvivesIsAViolation() throws {
        let original = try write("rules/m3-orphan.pbxproj")
        let runner = try OperationRunner(projectFile: pbxproj)
        let before = RuleSet.standard.evaluate(runner.project)
        let result = runner.run(Plan(), dryRun: false, verification: .wholeProject(before: before, selected: before))
        XCTAssertEqual(result.outcome, .violations(stage: .beforeWrite))
        XCTAssertEqual(result.findings, before)
        XCTAssertFalse(result.modified)
        XCTAssertEqual(try bytesOnDisk(), original)
        // With nothing selected, the same no-op plan is fine: nothing survived that was selected, nothing appeared.
        let none = runner.run(Plan(), dryRun: false, verification: .wholeProject(before: before, selected: []))
        XCTAssertEqual(none.outcome, .ok)
        XCTAssertFalse(none.modified)
    }

    // Findings are compared by identity, so a message that changes is not a new finding.
    func testFindingsAreComparedByIdentityNotMessage() throws {
        let finding = Finding(rule: .M3, object: "AB12", path: "a", related: ["G1"], message: "one")
        let reworded = Finding(rule: .M3, object: "AB12", path: "b", related: ["G1"], message: "two")
        XCTAssertEqual(finding.identity, reworded.identity)
        XCTAssertNotEqual(finding.identity, Finding(rule: .M3, object: "AB12", related: ["G2"], message: "one").identity)
        XCTAssertNotEqual(finding.identity, Finding(rule: .M4, object: "AB12", related: ["G1"], message: "one").identity)
    }

    // The post-write check runs in the same mode: an injected finding on the bytes read back restores the original.
    func testThePostWriteCheckUsesTheSameModeAndRestoresOnFailure() throws {
        let original = try write("repair/app.pbxproj")
        var runner = try OperationRunner(projectFile: pbxproj)
        runner.postWriteRuleSet = RuleSet(rules: [AlwaysFailingRule()], diskRules: [])
        let before = RuleSet.standard.evaluate(runner.project)
        let repair = RepairPlanner.plan(before, in: runner.project)
        let result = runner.run(repair.plan, dryRun: false, verification: .wholeProject(before: before, selected: repair.repaired))
        XCTAssertEqual(result.outcome, .violations(stage: .afterWrite))
        XCTAssertFalse(result.modified)
        XCTAssertEqual(result.findings.map(\.rule), [.S2], "the injected finding was absent before")
        XCTAssertEqual(try bytesOnDisk(), original, "the original bytes are back")
        XCTAssertEqual(try leftovers(), ["project.pbxproj"])
    }

    // Exemptions are honoured on both sides of the comparison.
    func testExemptFindingsAreOutsideTheComparison() throws {
        _ = try write("repair/app.pbxproj")
        var runner = try OperationRunner(projectFile: pbxproj)
        let exemptions = Exemptions([.M3: [try PathGlob("Tools/Generated/**")]])
        runner.exemptions = exemptions
        let before = RuleSet.standard.evaluate(runner.project, exemptions: exemptions)
        XCTAssertFalse(before.contains { $0.object == "AA0000000000000000000413" })
        let repair = RepairPlanner.plan(before, in: runner.project, exemptions: exemptions)
        let result = runner.run(repair.plan, dryRun: false, verification: .wholeProject(before: before, selected: repair.repaired))
        XCTAssertEqual(result.outcome, .ok, "\(result.findings)")
        XCTAssertEqual(try XCTUnwrap(result.project).parents(of: "AA0000000000000000000413"), [], "the exempt orphan was left alone")
    }
}
