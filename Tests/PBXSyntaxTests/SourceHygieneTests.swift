import Foundation
import XCTest

/// CLAUDE.md non-negotiable: no `fatalError`, `try!` or force unwraps in
/// `Sources/PBXSyntax`.
final class SourceHygieneTests: XCTestCase {
    func testNoTrapsInPBXSyntaxSources() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PBXSyntax")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let forbidden = try [
            "fatalError", "try!", "as!", "preconditionFailure", "precondition\\(", "assertionFailure",
            "unsafelyUnwrapped", "[A-Za-z0-9_\\)\\]>]!(?!=)",
        ].map { try NSRegularExpression(pattern: $0) }
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                // Comments and string literals may mention the constructs.
                var code = line
                if let comment = code.range(of: "//") { code = String(code[..<comment.lowerBound]) }
                code = code.replacingOccurrences(of: "\"[^\"]*\"", with: "\"\"", options: .regularExpression)
                for pattern in forbidden {
                    let range = NSRange(code.startIndex..., in: code)
                    XCTAssertNil(
                        pattern.firstMatch(in: code, range: range),
                        "\(file.lastPathComponent):\(number + 1): forbidden construct /\(pattern.pattern)/ in: \(line)")
                }
            }
        }
    }
}
