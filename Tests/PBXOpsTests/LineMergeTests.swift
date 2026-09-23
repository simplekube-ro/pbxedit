import XCTest
@testable import PBXOps

/// merge-command tasks 2.3–2.4: Myers' line diff and the three-way merge
/// into stable regions and hunks (design D6).
final class LineMergeTests: XCTestCase {
    /// One line per character, each ending in `\n`.
    private func lines(_ text: String) -> [[UInt8]] { text.map { Array("\($0)\n".utf8) } }

    private func merge(_ base: String, _ ours: String, _ theirs: String) -> [ThreeWay.Region] {
        ThreeWay.merge(base: lines(base), ours: lines(ours), theirs: lines(theirs)).regions
    }

    private func stable(_ text: String) -> ThreeWay.Region { .stable(lines(text)) }

    private func hunk(_ base: String, _ ours: String, _ theirs: String) -> ThreeWay.Region {
        .hunk(ThreeWay.Hunk(base: lines(base), ours: lines(ours), theirs: lines(theirs)))
    }

    // MARK: Lines

    func testLinesKeepTheirTerminators() {
        XCTAssertEqual(TextLines.split(Array("a\nb\n".utf8)), [Array("a\n".utf8), Array("b\n".utf8)])
        XCTAssertEqual(TextLines.split(Array("a\nb".utf8)), [Array("a\n".utf8), Array("b".utf8)])
        XCTAssertEqual(TextLines.split([]), [])
    }

    // MARK: Diff

    func testTheDiffOfSmallCases() {
        XCTAssertEqual(LineDiff.changes(from: lines("abc"), to: lines("axc")), [LineDiff.Change(base: 1..<2, other: 1..<2)])
        XCTAssertEqual(LineDiff.changes(from: lines("ac"), to: lines("abc")), [LineDiff.Change(base: 1..<1, other: 1..<2)])
        XCTAssertEqual(LineDiff.changes(from: lines("abc"), to: lines("ac")), [LineDiff.Change(base: 1..<2, other: 1..<1)])
        XCTAssertEqual(LineDiff.changes(from: lines(""), to: lines("ab")), [LineDiff.Change(base: 0..<0, other: 0..<2)])
        XCTAssertEqual(LineDiff.changes(from: lines("ab"), to: lines("")), [LineDiff.Change(base: 0..<2, other: 0..<0)])
        XCTAssertEqual(LineDiff.changes(from: lines("abcd"), to: lines("xbcy")),
                       [LineDiff.Change(base: 0..<1, other: 0..<1), LineDiff.Change(base: 3..<4, other: 3..<4)])
    }

    /// Myers' paper's example: the shortest edit script has five lines.
    func testTheDiffIsMinimal() {
        let changes = LineDiff.changes(from: lines("abcabba"), to: lines("cbabac"))
        let edits = changes.reduce(0) { $0 + $1.base.count + $1.other.count }
        XCTAssertEqual(edits, 5, "\(changes)")
    }

    func testTheBaseAgainstItselfIsEmpty() throws {
        let base = TextLines.split(try Fixtures.load(MergeFixture.basePath))
        XCTAssertEqual(LineDiff.changes(from: base, to: base), [])
    }

    // MARK: Regions

    func testUnchanged() {
        XCTAssertEqual(merge("abc", "abc", "abc"), [stable("abc")])
    }

    func testChangedByOneSide() {
        XCTAssertEqual(merge("abc", "axc", "abc"), [stable("axc")])
        XCTAssertEqual(merge("abc", "abc", "abyc"), [stable("abyc")])
    }

    func testChangedIdenticallyByBoth() {
        XCTAssertEqual(merge("abc", "axc", "axc"), [stable("axc")])
        XCTAssertEqual(merge("ac", "abc", "abc"), [stable("abc")])
    }

    func testAnOverlappingChangeIsAHunk() {
        XCTAssertEqual(merge("abc", "axc", "ayc"), [stable("a"), hunk("b", "x", "y"), stable("c")])
        XCTAssertEqual(merge("abcd", "axyd", "abzd"), [stable("a"), hunk("bc", "xy", "bz"), stable("d")])
    }

    func testSamePositionInsertionsAreAHunk() {
        XCTAssertEqual(merge("ac", "axc", "ayc"), [stable("a"), hunk("", "x", "y"), stable("c")])
    }

    func testAdjacentReplacementsMergeCleanly() {
        XCTAssertEqual(merge("abcd", "axcd", "abyd"), [stable("axyd")])
        XCTAssertEqual(merge("abc", "axc", "abyc"), [stable("axyc")], "a replacement followed by an insertion at its end")
    }

    func testADeletionAgainstAChangeIsAHunk() {
        XCTAssertEqual(merge("abc", "ac", "ayc"), [stable("a"), hunk("b", "", "y"), stable("c")])
    }

    func testAnInsertionInsideARemovedRangeIsAHunk() {
        XCTAssertEqual(merge("abcd", "ad", "abxcd"), [stable("a"), hunk("bc", "", "bxc"), stable("d")])
    }

    func testAHunkIsTrimmedZealously() {
        XCTAssertEqual(merge("az", "akxlz", "akylz"), [stable("ak"), hunk("", "x", "y"), stable("lz")])
    }

    func testTrimmingDropsCommonLinesFromTheBaseToo() {
        let trimmed = ThreeWay.trim(ThreeWay.Hunk(base: lines("kbl"), ours: lines("kxl"), theirs: lines("kyl")))
        XCTAssertEqual(trimmed.before, lines("k"))
        XCTAssertEqual(trimmed.hunk, ThreeWay.Hunk(base: lines("b"), ours: lines("x"), theirs: lines("y")))
        XCTAssertEqual(trimmed.after, lines("l"))
        let kept = ThreeWay.trim(ThreeWay.Hunk(base: lines("b"), ours: lines("kxl"), theirs: lines("kyl")))
        XCTAssertEqual(kept.hunk.base, lines("b"), "a base that does not share the lines keeps its own")
    }

    func testTextResolvesEachHunk() {
        let merged = ThreeWay.merge(base: lines("abcd"), ours: lines("axcy"), theirs: lines("azcw"))
        XCTAssertEqual(merged.hunks.count, 2)
        let text = merged.text { index, hunk in index == 0 ? hunk.ours : hunk.theirs }
        XCTAssertEqual(text, Array("a\nx\nc\nw\n".utf8))
        XCTAssertEqual(merged.text { _, hunk in hunk.base }, Array("a\nb\nc\nd\n".utf8))
    }

    func testTheMergeIsDeterministic() {
        var generator = SplitMix(seed: 7)
        let base = (0..<2000).map { _ in Array("line \(generator.next() % 50)\n".utf8) }
        let ours = LineMergePerformance.mutate(base, every: 37, with: "ours", generator: &generator)
        let theirs = LineMergePerformance.mutate(base, every: 41, with: "theirs", generator: &generator)
        let first = ThreeWay.merge(base: base, ours: ours, theirs: theirs)
        for _ in 0..<3 { XCTAssertEqual(ThreeWay.merge(base: base, ours: ours, theirs: theirs), first) }
        XCTAssertFalse(first.hunks.isEmpty)
    }
}

/// merge-command task 2.3: 10k-line inputs merge in under 100 ms in a
/// release build. The class name matches CI's `--filter PerformanceTests`.
final class LineMergePerformanceTests: XCTestCase {
    func testTenThousandLinesMergeQuickly() {
        var generator = SplitMix(seed: 11)
        let base = (0..<10_000).map { index in Array("\t\t\tkey\(index) = value\(generator.next() % 1000);\n".utf8) }
        let ours = LineMergePerformance.mutate(base, every: 97, with: "ours", generator: &generator)
        let theirs = LineMergePerformance.mutate(base, every: 101, with: "theirs", generator: &generator)
        let started = Date()
        let merged = ThreeWay.merge(base: base, ours: ours, theirs: theirs)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertFalse(merged.regions.isEmpty)
        #if DEBUG
        let limit = 5.0
        #else
        let limit = 0.1
        #endif
        print("SCALE line merge 10k lines: \(String(format: "%.3f", elapsed))s")
        XCTAssertLessThan(elapsed, limit)
    }
}

enum LineMergePerformance {
    /// Replaces every `every`-th line and inserts one after every `2 * every`-th.
    static func mutate(_ lines: [[UInt8]], every: Int, with tag: String, generator: inout SplitMix) -> [[UInt8]] {
        var result: [[UInt8]] = []
        for (index, line) in lines.enumerated() {
            if index % every == 0 {
                result.append(Array("\(tag) \(generator.next() % 1000)\n".utf8))
            } else {
                result.append(line)
            }
            if index % (2 * every) == 1 { result.append(Array("\(tag) inserted \(index)\n".utf8)) }
        }
        return result
    }
}

/// A seeded generator, so the synthetic inputs are the same every run.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
