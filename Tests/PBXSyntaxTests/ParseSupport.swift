import XCTest
@testable import PBXSyntax

/// Parses, failing the test on a parse error.
func parsed(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> SyntaxTree? {
    switch SyntaxTree.parse(bytes(source)) {
    case .success(let tree):
        return tree
    case .failure(let error):
        XCTFail("unexpected parse error: \(error)", file: file, line: line)
        return nil
    }
}

/// The parse error for `source`, failing the test when it parses.
func parseError(_ source: [UInt8], file: StaticString = #filePath, line: UInt = #line) -> ParseError? {
    switch SyntaxTree.parse(source) {
    case .success:
        XCTFail("expected a parse error", file: file, line: line)
        return nil
    case .failure(let error):
        return error
    }
}

func parseError(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> ParseError? {
    parseError(bytes(source), file: file, line: line)
}

