import XCTest
@testable import PBXSyntax

final class ParserTests: XCTestCase {
    // Spec: Grammar coverage — Escapes in a quoted string.
    func testEscapesInAQuotedString() throws {
        let source = #"{ name = "a \"quoted\" \U00e9\n"; }"#
        let tree = try XCTUnwrap(parsed(source))
        let name = try XCTUnwrap(tree.root.dictionary?["name"]?.string)
        XCTAssertEqual(name.value, "a \"quoted\" é\n")
        XCTAssertEqual(name.rawText, #""a \"quoted\" \U00e9\n""#)
        XCTAssertTrue(name.isQuoted)
    }

    // Spec: Grammar coverage — Single-line dictionary.
    func testSingleLineDictionary() throws {
        let source = "{ A1 /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = B2 /* Foo.swift */; }; }"
        let tree = try XCTUnwrap(parsed(source))
        let root = try XCTUnwrap(tree.root.dictionary)
        XCTAssertEqual(root.keys, ["A1"])
        let entry = try XCTUnwrap(root.entries.first)
        XCTAssertEqual(entry.key.value, "A1")
        XCTAssertEqual(
            entry.equals.leadingTrivia.pieces,
            [.whitespace(" "), .blockComment("/* Foo.swift in Sources */"), .whitespace(" ")]
        )
        let value = try XCTUnwrap(entry.value.dictionary)
        XCTAssertEqual(value.keys, ["isa", "fileRef"])
        XCTAssertEqual(value["isa"]?.stringValue, "PBXBuildFile")
        XCTAssertEqual(value["fileRef"]?.stringValue, "B2")
        XCTAssertEqual(
            value.entries.last?.semicolon.leadingTrivia.pieces,
            [.whitespace(" "), .blockComment("/* Foo.swift */")]
        )
    }

    // Spec: Grammar coverage — Array with trailing comma.
    func testArrayWithTrailingComma() throws {
        let source = "{ children = (\n\tA1 /* x */,\n\tB2 /* y */,\n); }"
        let tree = try XCTUnwrap(parsed(source))
        let children = try XCTUnwrap(tree.root.dictionary?["children"]?.array)
        XCTAssertEqual(children.elements.map { $0.value.stringValue }, ["A1", "B2"])
        XCTAssertEqual(children.elements.map { $0.comma != nil }, [true, true])
        XCTAssertEqual(children.elements[1].comma?.leadingTrivia.pieces, [.whitespace(" "), .blockComment("/* y */")])
    }

    func testArrayWithoutTrailingComma() throws {
        let tree = try XCTUnwrap(parsed("(a, b)"))
        let array = try XCTUnwrap(tree.root.array)
        XCTAssertEqual(array.elements.map { $0.value.stringValue }, ["a", "b"])
        XCTAssertEqual(array.elements.map { $0.comma != nil }, [true, false])
    }

    func testEmptyContainers() throws {
        let tree = try XCTUnwrap(parsed("{ a = (); b = {}; }"))
        let root = try XCTUnwrap(tree.root.dictionary)
        XCTAssertEqual(root["a"]?.array?.elements.count, 0)
        XCTAssertEqual(root["b"]?.dictionary?.entries.count, 0)
    }

    func testKeyOrderAndDuplicateKeysArePreserved() throws {
        let tree = try XCTUnwrap(parsed("{ z = 1; a = 2; z = 3; }"))
        let root = try XCTUnwrap(tree.root.dictionary)
        XCTAssertEqual(root.keys, ["z", "a", "z"])
        XCTAssertEqual(root["z"]?.stringValue, "1", "lookup returns the first match")
    }

    func testQuotedKey() throws {
        let tree = try XCTUnwrap(parsed(#"{ "ARCHS[sdk=*]" = arm64; }"#))
        XCTAssertEqual(tree.root.dictionary?["ARCHS[sdk=*]"]?.stringValue, "arm64")
    }

    func testDataNode() throws {
        let tree = try XCTUnwrap(parsed("{ d = <0fbd 777f>; }"))
        let data = try XCTUnwrap(tree.root.dictionary?["d"]?.data)
        XCTAssertEqual(data.rawText, "<0fbd 777f>")
        XCTAssertEqual(data.bytes, [0x0F, 0xBD, 0x77, 0x7F])
    }

    func testBareStringValueIsItsText() throws {
        let tree = try XCTUnwrap(parsed("{ path = My-File.swift; }"))
        let path = try XCTUnwrap(tree.root.dictionary?["path"]?.string)
        XCTAssertEqual(path.value, "My-File.swift")
        XCTAssertFalse(path.isQuoted)
    }

    func testEscapeDecoding() throws {
        let cases: [(String, String)] = [
            (#""\a\b\f\n\r\t\v""#, "\u{07}\u{08}\u{0C}\n\r\t\u{0B}"),
            (#""\\ \" \'""#, "\\ \" '"),
            (#""\101\60\7""#, "A0\u{07}"),
            (#""\U0041\u0042""#, "Au0042"),
            (#""\Ud83d\Ude00""#, "😀"),
            (#""\Ud83d""#, "\u{FFFD}"),
            (#""\q""#, "q"),
            (#"'single "double"'"#, "single \"double\""),
            ("\"line\\\nbreak\"", "line\nbreak"),
            (#""\U00zz""#, "U00zz"),
        ]
        for (raw, expected) in cases {
            let tree = try XCTUnwrap(parsed("{ k = \(raw); }"), "raw: \(raw)")
            XCTAssertEqual(tree.root.dictionary?["k"]?.stringValue, expected, "raw: \(raw)")
        }
    }

    func testNestedStructure() throws {
        let source = """
            // !$*UTF8*$!
            {
            \tarchiveVersion = 1;
            \tobjects = {
            \t\tG1 = {
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            \t\t\t\tA1 /* a.swift */,
            \t\t\t);
            \t\t};
            \t};
            \trootObject = P1 /* Project object */;
            }

            """
        let tree = try XCTUnwrap(parsed(source))
        let root = try XCTUnwrap(tree.root.dictionary)
        XCTAssertEqual(root.keys, ["archiveVersion", "objects", "rootObject"])
        let group = try XCTUnwrap(root["objects"]?.dictionary?["G1"]?.dictionary)
        XCTAssertEqual(group["isa"]?.stringValue, "PBXGroup")
        XCTAssertEqual(group["children"]?.array?.elements.first?.value.stringValue, "A1")
        XCTAssertEqual(tree.endOfFile.leadingTrivia.text, "\n")
    }

    func testRootMayBeAnyValue() throws {
        XCTAssertNotNil(parsed("(a, b)")?.root.array)
        XCTAssertEqual(parsed("\"just a string\"")?.root.stringValue, "just a string")
    }

    func testNestingAtTheLimitParses() {
        let depth = SyntaxTree.maximumNestingDepth
        let source = String(repeating: "(", count: depth) + String(repeating: ")", count: depth)
        XCTAssertNotNil(parsed(source))
    }

    /// Motivation table, row 1: keys are matched exactly, never by prefix.
    func testKeyLookupIsExactNotByPrefix() throws {
        let tree = try XCTUnwrap(parsed("{ TVOSTEST00020 = long; TVOSTEST0002 = short; }"))
        let root = try XCTUnwrap(tree.root.dictionary)
        XCTAssertEqual(root["TVOSTEST0002"]?.stringValue, "short")
        XCTAssertEqual(root["TVOSTEST00020"]?.stringValue, "long")
        XCTAssertNil(root["TVOSTEST000"])
    }

    /// `String ==` equates canonically equivalent text; keys must not.
    func testKeyLookupIsByteExact() throws {
        let tree = try XCTUnwrap(parsed("{ \"caf\u{E9}\" = composed; }"))
        let root = try XCTUnwrap(tree.root.dictionary)
        XCTAssertEqual(root["caf\u{E9}"]?.stringValue, "composed")
        XCTAssertNil(root["cafe\u{301}"])
    }
}
