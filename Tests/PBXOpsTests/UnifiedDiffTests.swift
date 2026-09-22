import XCTest
@testable import PBXOps

/// Task 2.4: the unified diff `--dry-run` prints.
final class UnifiedDiffTests: XCTestCase {
    func testIdenticalInputsGiveAnEmptyDiff() {
        XCTAssertEqual(UnifiedDiff.make(from: Array("a\nb\n".utf8), to: Array("a\nb\n".utf8), name: "f"), "")
    }

    func testAnInsertionInTheMiddleIsOneHunkWithContext() {
        let before = (1...10).map { "line \($0)\n" }.joined()
        let after = (1...5).map { "line \($0)\n" }.joined() + "new\n" + (6...10).map { "line \($0)\n" }.joined()
        let diff = UnifiedDiff.make(from: Array(before.utf8), to: Array(after.utf8), name: "f")
        XCTAssertEqual(diff, """
            --- a/f
            +++ b/f
            @@ -3,6 +3,7 @@
             line 3
             line 4
             line 5
            +new
             line 6
             line 7
             line 8

            """)
    }

    func testTwoDistantEditsAreTwoHunksAndARemovalIsMinus() {
        let before = (1...30).map { "l\($0)\n" }.joined()
        var lines = (1...30).map { "l\($0)\n" }
        lines.remove(at: 1)          // l2 removed
        lines.insert("x\n", at: 25)  // insertion near the end
        let after = lines.joined()
        let diff = UnifiedDiff.make(from: Array(before.utf8), to: Array(after.utf8), name: "f")
        XCTAssertTrue(diff.hasPrefix("--- a/f\n+++ b/f\n@@ -1,5 +1,4 @@\n l1\n-l2\n l3\n l4\n l5\n@@ -24,6 +23,7 @@\n"), diff)
        XCTAssertTrue(diff.contains("+x\n"), diff)
        XCTAssertEqual(diff.components(separatedBy: "@@ -").count - 1, 2)
    }

    func testAMissingTrailingNewlineIsMarked() {
        let diff = UnifiedDiff.make(from: Array("a\nb".utf8), to: Array("a\nb\nc".utf8), name: "f")
        XCTAssertEqual(diff, "--- a/f\n+++ b/f\n@@ -1,2 +1,3 @@\n a\n-b\n\\ No newline at end of file\n+b\n+c\n\\ No newline at end of file\n")
    }
}
