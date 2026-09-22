import Foundation
import XCTest
@testable import PBXSyntax

/// Trivia-only accessors for the model layer (typed-project-model, design
/// D5): leading trivia of an item and of a closing delimiter, and the
/// annotation comments after a value and after a key. None changes a value's
/// bytes.
final class TriviaAccessTests: XCTestCase {
    private let source = "{\n\tobjects = {\n\n/* Begin A section */\n\t\tA1 /* one */ = {isa = A; ref = B1 /* b */; };\n/* End A section */\n\n/* Begin B section */\n\t\tB1 = {\n\t\t\tisa = B;\n\t\t\tkids = (\n\t\t\t\tA1 /* one */,\n\t\t\t\tA2\n\t\t\t);\n\t\t};\n/* End B section */\n\t};\n}\n"

    func testLeadingTriviaOfAnItemIsReadable() throws {
        let tree = try XCTUnwrap(parsed(source))
        XCTAssertEqual(tree.leadingTrivia(at: ["objects", "A1"])?.text, "\n\n/* Begin A section */\n\t\t")
        XCTAssertEqual(tree.leadingTrivia(at: ["objects", "B1"])?.text, "\n/* End A section */\n\n/* Begin B section */\n\t\t")
        XCTAssertEqual(tree.leadingTrivia(at: ["objects", "B1", "kids", 1])?.text, "\n\t\t\t\t")
        XCTAssertEqual(tree.leadingTrivia(at: [])?.text, "")
        XCTAssertNil(tree.leadingTrivia(at: ["objects", "nope"]))
        XCTAssertEqual(tree.closingTrivia(at: ["objects"])?.text, "\n/* End B section */\n\t")
        XCTAssertEqual(tree.closingTrivia(at: ["objects", "B1", "kids"])?.text, "\n\t\t\t")
        XCTAssertNil(tree.closingTrivia(at: ["objects", "A1", "isa"]), "a string has no closing delimiter")
    }

    func testLeadingTriviaOfAnItemCanBeReplaced() throws {
        let trivia = try XCTUnwrap(Trivia.whitespace("\n") ?? nil) + (try XCTUnwrap(Trivia.blockComment("End A section")))
            + (try XCTUnwrap(Trivia.whitespace("\n\n"))) + (try XCTUnwrap(Trivia.blockComment("Begin C section")))
            + (try XCTUnwrap(Trivia.whitespace("\n\t\t")))
        let output = try edited(source) { try $0.setLeadingTrivia(trivia, at: ["objects", "B1"]) }
        XCTAssertEqual(output, replacing(source, "/* Begin B section */\n\t\tB1", with: "/* Begin C section */\n\t\tB1"))
        let closed = try edited(source) {
            try $0.setClosingTrivia(try XCTUnwrap(Trivia.whitespace("\n\t")), at: ["objects"])
        }
        XCTAssertEqual(closed, replacing(source, "\n/* End B section */\n\t};", with: "\n\t};"))
        let element = try edited(source) {
            try $0.setLeadingTrivia(try XCTUnwrap(Trivia.whitespace(" ")), at: ["objects", "B1", "kids", 1])
        }
        XCTAssertEqual(element, replacing(source, "\n\t\t\t\tA2", with: " A2"))
    }

    func testAnnotationsAreReadable() throws {
        let tree = try XCTUnwrap(parsed(source))
        XCTAssertEqual(tree.keyAnnotation(at: ["objects", "A1"]), "one")
        XCTAssertNil(tree.keyAnnotation(at: ["objects", "B1"]))
        XCTAssertEqual(tree.annotation(at: ["objects", "A1", "ref"]), "b")
        XCTAssertNil(tree.annotation(at: ["objects", "A1", "isa"]))
        XCTAssertEqual(tree.annotation(at: ["objects", "B1", "kids", 0]), "one")
        XCTAssertNil(tree.annotation(at: ["objects", "B1", "kids", 1]))
        XCTAssertNil(tree.annotation(at: ["objects", "nope"]))
        XCTAssertNil(tree.keyAnnotation(at: ["objects", "B1", "kids", 0]), "an element has no key")
    }

    func testAnnotationsCanBeSetWithoutTouchingValues() throws {
        // Non-canonical quoting on the value stays: only trivia changes.
        let quoted = replacing(source, "ref = B1 /* b */", with: "ref = 'B1' /* b */")
        XCTAssertEqual(
            try edited(quoted) { try $0.setAnnotation("bee", at: ["objects", "A1", "ref"]) },
            replacing(quoted, "'B1' /* b */", with: "'B1' /* bee */"))
        XCTAssertEqual(
            try edited(source) { try $0.setAnnotation("added", at: ["objects", "A1", "isa"]) },
            replacing(source, "isa = A;", with: "isa = A /* added */;"))
        XCTAssertEqual(
            try edited(source) { try $0.setKeyAnnotation("uno", at: ["objects", "A1"]) },
            replacing(source, "A1 /* one */ = {isa", with: "A1 /* uno */ = {isa"))
        XCTAssertEqual(
            try edited(source) { try $0.setKeyAnnotation("bee", at: ["objects", "B1"]) },
            replacing(source, "\t\tB1 = {", with: "\t\tB1 /* bee */ = {"))
        XCTAssertEqual(
            try edited(source) { try $0.setAnnotation("uno", at: ["objects", "B1", "kids", 0]) },
            replacing(source, "A1 /* one */,\n", with: "A1 /* uno */,\n"))
        XCTAssertEqual(
            try edited(source) { try $0.setAnnotation("two", at: ["objects", "B1", "kids", 1]) },
            replacing(source, "\t\t\t\tA2\n", with: "\t\t\t\tA2 /* two */\n"),
            "the last element without a comma keeps its annotation before the closing delimiter")
        XCTAssertEqual(
            try edited("{ a = (x /* old */); }") { try $0.setAnnotation("new", at: ["a", 0]) },
            "{ a = (x /* new */); }")
    }

    func testTriviaCanBeBuiltFromValidatedText() {
        XCTAssertEqual(Trivia(validating: "\n/* End A section */\n\t")?.text, "\n/* End A section */\n\t")
        XCTAssertEqual(Trivia(validating: "")?.text, "")
        XCTAssertEqual(Trivia(validating: " // tail")?.pieces.count, 2)
        XCTAssertNil(Trivia(validating: "x"))
        XCTAssertNil(Trivia(validating: "/* open"))
        XCTAssertNil(Trivia(validating: " a = b; "))
        XCTAssertNil(Trivia(validating: "\u{FEFF}"), "a byte order mark is not trivia in the middle of a file")
    }

    func testAccessorErrors() throws {
        var tree = try XCTUnwrap(parsed(source))
        let before = tree
        XCTAssertThrowsError(try tree.setAnnotation("x", at: ["objects", "nope"]))
        XCTAssertThrowsError(try tree.setKeyAnnotation("x", at: ["objects", "B1", "kids", 0]))
        XCTAssertThrowsError(try tree.setAnnotation("bad */", at: ["objects", "A1", "ref"]))
        XCTAssertThrowsError(try tree.setLeadingTrivia(.empty, at: ["objects", "nope"]))
        XCTAssertThrowsError(try tree.setClosingTrivia(.empty, at: ["objects", "A1", "isa"]))
        XCTAssertEqual(tree, before, "a failed edit leaves the tree unchanged")
    }
}
