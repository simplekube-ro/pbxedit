import XCTest
@testable import PBXSyntax

/// Change `merge-reorder-whole-array`, design D2: the lines an array spans,
/// for the line merge to keep a reorder in one hunk.
final class ArrayLinesTests: XCTestCase {
    private func lines(_ source: String) -> [[String]: Range<Int>] {
        guard let tree = parsed(source) else { return [:] }
        var result: [[String]: Range<Int>] = [:]
        for (keys, range) in tree.arrayLines() { result[keys] = range }
        return result
    }

    func testAnArrayOneElementPerLineSpansItsParentheses() {
        let source = "{\n\tobjects = {\n\t\tA = {\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n\t\t};\n\t};\n}\n"
        XCTAssertEqual(lines(source), [["objects", "A", "knownRegions"]: 3..<7])
    }

    func testAnArrayOnOneLineSpansThatLine() {
        XCTAssertEqual(lines("{\n\ta = (x, y);\n\tb = {\n\t\tc = ();\n\t};\n}\n"), [["a"]: 1..<2, ["b", "c"]: 3..<4])
    }

    func testCommentsAndQuotedNewlinesCount() {
        let source = "{\n\t/* one\n two */ a = \"x\ny\";\n\tb = (\n\t\tz, /* w */\n\t);\n}\n"
        XCTAssertEqual(lines(source), [["b"]: 4..<7])
    }

    func testArraysInsideArraysAreNotReachedByKeys() {
        XCTAssertEqual(lines("{\n\ta = (\n\t\t(x),\n\t\t{ b = (y); },\n\t);\n}\n"), [["a"]: 1..<5])
    }

    func testAnEmptyTreeHasNoArrays() {
        XCTAssertEqual(lines("{}"), [:])
        XCTAssertEqual(lines("(a)"), [[]: 0..<1])
    }
}
