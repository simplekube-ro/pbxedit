import Foundation
import XCTest
@testable import PBXSyntax

func bytes(_ string: String) -> [UInt8] { Array(string.utf8) }

func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

/// Tokenizes, failing the test on a lexer error.
func tokens(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> [Token] {
    switch Lexer.tokenize(bytes(source)) {
    case .success(let tokens):
        return tokens
    case .failure(let error):
        XCTFail("unexpected lexer error: \(error)", file: file, line: line)
        return []
    }
}

/// Concatenation of every token's trivia and text.
func reassembled(_ tokens: [Token]) -> String {
    tokens.map { $0.leadingTrivia.text + $0.text }.joined()
}

enum Fixtures {
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // PBXSyntaxTests
        .deletingLastPathComponent()  // Tests
        .appendingPathComponent("Fixtures")

    static func load(_ relativePath: String) throws -> [UInt8] {
        Array(try Data(contentsOf: directory.appendingPathComponent(relativePath)))
    }

    /// Every `.pbxproj` and `.plist` fixture below `Tests/Fixtures`, sorted by path.
    static func allProjectFiles(under subdirectory: String? = nil) -> [URL] {
        let root = subdirectory.map { directory.appendingPathComponent($0) } ?? directory
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "pbxproj" {
            result.append(url)
        }
        return result.sorted { $0.path < $1.path }
    }
}

/// Lines present in `after` but not `before`, and the reverse, by a simple
/// longest-common-subsequence diff. Lines keep their terminators.
func lineDiff(_ before: String, _ after: String) -> (removed: [String], added: [String]) {
    let a = splitKeepingTerminators(before)
    let b = splitKeepingTerminators(after)
    var prefix = 0
    while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < a.count - prefix, suffix < b.count - prefix,
          a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
    let x = Array(a[prefix..<(a.count - suffix)])
    let y = Array(b[prefix..<(b.count - suffix)])
    var table = [[Int]](repeating: [Int](repeating: 0, count: y.count + 1), count: x.count + 1)
    if !x.isEmpty, !y.isEmpty {
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                table[i][j] = x[i] == y[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
    }
    var removed: [String] = []
    var added: [String] = []
    var i = 0
    var j = 0
    while i < x.count, j < y.count {
        if x[i] == y[j] {
            i += 1
            j += 1
        } else if table[i + 1][j] >= table[i][j + 1] {
            removed.append(x[i])
            i += 1
        } else {
            added.append(y[j])
            j += 1
        }
    }
    removed.append(contentsOf: x[i...])
    added.append(contentsOf: y[j...])
    return (removed, added)
}

private func splitKeepingTerminators(_ string: String) -> [String] {
    var lines: [String] = []
    var current: [UInt8] = []
    for byte in string.utf8 {
        current.append(byte)
        if byte == 0x0A {
            lines.append(String(decoding: current, as: UTF8.self))
            current.removeAll(keepingCapacity: true)
        }
    }
    if !current.isEmpty { lines.append(String(decoding: current, as: UTF8.self)) }
    return lines
}
