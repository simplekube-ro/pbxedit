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
