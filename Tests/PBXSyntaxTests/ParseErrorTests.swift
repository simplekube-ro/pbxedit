import XCTest
@testable import PBXSyntax

final class ParseErrorTests: XCTestCase {
    // Spec: Located errors — Character not allowed in a bare string.
    func testPlusInABareStringIsLocated() throws {
        var lines = ["// !$*UTF8*$!", "{", "\tobjects = {", "\t\tA1 = {"]
        while lines.count < 11 { lines.append("\t\t\tkey\(lines.count) = value;") }
        lines.append("\t\t\tpath = Foo+Bar.swift;")
        lines.append(contentsOf: ["\t\t};", "\t};", "}"])
        let error = try XCTUnwrap(parseError(lines.joined(separator: "\n")))
        XCTAssertEqual(error.kind, .unexpectedCharacter)
        XCTAssertEqual(error.line, 12)
        XCTAssertEqual(error.column, 14, "three tabs, then `path = Foo` is ten columns, so `+` is column 14")
        XCTAssertTrue(error.found.contains("+"), error.found)
        XCTAssertTrue(error.description.hasPrefix("12:14: "), error.description)
    }

    // Spec: Located errors — Unterminated comment.
    func testUnterminatedCommentIsLocatedAtItsOpening() throws {
        let source = "{\n\tobjects = {\n\n/* Begin PBXGroup"
        let error = try XCTUnwrap(parseError(source))
        XCTAssertEqual(error.kind, .unterminatedComment)
        XCTAssertEqual(error.line, 4)
        XCTAssertEqual(error.column, 1)
        XCTAssertEqual(error.byteOffset, source.utf8.count - "/* Begin PBXGroup".utf8.count)
    }

    // Spec: Located errors — Not an old-style property list.
    func testXMLPropertyListIsRejectedAsUnsupported() throws {
        for source in ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict/></plist>",
                       "\n  <?xml version=\"1.0\"?>", "<!DOCTYPE plist>", "<plist version=\"1.0\">"] {
            let error = try XCTUnwrap(parseError(source))
            XCTAssertEqual(error.kind, .unsupportedFormat(.xml), source)
            XCTAssertTrue(error.found.contains("XML"), error.found)
            XCTAssertTrue(error.description.contains("not supported"), error.description)
        }
    }

    func testBinaryPropertyListIsRejectedAsUnsupported() throws {
        let source: [UInt8] = Array("bplist00".utf8) + [0xD1, 0x01, 0x02, 0xFF, 0x00]
        let error = try XCTUnwrap(parseError(source))
        XCTAssertEqual(error.kind, .unsupportedFormat(.binary))
        XCTAssertEqual(error.byteOffset, 0)
        XCTAssertTrue(error.found.contains("binary"), error.found)
        XCTAssertTrue(error.description.contains("not supported"), error.description)
    }

    // Spec: UTF-8 only — Invalid byte sequence.
    func testInvalidUTF8ReportsTheByteOffset() throws {
        let prefix = Array("{\n\tname = \"ab".utf8)
        let source = prefix + [0xFF] + Array("\";\n}".utf8)
        let error = try XCTUnwrap(parseError(source))
        XCTAssertEqual(error.kind, .invalidUTF8)
        XCTAssertEqual(error.byteOffset, prefix.count)
        XCTAssertEqual(error.line, 2)
        XCTAssertEqual(error.column, 12)
        XCTAssertTrue(error.found.contains("0xFF"), error.found)
        XCTAssertTrue(error.description.contains("byte offset \(prefix.count)"), error.description)
    }

    func testInvalidUTF8Forms() throws {
        let cases: [([UInt8], Int)] = [
            ([0x80], 0),                          // lone continuation
            ([0x41, 0xC3], 1),                    // truncated two-byte sequence
            ([0xC0, 0xAF], 0),                    // overlong
            ([0xE0, 0x80, 0xAF], 0),              // overlong three-byte
            ([0xED, 0xA0, 0x80], 0),              // UTF-16 surrogate
            ([0xF4, 0x90, 0x80, 0x80], 0),        // above U+10FFFF
            ([0x41, 0xE2, 0x82, 0x41], 1),        // bad continuation
        ]
        for (tail, badOffset) in cases {
            let prefix = Array("{ a = \"".utf8)
            let error = try XCTUnwrap(parseError(prefix + tail + Array("\"; }".utf8)))
            XCTAssertEqual(error.kind, .invalidUTF8, "\(tail)")
            XCTAssertEqual(error.byteOffset, prefix.count + badOffset, "\(tail)")
        }
    }

    func testValidMultiByteUTF8IsAccepted() {
        XCTAssertNotNil(parsed("{ a = \"é € 😀 \u{10FFFF}\"; /* ü */ }"))
    }

    func testNestingPastTheLimitIsALocatedError() throws {
        let depth = SyntaxTree.maximumNestingDepth + 1
        let source = String(repeating: "(", count: depth) + String(repeating: ")", count: depth)
        let error = try XCTUnwrap(parseError(source))
        XCTAssertEqual(error.kind, .nestingTooDeep)
        XCTAssertEqual(error.line, 1)
        XCTAssertEqual(error.column, depth, "the container that crosses the limit")
    }

    func testVeryDeepNestingDoesNotOverflowTheStack() throws {
        let source = String(repeating: "{a=", count: 200_000)
        XCTAssertEqual(try XCTUnwrap(parseError(source)).kind, .nestingTooDeep)
    }

    func testUnterminatedStringIsLocatedAtItsOpening() throws {
        let error = try XCTUnwrap(parseError("{\n\tname = \"never closed;\n}\n"))
        XCTAssertEqual(error.kind, .unterminatedString)
        XCTAssertEqual(error.line, 2)
        XCTAssertEqual(error.column, 9)
    }

    func testStringEndingInABackslashIsUnterminated() throws {
        XCTAssertEqual(try XCTUnwrap(parseError("\"abc\\")).kind, .unterminatedString)
        XCTAssertEqual(try XCTUnwrap(parseError("\"abc\\\"")).kind, .unterminatedString)
    }

    func testMissingSemicolon() throws {
        let error = try XCTUnwrap(parseError("{\n\ta = b\n\tc = d;\n}"))
        XCTAssertEqual(error.kind, .unexpectedToken)
        XCTAssertEqual(error.line, 3)
        XCTAssertEqual(error.column, 2)
        XCTAssertTrue(error.expected.contains("';'"), error.expected)
        XCTAssertEqual(error.found, "'c'")
    }

    func testMissingCommaBetweenArrayElements() throws {
        let error = try XCTUnwrap(parseError("( a b )"))
        XCTAssertEqual(error.kind, .unexpectedToken)
        XCTAssertEqual(error.column, 5)
    }

    func testUnexpectedEndOfInput() throws {
        for source in ["", "   \n", "{", "{ a", "{ a =", "{ a = b", "{ a = b;", "(", "( a", "( a,"] {
            let error = try XCTUnwrap(parseError(source), source.debugDescription)
            XCTAssertEqual(error.kind, .unexpectedEndOfInput, source.debugDescription)
            XCTAssertEqual(error.byteOffset, source.utf8.count)
            XCTAssertEqual(error.found, "end of input")
        }
    }

    func testTrailingContentAfterTheRootValue() throws {
        let error = try XCTUnwrap(parseError("{}\n{}"))
        XCTAssertEqual(error.kind, .unexpectedToken)
        XCTAssertEqual(error.line, 2)
        XCTAssertEqual(error.column, 1)
    }

    func testMalformedData() throws {
        XCTAssertEqual(try XCTUnwrap(parseError("{ d = <0g>; }")).column, 9)
        XCTAssertEqual(try XCTUnwrap(parseError("{ d = <abc>; }")).kind, .malformedData)
        XCTAssertEqual(try XCTUnwrap(parseError("{ d = <ab")).kind, .malformedData)
    }

    func testColumnsCountScalarsNotBytes() throws {
        let error = try XCTUnwrap(parseError("{ \"é€😀\" = +; }"))
        XCTAssertEqual(error.column, 11)
        XCTAssertEqual(error.byteOffset, 16)
    }

    func testLineCountingAcrossLineEndingStyles() throws {
        XCTAssertEqual(try XCTUnwrap(parseError("{\r\n\r\n+")).line, 3)
        XCTAssertEqual(try XCTUnwrap(parseError("{\r\r+")).line, 3)
        XCTAssertEqual(try XCTUnwrap(parseError("{\n\n+")).line, 3)
    }

    func testControlCharacterIsDescribed() throws {
        let error = try XCTUnwrap(parseError("{ a = \u{01}; }"))
        XCTAssertEqual(error.kind, .unexpectedCharacter)
        XCTAssertEqual(error.found, "control character U+0001")
    }
}
