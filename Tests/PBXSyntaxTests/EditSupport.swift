import Foundation
import XCTest
@testable import PBXSyntax

/// Applies `edit` to the tree parsed from `source` and returns the serialized
/// result. Also asserts that the edited tree re-parses to itself, so no edit
/// can produce text that reads back differently.
func edited(
    _ source: String, file: StaticString = #filePath, line: UInt = #line,
    _ edit: (inout SyntaxTree) throws -> Void
) throws -> String {
    var tree = try XCTUnwrap(parsed(source, file: file, line: line), file: file, line: line)
    try edit(&tree)
    let output = tree.serialize()
    switch SyntaxTree.parse(output) {
    case .success(let reparsed):
        XCTAssertEqual(reparsed, tree, "the edited tree does not re-parse to itself", file: file, line: line)
    case .failure(let error):
        XCTFail("the edited tree does not parse: \(error)\n\(text(output))", file: file, line: line)
    }
    return text(output)
}

func fixtureText(_ relativePath: String) throws -> String {
    text(try Fixtures.load(relativePath))
}

/// `source` with the first occurrence of `target` replaced.
func replacing(_ source: String, _ target: String, with replacement: String,
               file: StaticString = #filePath, line: UInt = #line) -> String {
    guard let range = source.range(of: target) else {
        XCTFail("fixture does not contain \(target.debugDescription)", file: file, line: line)
        return source
    }
    return source.replacingCharacters(in: range, with: replacement)
}
