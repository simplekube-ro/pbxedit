import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Tasks 2.1, 2.2 and 2.4: the pipeline of design D2 driven with hand-built
/// plans, on a project file in a temporary `.xcodeproj`.
final class OperationRunnerTests: XCTestCase {
    private var root: URL!
    private var pbxproj: URL!
    private var original: [UInt8] = []

    private let newRef: ObjectID = "0123456789ABCDEF01234567"
    private let newBuildFile: ObjectID = "0123456789ABCDEF01234569"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pbxedit-runner-\(UUID().uuidString)")
        let xcodeproj = root.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        pbxproj = xcodeproj.appendingPathComponent("project.pbxproj")
        original = try Fixtures.load("add/app.pbxproj")
        try Data(original).write(to: pbxproj)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func bytesOnDisk() throws -> [UInt8] { Array(try Data(contentsOf: pbxproj)) }

    private func leftovers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: pbxproj.deletingLastPathComponent().path).sorted()
    }

    /// A sound plan: `App/Views/Bar.swift` into `App`.
    private func goodPlan() -> Plan {
        Plan(
            steps: [
                .createFileReference(id: newRef, path: "Bar.swift", name: nil, sourceTree: "<group>", lastKnownFileType: "sourcecode.swift"),
                .addChild(newRef, to: "AA0000000000000000000003", position: .last),
                .createBuildFile(id: newBuildFile, fileRef: newRef, platformFilters: []),
                .addPhaseEntry(newBuildFile, to: "CC0000000000000000000001", position: .last),
            ],
            touched: [newRef, newBuildFile, "AA0000000000000000000003", "CC0000000000000000000001"])
    }

    /// A plan whose result violates M3 among the touched objects: a second
    /// parent for `Foo.swift`.
    private func badPlan() -> Plan {
        Plan(
            steps: [.addChild("AA0000000000000000000120", to: "AA0000000000000000000002", position: .last)],
            touched: ["AA0000000000000000000120", "AA0000000000000000000002"])
    }

    // Task 2.1: zero steps.
    func testAZeroStepPlanWritesNothing() throws {
        let past = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: pbxproj.path)
        let runner = try OperationRunner(projectFile: pbxproj)
        let result = runner.run(Plan(touched: ["AA0000000000000000000120"]), dryRun: false)
        XCTAssertEqual(result.outcome, .ok)
        XCTAssertFalse(result.modified)
        XCTAssertEqual(result.findings, [])
        XCTAssertEqual(try bytesOnDisk(), original)
        let modified = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: pbxproj.path)[.modificationDate] as? Date)
        XCTAssertEqual(modified.timeIntervalSince1970, past.timeIntervalSince1970, accuracy: 1, "not even rewritten with the same bytes")
        XCTAssertEqual(try leftovers(), ["project.pbxproj"])
    }

    // Task 2.1: the scoped check refuses.
    func testAPlanFailingTheScopedCheckWritesNothingAndReturnsTheFindings() throws {
        let runner = try OperationRunner(projectFile: pbxproj)
        let result = runner.run(badPlan(), dryRun: false)
        XCTAssertEqual(result.outcome, .violations(stage: .beforeWrite))
        XCTAssertFalse(result.modified)
        XCTAssertEqual(result.findings.map(\.rule), [.M3])
        XCTAssertEqual(result.findings.first?.object, "AA0000000000000000000120")
        XCTAssertEqual(try bytesOnDisk(), original)
        XCTAssertEqual(try leftovers(), ["project.pbxproj"])
    }

    // Task 2.1: success.
    func testASuccessfulPlanReplacesTheFile() throws {
        let runner = try OperationRunner(projectFile: pbxproj)
        let result = runner.run(goodPlan(), dryRun: false)
        XCTAssertEqual(result.outcome, .ok)
        XCTAssertTrue(result.modified)
        XCTAssertEqual(result.findings, [])
        let written = try bytesOnDisk()
        XCTAssertNotEqual(written, original)
        XCTAssertEqual(written, try XCTUnwrap(result.project).serialize(), "the result is what is on disk")
        let reloaded = try Project.load(written)
        XCTAssertEqual(reloaded.membership(of: newRef).targets.map(\.name), ["App"])
        XCTAssertEqual(reloaded.parents(of: newRef).map(\.id), ["AA0000000000000000000003"])
        assertOperationClean(reloaded, scope: goodPlan().touched)
        XCTAssertEqual(RuleSet.standard.evaluate(reloaded), [], "the fixture was clean and stays clean")
        XCTAssertEqual(try leftovers(), ["project.pbxproj"])
        XCTAssertNil(result.diff)
    }

    // Task 2.1: a step that cannot be applied is a failure, not a write.
    func testAnInapplicablePlanWritesNothing() throws {
        let runner = try OperationRunner(projectFile: pbxproj)
        let result = runner.run(Plan(steps: [.addChild(newRef, to: "NOPE", position: .last)], touched: [newRef]), dryRun: false)
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertFalse(result.modified)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(try bytesOnDisk(), original)
        XCTAssertEqual(try leftovers(), ["project.pbxproj"])
    }

    // Task 2.2: post-write verification failure restores the original bytes.
    func testAPostWriteVerificationFailureRestoresTheOriginalBytes() throws {
        var runner = try OperationRunner(projectFile: pbxproj)
        runner.postWriteRuleSet = RuleSet(rules: [AlwaysFailingRule()], diskRules: [])
        let result = runner.run(goodPlan(), dryRun: false)
        XCTAssertEqual(result.outcome, .violations(stage: .afterWrite))
        XCTAssertFalse(result.modified)
        XCTAssertEqual(result.findings.map(\.rule), [.S2])
        XCTAssertEqual(try bytesOnDisk(), original, "the original bytes are back")
        XCTAssertEqual(try leftovers(), ["project.pbxproj"])
    }

    // Task 2.4: dry run.
    func testADryRunProducesADiffAndWritesNothing() throws {
        let past = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: pbxproj.path)
        let runner = try OperationRunner(projectFile: pbxproj)
        let result = runner.run(goodPlan(), dryRun: true)
        XCTAssertEqual(result.outcome, .ok)
        XCTAssertFalse(result.modified)
        XCTAssertEqual(try bytesOnDisk(), original)
        let modified = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: pbxproj.path)[.modificationDate] as? Date)
        XCTAssertEqual(modified.timeIntervalSince1970, past.timeIntervalSince1970, accuracy: 1)
        let diff = try XCTUnwrap(result.diff)
        XCTAssertTrue(diff.hasPrefix("--- a/project.pbxproj\n+++ b/project.pbxproj\n@@ "), diff)
        XCTAssertTrue(diff.contains("+\t\t\(newBuildFile) /* Bar.swift in Sources */ = {isa = PBXBuildFile; fileRef = \(newRef) /* Bar.swift */; };\n"), diff)
        XCTAssertTrue(diff.contains("+\t\t\t\t\(newRef) /* Bar.swift */,\n"), diff)
        XCTAssertTrue(diff.contains("+\t\t\t\t\(newBuildFile) /* Bar.swift in Sources */,\n"), diff)
        XCTAssertFalse(diff.contains("\n-"), "nothing is removed: \(diff)")
        // The diff applies: every line of the new file is either context or added.
        let added = diff.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }
        XCTAssertEqual(added.count, 4)
        // A dry run of a refused plan has the outcome the real run would have.
        let refused = runner.run(badPlan(), dryRun: true)
        XCTAssertEqual(refused.outcome, .violations(stage: .beforeWrite))
        XCTAssertNil(refused.diff)
        // A dry run of a no-op has an empty diff.
        let noop = runner.run(Plan(), dryRun: true)
        XCTAssertEqual(noop.diff, "")
        XCTAssertEqual(try leftovers(), ["project.pbxproj"])
    }

    func testAProjectThatDoesNotLoadIsReportedByTheInitializer() throws {
        try Data(Fixtures.load("rules/s1-unterminated-comment.pbxproj")).write(to: pbxproj)
        XCTAssertThrowsError(try OperationRunner(projectFile: pbxproj)) { error in
            XCTAssertTrue("\(error)".contains("3:14"), "\(error)")
        }
    }
}

/// A rule that reports on every project, naming every object so that any
/// scope keeps it, to inject a verification failure.
struct AlwaysFailingRule: Rule {
    let id = RuleID.S2
    func evaluate(_ project: Project) -> [Finding] {
        [Finding(rule: .S2, object: project.rootObjectID, related: project.objects.map(\.id), message: "injected failure")]
    }
}
