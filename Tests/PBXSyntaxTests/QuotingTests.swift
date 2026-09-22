import Foundation
import XCTest
@testable import PBXSyntax

/// Task 6.3 — canonical quoting on write (design D5), existing quoting kept.
final class QuotingTests: XCTestCase {
    private func written(_ value: String) throws -> String {
        let output = try edited("{ v = old; }") { try $0.replaceValue(at: ["v"], with: .string(value)) }
        let tree = try XCTUnwrap(parsed(output))
        XCTAssertEqual(tree.node(at: ["v"])?.stringValue, value, "the written string must decode to the value")
        return String(output.dropFirst("{ v = ".count).dropLast("; }".count))
    }

    // Spec: Written strings are quoted canonically — Hyphen and plus are quoted on write.
    func testHyphenAndPlusAreQuotedOnWrite() throws {
        XCTAssertEqual(try written("My-File.swift"), "\"My-File.swift\"")
        XCTAssertEqual(try written("AppState+Scope.swift"), "\"AppState+Scope.swift\"")
    }

    func testStringsOverTheWriteSideSetAreLeftBare() throws {
        for value in ["Foo.swift", "a/b_c$d.E9", "PBXBuildFile", "0", "sourcecode.swift", "_", "a_/b", "__", "/"] {
            XCTAssertEqual(try written(value), value)
        }
    }

    func testEverythingElseIsQuoted() throws {
        for value in ["", "a//b", "a___b", "two words", "<group>", "a:b", "-", "café", "a,b", "a=b", "a;b", "(a)", "{a}", "a*b", "@rpath", "$(SRCROOT)", "a'b"] {
            XCTAssertEqual(try written(value), "\"\(value)\"", value)
        }
    }

    func testEscapesOnWrite() throws {
        XCTAssertEqual(try written("say \"hi\""), #""say \"hi\"""#)
        XCTAssertEqual(try written("back\\slash"), #""back\\slash""#)
        XCTAssertEqual(try written("line\nbreak"), #""line\nbreak""#)
        XCTAssertEqual(try written("tab\there"), #""tab\there""#)
        XCTAssertEqual(try written("cr\rhere"), #""cr\rhere""#)
        XCTAssertEqual(try written("bell\u{07}"), #""bell\U0007""#)
        XCTAssertEqual(try written("del\u{7F}"), #""del\U007f""#)
        XCTAssertEqual(try written("emoji 😀 é"), "\"emoji 😀 é\"")
    }

    func testEveryWrittenStringDecodesToItself() throws {
        var generator = SplitMix64(seed: 0x5EED)
        let alphabet: [Character] = ["a", "Z", "0", "_", "$", "/", ".", "-", "+", " ", "\"", "\\", "\n", "\t", "\r", "\u{01}", "\u{7F}", "é", "😀", "*", "'", ";", "U", "n", "\u{2028}"]
        for _ in 0..<500 {
            let length = Int(generator.next() % 12)
            let value = String((0..<length).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] })
            _ = try written(value)
        }
    }

    func testKeysAndCommentsFollowTheSameRule() throws {
        let output = try edited("{\n\ta = 1;\n}\n") {
            try $0.insert(NewEntry("ARCHS[sdk=*]", comment: "note", .string("arm64 x86_64")), intoDictionaryAt: [])
        }
        XCTAssertEqual(output, "{\n\ta = 1;\n\t\"ARCHS[sdk=*]\" /* note */ = \"arm64 x86_64\";\n}\n")
    }

    // Spec: Written strings are quoted canonically — Existing quoting is preserved.
    func testExistingQuotingIsPreserved() throws {
        let source = "{\n\tbareHyphen = My-File.swift;\n\tneedlesslyQuoted = \"Foo.swift\";\n\tsingle = 'x';\n\tother = old;\n}\n"
        let output = try edited(source) { try $0.replaceValue(at: ["other"], with: .string("new")) }
        XCTAssertEqual(output, replacing(source, "other = old;", with: "other = new;"))
        XCTAssertTrue(output.contains("bareHyphen = My-File.swift;"))
        XCTAssertTrue(output.contains("needlesslyQuoted = \"Foo.swift\";"))
    }
}

/// Deterministic generator for seeded tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
