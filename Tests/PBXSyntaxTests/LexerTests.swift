import XCTest
@testable import PBXSyntax

final class LexerTests: XCTestCase {
    func testStructuralTokens() {
        let result = tokens("{}()=;,")
        XCTAssertEqual(
            result.map(\.kind),
            [.leftBrace, .rightBrace, .leftParen, .rightParen, .equals, .semicolon, .comma, .endOfFile]
        )
        XCTAssertEqual(result.map(\.text), ["{", "}", "(", ")", "=", ";", ",", ""])
    }

    func testBareStringOverCoreFoundationCharacterSet() {
        let source = "abcXYZ019_$/:.-"
        let result = tokens(source)
        XCTAssertEqual(result.map(\.kind), [.bareString, .endOfFile])
        XCTAssertEqual(result.first?.text, source)
    }

    func testBareStringEndsAtStructuralCharacter() {
        let result = tokens("path=Foo.swift;")
        XCTAssertEqual(result.map(\.kind), [.bareString, .equals, .bareString, .semicolon, .endOfFile])
        XCTAssertEqual(result.map(\.text), ["path", "=", "Foo.swift", ";", ""])
    }

    func testQuotedStringKeepsRawTextIncludingEscapes() {
        let source = #""a \"quoted\" \\ \n \U00e9 é""#
        let result = tokens(source)
        XCTAssertEqual(result.map(\.kind), [.quotedString, .endOfFile])
        XCTAssertEqual(result.first?.text, source)
    }

    func testQuotedStringMayContainStructuralCharactersAndCommentMarkers() {
        let source = #""{ ( /* not a comment */ // nor this ; = , ) }""#
        let result = tokens(source)
        XCTAssertEqual(result.map(\.kind), [.quotedString, .endOfFile])
        XCTAssertEqual(result.first?.text, source)
    }

    func testSingleQuotedString() {
        let source = #"'it''s' 'a "b"'"#
        let result = tokens(source)
        XCTAssertEqual(result.map(\.kind), [.quotedString, .quotedString, .quotedString, .endOfFile])
        XCTAssertEqual(reassembled(result), source)
    }

    func testDataLiteral() {
        let source = "<0fbd777f 1c2735ae>"
        let result = tokens(source)
        XCTAssertEqual(result.map(\.kind), [.data, .endOfFile])
        XCTAssertEqual(result.first?.text, source)
    }

    func testBlockCommentIsLeadingTriviaOfTheNextToken() {
        let result = tokens("/* Begin PBXGroup section */\n\t\tA1")
        XCTAssertEqual(result.map(\.kind), [.bareString, .endOfFile])
        XCTAssertEqual(
            result.first?.leadingTrivia.pieces,
            [.blockComment("/* Begin PBXGroup section */"), .whitespace("\n\t\t")]
        )
    }

    func testLineCommentRunsToEndOfLine() {
        let source = "// !$*UTF8*$!\n{"
        let result = tokens(source)
        XCTAssertEqual(result.map(\.kind), [.leftBrace, .endOfFile])
        XCTAssertEqual(result.first?.leadingTrivia.pieces, [.lineComment("// !$*UTF8*$!"), .whitespace("\n")])
        XCTAssertEqual(reassembled(result), source)
    }

    func testLineCommentAtEndOfInputWithoutNewline() {
        let source = "A // trailing"
        let result = tokens(source)
        XCTAssertEqual(result.map(\.kind), [.bareString, .endOfFile])
        XCTAssertEqual(result.last?.leadingTrivia.pieces, [.whitespace(" "), .lineComment("// trailing")])
    }

    func testCarriageReturnLineFeedIsWhitespace() {
        let source = "{\r\n\tisa = PBXGroup;\r\n}"
        let result = tokens(source)
        XCTAssertEqual(result[1].leadingTrivia.pieces, [.whitespace("\r\n\t")])
        XCTAssertEqual(reassembled(result), source)
    }

    /// Design D2: a comment after a value belongs to the next token.
    func testCommentAfterValueBelongsToTheSeparator() {
        let result = tokens("A1 /* Foo.swift */,")
        XCTAssertEqual(result.map(\.kind), [.bareString, .comma, .endOfFile])
        XCTAssertEqual(result[0].leadingTrivia.text, "")
        XCTAssertEqual(result[1].leadingTrivia.pieces, [.whitespace(" "), .blockComment("/* Foo.swift */")])
    }

    func testCommentAfterKeyBelongsToTheEqualsSign() {
        let result = tokens("A1 /* name */ = {")
        XCTAssertEqual(result.map(\.kind), [.bareString, .equals, .leftBrace, .endOfFile])
        XCTAssertEqual(
            result[1].leadingTrivia.pieces,
            [.whitespace(" "), .blockComment("/* name */"), .whitespace(" ")]
        )
        XCTAssertEqual(result[2].leadingTrivia.pieces, [.whitespace(" ")])
    }

    /// Design D1: the end-of-file token owns whatever follows the last real token.
    func testEndOfFileTokenOwnsTrailingTrivia() {
        let result = tokens("{}\n/* tail */\n")
        XCTAssertEqual(result.last?.kind, .endOfFile)
        XCTAssertEqual(
            result.last?.leadingTrivia.pieces,
            [.whitespace("\n"), .blockComment("/* tail */"), .whitespace("\n")]
        )
    }

    func testByteOrderMarkIsTriviaAtTheStart() {
        let source = "\u{FEFF}{}"
        let result = tokens(source)
        XCTAssertEqual(result.first?.leadingTrivia.pieces, [.byteOrderMark])
        XCTAssertEqual(reassembled(result), source)
    }

    func testMultiByteTextPassesThroughStringsAndComments() {
        let source = "/* Überblick 日本語 */ \"Größe 📦\""
        let result = tokens(source)
        XCTAssertEqual(result.map(\.kind), [.quotedString, .endOfFile])
        XCTAssertEqual(Array(reassembled(result).utf8), Array(source.utf8))
    }

    func testReassemblyReproducesEveryInput() {
        let inputs = [
            "",
            "   \n\t",
            "{}()=;,",
            "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tobjects = {\n\t};\n}\n",
            "A1 /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = B2 /* Foo.swift */; };",
            "children = (\r\n\tA1 /* x */,\r\n\tB2 /* y */,\r\n);",
            "<0fbd 777f> \"q\\\"\" 'single' bare-string:with.cf/chars",
            // `/` is a bare-string character, so a comment needs a space before it.
            "/**/x /***/y /* * / */",
        ]
        for input in inputs {
            let result = tokens(input)
            XCTAssertEqual(Array(reassembled(result).utf8), Array(input.utf8), "input: \(input.debugDescription)")
        }
    }
}
