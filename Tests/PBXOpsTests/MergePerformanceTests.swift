import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command task 7.4: a synthetic three-way merge on the largest corpus
/// file — a file added on each side and one conflicting setting — run to
/// the decisions report and again, decided, to the verified result. The
/// class name matches CI's release-mode `--filter PerformanceTests`.
final class MergePerformanceTests: XCTestCase {
    /// The budget of task 7.4, in a release build.
    static let releaseLimit: TimeInterval = 2.0
    /// Debug builds only guard against a blow-up.
    static let debugLimit: TimeInterval = 30

    func testAThreeWayMergeOfTheLargestCorpusFile() throws {
        let sized = try Corpus.committedFiles().map { ($0, try Corpus.load($0).count) }
        let file = try XCTUnwrap(sized.max { $0.1 < $1.1 }?.0)
        let bytes = try Corpus.load(file)
        let base = try Project.load(bytes)
        let snapshot = MembershipSnapshot(base)
        // A source some target builds, and a configuration to disagree about.
        let sibling = try XCTUnwrap(snapshot.paths.compactMap { snapshot.references[$0] }.first { reference in
            reference.rows.contains { $0.phase == .sources } && reference.resolvedPath.contains("/")
        })
        let target = try XCTUnwrap(sibling.rows.first { $0.phase == .sources }?.target)
        let directory = String(sibling.resolvedPath[..<(sibling.resolvedPath.lastIndex(of: "/") ?? sibling.resolvedPath.endIndex)])
        let configuration = try XCTUnwrap(base.objects.first { $0.isa == "XCBuildConfiguration" && $0.attributes?["buildSettings"]?.dictionary != nil }?.id)

        let ours = try MergeFixture.setting("MERGE_PROBE", "ours", in: configuration,
                                            of: try MergeFixture.add(["\(directory)/MergeOurs.swift"], to: base, targets: [target], seed: 1))
        let theirs = try MergeFixture.setting("MERGE_PROBE", "theirs", in: configuration,
                                              of: try MergeFixture.add(["\(directory)/MergeTheirs.swift"], to: base, targets: [target], seed: 2))
        let (oursBytes, theirsBytes) = (ours.serialize(), theirs.serialize())

        let started = Date()
        let open = MergeEngine().run(base: bytes, ours: oursBytes, theirs: theirsBytes)
        let reported = Date()
        XCTAssertEqual(open.status, .decisionsNeeded, open.error ?? "")
        XCTAssertEqual(open.hunks.count, 1)
        let decisions = try MergeFixture.decide(open, hunks: { _ in "theirs" })
        let decidedStarted = Date()
        let report = MergeEngine(decisions: decisions).run(base: bytes, ours: oursBytes, theirs: theirsBytes)
        let finished = Date()
        XCTAssertEqual(report.status, .merged, report.error ?? "\(report.checks.filter { !$0.passed })")
        let result = try Project.load(try XCTUnwrap(report.result))
        XCTAssertEqual(result.fileReferences(at: "\(directory)/MergeOurs.swift").count, 1)
        XCTAssertEqual(result.fileReferences(at: "\(directory)/MergeTheirs.swift").count, 1)
        XCTAssertEqual(PlistLeaves(result)[["objects", configuration.rawValue, "buildSettings", "MERGE_PROBE"]], .string("theirs"))

        #if DEBUG
        let configurationName = "debug"
        let limit = MergePerformanceTests.debugLimit
        #else
        let configurationName = "release"
        let limit = MergePerformanceTests.releaseLimit
        #endif
        let seconds = { (from: Date, to: Date) in String(format: "%.3f", to.timeIntervalSince(from)) }
        print("SCALE \(configurationName) merge \(file.name) bytes=\(bytes.count) objects=\(base.objects.count) "
            + "report=\(seconds(started, reported))s decided=\(seconds(decidedStarted, finished))s")
        XCTAssertLessThan(finished.timeIntervalSince(decidedStarted), limit, "the decided merge, checks included (\(configurationName) build)")
        XCTAssertLessThan(reported.timeIntervalSince(started), limit, "the decisions report (\(configurationName) build)")
    }
}
