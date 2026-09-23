import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 6.1–6.4: checks A–F (design D9) on synthesised
/// results, each paired with the rule set passing on the same result, so
/// the check is what catches it.
final class MergeCheckTests: XCTestCase {
    private let a1: ObjectID = "1000000000000000000000A1"
    private let a2: ObjectID = "1000000000000000000000A2"
    private let a3: ObjectID = "1000000000000000000000A3"
    private let a4: ObjectID = "1000000000000000000000A4"

    private func errors(_ project: Project) -> [Finding] {
        RuleSet.standard.evaluate(project).filter { $0.severity == .error }
    }

    private func accounting(ours: Project, theirs: Project, result: Project, hunks: [DecidedHunk] = [], faults: MergeFaults = []) throws -> CheckResult {
        let base = try MergeFixture.base()
        return MergeChecks.accounting(base: base, ours: ours, theirs: theirs, result: result, hunks: hunks, faults: faults)
    }

    /// The text merge, every hunk resolved by `choose`.
    private func textMerge(ours: Project, theirs: Project, choose: (AnalysedHunk) -> HunkChoice = { _ in .ours }) throws -> (Project, [DecidedHunk]) {
        let base = try MergeFixture.base()
        let merge = ThreeWay.merge(base: TextLines.split(base.serialize()), ours: TextLines.split(ours.serialize()),
                                   theirs: TextLines.split(theirs.serialize()))
        let decided = try AnalysedHunk.analyse(merge, sides: AnalysedHunk.Sides(ours: ours, theirs: theirs))
            .map { DecidedHunk(hunk: $0, choice: choose($0)) }
        let text = merge.text { index, _ in decided[index].hunk.resolution(decided[index].choice) }
        return (try Project.load(text), decided)
    }

    // MARK: C

    // Spec: A lost setting fails accounting (the text merge replaced by ours, as the `skipTextMerge` fault does).
    func testALostSettingFailsAccounting() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.setting("PRODUCT_NAME", "Renamed", in: a4, of: base)
        let check = try accounting(ours: base, theirs: theirs, result: base)
        XCTAssertFalse(check.passed)
        XCTAssertEqual(check.check, .C)
        XCTAssertEqual(check.problems.map(\.subject), ["1000000000000000000000A4 buildSettings.PRODUCT_NAME"])
        XCTAssertEqual(check.problems.first?.object, a4)
        XCTAssertEqual(errors(base), [], "lint alone reports nothing")
    }

    // Spec: A value in the wrong configuration fails accounting.
    func testAValueInTheWrongConfigurationFails() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a2, of: base)
        let wrong = try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a3, of: base)
        let check = try accounting(ours: base, theirs: theirs, result: wrong)
        XCTAssertEqual(Set(check.problems.map(\.subject)),
                       ["1000000000000000000000A2 buildSettings.SWIFT_VERSION", "1000000000000000000000A3 buildSettings.SWIFT_VERSION"])
        XCTAssertEqual(errors(wrong), [])
    }

    // Spec: A lost reorder fails accounting.
    func testALostReorderFails() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.attribute("buildPhases", .array([
            base.reference(to: "CC0000000000000000000001"), base.reference(to: "CC0000000000000000000003"),
            base.reference(to: "CC0000000000000000000002"),
        ]), of: "DD0000000000000000000001", in: base)
        let check = try accounting(ours: base, theirs: theirs, result: base)
        XCTAssertEqual(check.problems.map(\.subject), ["DD0000000000000000000001 buildPhases"])
        XCTAssertEqual(errors(base), [])
        // The `multisetArrays` fault compares arrays without order, and the probe goes red.
        XCTAssertTrue(try accounting(ours: base, theirs: theirs, result: base, faults: .multisetArrays).passed,
                      "without order the lost reorder passes: the order rule is what catches it")
    }

    func testAnIdenticalChangeOnBothSidesPasses() throws {
        let base = try MergeFixture.base()
        let both = try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a1, of: base)
        XCTAssertTrue(try accounting(ours: both, theirs: both, result: both).passed)
    }

    func testTwoDifferentSettingsInOneBuildSettingsPass() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: base)
        let theirs = try MergeFixture.setting("SDKROOT", "macosx", in: a1, of: base)
        let (result, hunks) = try textMerge(ours: ours, theirs: theirs)
        XCTAssertEqual(hunks, [])
        let check = try accounting(ours: ours, theirs: theirs, result: result)
        XCTAssertTrue(check.passed, "\(check.problems)")
        // The `wholeDictionaryLeaves` fault: `buildSettings` is one leaf, both changed it, nothing governs it.
        let whole = try accounting(ours: ours, theirs: theirs, result: result, faults: .wholeDictionaryLeaves)
        XCTAssertEqual(whole.problems.map(\.subject), ["1000000000000000000000A1 buildSettings"])
    }

    func testADecidedHunkExpectsTheDecidedSide() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: base)
        let theirs = try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a1, of: base)
        let (result, hunks) = try textMerge(ours: ours, theirs: theirs) { _ in .theirs }
        XCTAssertEqual(hunks.count, 1)
        XCTAssertTrue(try accounting(ours: ours, theirs: theirs, result: result, hunks: hunks).passed)
        let mislabelled = hunks.map { DecidedHunk(hunk: $0.hunk, choice: .ours) }
        XCTAssertEqual(try accounting(ours: ours, theirs: theirs, result: result, hunks: mislabelled).problems.map(\.subject),
                       ["1000000000000000000000A1 buildSettings.SWIFT_VERSION"])
        XCTAssertFalse(try accounting(ours: ours, theirs: theirs, result: result).passed, "both changed it and no hunk decides it")
    }

    /// Theirs deletes an object ours edited: the hunk decided `ours` keeps
    /// the whole object, including the leaves only theirs changed.
    func testADecidedHunkGovernsLeavesOnlyOneSideChanged() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: base)
        var theirs = base
        try theirs.setAttribute("buildConfigurations", of: "FF0000000000000000000001", to: .array([]))
        try theirs.deleteObject(a1)
        let (kept, hunks) = try textMerge(ours: ours, theirs: theirs) { _ in .ours }
        XCTAssertFalse(hunks.isEmpty)
        XCTAssertTrue(hunks.contains { $0.hunk.governed.contains(["objects", a1.rawValue, "isa"]) }, "\(hunks.map(\.hunk.governed))")
        XCTAssertTrue(try accounting(ours: ours, theirs: theirs, result: kept, hunks: hunks).passed)
    }

    func testAnArrayBothSidesChangedKeepsEverythingInEachSidesOrder() throws {
        let base = try MergeFixture.base()
        let known = { (values: [String]) in NewValue.array(values.map { .string($0) }) }
        let ours = try MergeFixture.attribute("knownRegions", known(["en", "Base", "fr"]), of: "EE0000000000000000000001", in: base)
        let theirs = try MergeFixture.attribute("knownRegions", known(["de", "en", "Base"]), of: "EE0000000000000000000001", in: base)
        let good = try MergeFixture.attribute("knownRegions", known(["de", "en", "Base", "fr"]), of: "EE0000000000000000000001", in: base)
        XCTAssertTrue(try accounting(ours: ours, theirs: theirs, result: good).passed)
        let lost = try MergeFixture.attribute("knownRegions", known(["en", "Base", "fr"]), of: "EE0000000000000000000001", in: base)
        XCTAssertEqual(try accounting(ours: ours, theirs: theirs, result: lost).problems.map(\.subject), ["EE0000000000000000000001 knownRegions"])
        let reordered = try MergeFixture.attribute("knownRegions", known(["de", "Base", "en", "fr"]), of: "EE0000000000000000000001", in: base)
        XCTAssertFalse(try accounting(ours: ours, theirs: theirs, result: reordered).passed, "ours' en before Base is lost")
    }

    /// Issue #12: the head and the tail of `knownRegions` are two hunks.
    /// Decided `theirs`/`theirs`, the text merge is theirs' array; a result
    /// that loses an element, keeps the wrong one or breaks an order still fails.
    func testTwoDecidedHunksOverOneArrayExpectBothDecisions() throws {
        let (ours, theirs) = try MergeEngineTests.sharedArraySides()
        let known = { (values: [String]) in NewValue.array(values.map { .string($0) }) }
        let project: ObjectID = "EE0000000000000000000001"
        let regions: LeafPath = ["objects", project.rawValue, "knownRegions"]
        let (result, hunks) = try textMerge(ours: ours, theirs: theirs) { $0.governed.contains(regions) ? .theirs : .ours }
        XCTAssertEqual(hunks.filter { $0.hunk.governed.contains(regions) }.count, 2)
        XCTAssertEqual(PlistLeaves(result)[regions], .array(["fr", "en", "Base", "es"].map { .string($0) }))
        XCTAssertTrue(try accounting(ours: ours, theirs: theirs, result: result, hunks: hunks).passed)
        for wrong in [["fr", "en", "Base"], ["fr", "en", "Base", "it"], ["de", "en", "Base", "es"], ["en", "fr", "Base", "es"]] {
            let bad = try MergeFixture.attribute("knownRegions", known(wrong), of: project, in: result)
            XCTAssertEqual(try accounting(ours: ours, theirs: theirs, result: bad, hunks: hunks).problems.map(\.subject),
                           ["EE0000000000000000000001 knownRegions"], "\(wrong)")
            XCTAssertEqual(errors(bad), [], "lint alone reports nothing")
        }
        // The `multisetArrays` fault: without order, the reordered result passes.
        let reordered = try MergeFixture.attribute("knownRegions", known(["en", "fr", "Base", "es"]), of: project, in: result)
        XCTAssertTrue(try accounting(ours: ours, theirs: theirs, result: reordered, hunks: hunks, faults: .multisetArrays).passed)
    }

    /// A `both` hunk sharing the array with a decided one counts with its
    /// own counterfactual: both heads, then theirs' tail.
    func testABothHunkSharingAnArrayWithADecidedOneCounts() throws {
        let (ours, theirs) = try MergeEngineTests.sharedArraySides()
        let regions: LeafPath = ["objects", "EE0000000000000000000001", "knownRegions"]
        let (result, hunks) = try textMerge(ours: ours, theirs: theirs) { hunk in
            !hunk.governed.contains(regions) ? .ours : hunk.number == 1 ? .both : .theirs
        }
        XCTAssertEqual(PlistLeaves(result)[regions], .array(["de", "fr", "en", "Base", "es"].map { .string($0) }))
        XCTAssertTrue(try accounting(ours: ours, theirs: theirs, result: result, hunks: hunks).passed)
        let lost = try MergeFixture.attribute("knownRegions", .array(["fr", "en", "Base", "es"].map { .string($0) }),
                                              of: "EE0000000000000000000001", in: result)
        XCTAssertFalse(try accounting(ours: ours, theirs: theirs, result: lost, hunks: hunks).passed, "ours' de is lost")
    }

    // MARK: Engine seams

    private func engine(_ faults: MergeFaults = []) -> MergeEngine {
        var engine = MergeEngine()
        engine.faults = faults
        engine.minter = IDMinter(generator: SplitMix(seed: 77))
        return engine
    }

    private func merge(ours: Project, theirs: Project, faults: MergeFaults = []) throws -> MergeReport {
        engine(faults).run(base: try MergeFixture.baseBytes(), ours: ours.serialize(), theirs: theirs.serialize())
    }

    private func failed(_ report: MergeReport, file: StaticString = #filePath, line: UInt = #line) -> CheckResult? {
        XCTAssertEqual(report.status, .failed, "\(report.error ?? "") \(report.checks)", file: file, line: line)
        XCTAssertTrue(report.result == nil, "nothing to write", file: file, line: line)
        return report.checks.last
    }

    // Spec: A lost setting fails accounting — through the engine, with the text merge replaced by ours.
    func testTheSkipTextMergeFaultFailsAccountingInTheEngine() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.setting("PRODUCT_NAME", "Renamed", in: a4, of: base)
        XCTAssertEqual(try merge(ours: base, theirs: theirs).status, .merged)
        let check = failed(try merge(ours: base, theirs: theirs, faults: .skipTextMerge))
        XCTAssertEqual(check?.check, .C)
        XCTAssertEqual(check?.problems.map(\.subject), ["1000000000000000000000A4 buildSettings.PRODUCT_NAME"])
    }

    // Issue #12 through the engine: with the text merge replaced by ours,
    // the two decided hunks over `knownRegions` are what check C misses.
    func testTheSkipTextMergeFaultFailsAccountingOnASharedArray() throws {
        let (ours, theirs) = try MergeEngineTests.sharedArraySides()
        let open = try merge(ours: ours, theirs: theirs)
        let decisions = try MergeFixture.decide(open, hunks: { $0.analysed.number <= 2 ? "theirs" : "ours" })
        var decided = engine()
        decided.decisions = decisions
        XCTAssertEqual(decided.run(base: try MergeFixture.baseBytes(), ours: ours.serialize(), theirs: theirs.serialize()).status, .merged)
        decided.faults = .skipTextMerge
        let check = failed(decided.run(base: try MergeFixture.baseBytes(), ours: ours.serialize(), theirs: theirs.serialize()))
        XCTAssertEqual(check?.check, .C)
        XCTAssertEqual(check?.problems.map(\.subject), ["EE0000000000000000000001 knownRegions"])
    }

    // MARK: F

    // Spec: Membership smuggled as bytes fails.
    func testMembershipSmuggledAsBytesFails() throws {
        let base = try MergeFixture.base()
        let smuggled = try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"])
        let reference = try XCTUnwrap(MembershipSnapshot(smuggled).references["App/Services/New.swift"]?.id)
        let check = MergeChecks.noMembershipAsBytes(ours: MembershipSnapshot(base), result: MembershipSnapshot(smuggled))
        XCTAssertEqual(check.problems.map(\.object), [reference])
        XCTAssertTrue(check.problems[0].subject.contains("App/Services/New.swift"))
        XCTAssertEqual(errors(smuggled), [])
        XCTAssertTrue(MergeChecks.noMembershipAsBytes(ours: MembershipSnapshot(base), result: MembershipSnapshot(base)).passed)
    }

    func testWithoutStructuralDiscoveryAReferenceOnlyAddReachesTheResultAsBytes() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: base, phase: .notBuilt)
        XCTAssertEqual(try merge(ours: base, theirs: theirs).status, .merged)
        let check = failed(try merge(ours: base, theirs: theirs, faults: .skipStructuralDiscovery))
        XCTAssertEqual(check?.check, .F)
        XCTAssertEqual(check?.problems.count, 1)
        XCTAssertTrue(check?.problems.first?.subject.contains("App/Services/New.swift") == true, "\(check?.problems ?? [])")
    }

    // MARK: E

    // Spec: A replay that drops an attribute fails.
    func testAReplayThatDropsAnAttributeFails() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.attribute("fileEncoding", .string("4"), of: "AA0000000000000000000260", in: base)
        let detached = try MergeFixture.remove(["App/Filtered/F1.swift"], from: base, target: "App")
        let theirs = try MergeFixture.add(["App/Filtered/F1.swift"], to: detached, targets: ["App"], platforms: ["ios", "macos"])
        XCTAssertEqual(try merge(ours: ours, theirs: theirs).status, .merged)
        let check = failed(try merge(ours: ours, theirs: theirs, faults: .replayRemoveAll))
        XCTAssertEqual(check?.check, .E)
        let problem = try XCTUnwrap(check?.problems.first { $0.subject.hasSuffix("fileEncoding") }, "\(check?.problems ?? [])")
        XCTAssertEqual(problem.object, "AA0000000000000000000260")
    }

    // Spec: A conflict dropped from a unit's residuals fails (issue #20).
    func testAConflictDroppedFromAUnitsResidualsFails() throws {
        let sides = try MergeFixture.attributeConflict()
        XCTAssertEqual(try merge(ours: sides.ours, theirs: sides.theirs).status, .decisionsNeeded, "the conflict is asked about")
        let check = failed(try merge(ours: sides.ours, theirs: sides.theirs, faults: .ignoreAttributeConflicts))
        XCTAssertEqual(check?.check, .E)
        let problem = try XCTUnwrap(check?.problems.first { $0.subject.hasSuffix("fileEncoding") }, "\(check?.problems ?? [])")
        XCTAssertEqual(problem.object, "AA0000000000000000000260")
        XCTAssertTrue(problem.message.contains("both sides changed"), problem.message)
    }

    // MARK: D

    func testAReplayThatEditsAnUnrelatedPathFails() throws {
        let base = try MergeFixture.base()
        let replayed = try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"])
        XCTAssertTrue(MergeChecks.isolation(pre: base, result: replayed, replayedPaths: ["App/Services/New.swift"]).passed)
        let meddled = try MergeFixture.remove(["App/Views/Foo.swift"], from: replayed)
        let check = MergeChecks.isolation(pre: base, result: meddled, replayedPaths: ["App/Services/New.swift"])
        XCTAssertFalse(check.passed)
        XCTAssertTrue(check.problems.contains { $0.object == "AA0000000000000000000120" }, "\(check.problems)")
        XCTAssertEqual(errors(meddled), [])
    }

    // MARK: B

    func testARowDroppedFromAReplayedUnitFails() throws {
        let base = try MergeFixture.base()
        let theirs = try MergeFixture.add(["App/Services/New.swift"], to: base, targets: ["App"])
        let dropped = try MergeFixture.remove(["App/Services/New.swift"], from: theirs, target: "App")
        let paths: Set<String> = ["App/Services/New.swift"]
        XCTAssertTrue(MergeChecks.membership(ours: MembershipSnapshot(base), theirs: MembershipSnapshot(theirs), result: MembershipSnapshot(theirs),
                                             theirsPaths: paths, owed: []).passed)
        let check = MergeChecks.membership(ours: MembershipSnapshot(base), theirs: MembershipSnapshot(theirs), result: MembershipSnapshot(dropped),
                                           theirsPaths: paths, owed: [])
        XCTAssertEqual(check.problems.map(\.subject), ["target App"])
        XCTAssertTrue(check.problems[0].message.contains("App/Services/New.swift"))
        XCTAssertEqual(errors(dropped), [])
    }

    // MARK: A

    func testANewOrphanFailsAndAFindingOursHadPasses() throws {
        let base = try MergeFixture.base()
        var orphaned = base
        try orphaned.createObject("AB0000000000000000000030", isa: Kind.fileReference, attributes: [
            NewEntry("path", .string("Loose.swift")), NewEntry("sourceTree", .string("<group>")),
        ])
        let (check, new) = MergeChecks.findings(result: orphaned, ours: base, theirs: base, exemptions: nil)
        XCTAssertEqual(new.map(\.rule), [.M3])
        XCTAssertEqual(check.problems.map(\.object), ["AB0000000000000000000030"])
        XCTAssertEqual(RuleSet.standard.evaluate(base).map(\.rule), [.M6, .M6, .M6, .M6], "ours already has these")
        XCTAssertTrue(MergeChecks.findings(result: base, ours: base, theirs: base, exemptions: nil).check.passed)
    }
}
