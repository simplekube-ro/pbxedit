import XCTest
@testable import PBXSyntax

/// `integrity-rules-lint` task 3.2: the write-side quoting rule (design D5),
/// exposed read-only so rule S5 can ask whether an existing string is spelled
/// as Xcode would spell it.
final class CanonicalQuotingTests: XCTestCase {
    func testIsCanonicallyQuoted() throws {
        let source = #"{ a = My-File.swift; b = "My-File.swift"; c = Foo.swift; d = "Foo.swift"; e = ""; f = "<group>"; g = "a\"b"; }"#
        let tree = try SyntaxTree.parse(Array(source.utf8)).get()
        func node(_ key: String) -> StringNode? { tree.node(at: [.key(key)])?.string }
        XCTAssertEqual(node("a")?.isCanonicallyQuoted, false, "bare hyphen: Xcode quotes it")
        XCTAssertEqual(node("b")?.isCanonicallyQuoted, true)
        XCTAssertEqual(node("c")?.isCanonicallyQuoted, true)
        XCTAssertEqual(node("d")?.isCanonicallyQuoted, false, "needless quotes")
        XCTAssertEqual(node("e")?.isCanonicallyQuoted, true, "the empty string must be quoted")
        XCTAssertEqual(node("f")?.isCanonicallyQuoted, true)
        XCTAssertEqual(node("g")?.isCanonicallyQuoted, true, "escapes decode before the rule is applied")
        // Keys are strings too.
        let entries = try XCTUnwrap(tree.root.dictionary?.entries)
        XCTAssertTrue(entries.allSatisfy { $0.key.isCanonicallyQuoted })
    }
}
