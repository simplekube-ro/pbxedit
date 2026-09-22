import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

enum Fixtures {
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // PBXOpsTests
        .deletingLastPathComponent()  // Tests
        .appendingPathComponent("Fixtures")

    static func load(_ relativePath: String) throws -> [UInt8] {
        Array(try Data(contentsOf: directory.appendingPathComponent(relativePath)))
    }

    static func text(_ relativePath: String) throws -> String {
        String(decoding: try load(relativePath), as: UTF8.self)
    }

    /// Every `.pbxproj` below `Tests/Fixtures/<subdirectory>`, sorted by path.
    static func projectFiles(under subdirectory: String) -> [URL] {
        let root = directory.appendingPathComponent(subdirectory)
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

/// Loads a fixture project, failing the test on any error.
func loadProject(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) throws -> Project {
    try Project.load(try Fixtures.load(relativePath))
}

/// The result of `plutil -lint` on `bytes`, written to a temporary file.
func plutilLint(_ bytes: [UInt8]) throws -> (ok: Bool, output: String) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pbxedit-ops-\(UUID().uuidString).pbxproj")
    try Data(bytes).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
    process.arguments = ["-lint", url.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus == 0, String(decoding: data, as: UTF8.self))
}

func assertPlutilLints(_ bytes: [UInt8], _ name: String = "output", file: StaticString = #filePath, line: UInt = #line) {
    do {
        let result = try plutilLint(bytes)
        XCTAssertTrue(result.ok, "plutil -lint rejects \(name): \(result.output)", file: file, line: line)
    } catch {
        XCTFail("plutil could not run: \(error)", file: file, line: line)
    }
}

/// Every operation test asserts this: the rule set, scoped to what the
/// operation touched, reports no error; and the bytes are a plist.
func assertOperationClean(_ project: Project, scope: Set<ObjectID>, file: StaticString = #filePath, line: UInt = #line) {
    let findings = RuleSet.standard.evaluate(project, scope: scope).filter { $0.severity == .error }
    XCTAssertEqual(findings, [], "rule set is not clean over the touched objects", file: file, line: line)
    assertPlutilLints(project.serialize(), file: file, line: line)
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
