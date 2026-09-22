import Foundation
import XCTest

/// release-distribution task 2.1: `--version` (design D1). The binary under
/// test is a development build, so the `-dev` suffix is expected and the
/// `+<hash>` part follows `PBXEDIT_BUILD_HASH`.
final class VersionTests: XCTestCase {
    static let shape = #"^\d+\.\d+\.\d+(-dev(\+[0-9a-f]{7})?)?$"#
    static let variable = "PBXEDIT_BUILD_HASH"

    private func version(_ hash: String?) throws -> RunResult {
        try pbxedit(["--version"], environment: [Self.variable: hash])
    }

    private func line(_ result: RunResult, file: StaticString = #filePath, line: UInt = #line) -> String {
        XCTAssertEqual(result.status, 0, result.stderr, file: file, line: line)
        XCTAssertEqual(result.stderr, "", file: file, line: line)
        XCTAssertTrue(result.stdout.hasSuffix("\n"), result.stdout, file: file, line: line)
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        XCTAssertEqual(lines.count, 1, result.stdout, file: file, line: line)
        return String(lines.first ?? "")
    }

    func testVersionExitsZeroWithOneWellFormedLine() throws {
        let printed = line(try version(nil))
        XCTAssertNotNil(printed.range(of: Self.shape, options: .regularExpression), printed)
        XCTAssertTrue(printed.hasSuffix("-dev"), "the binary under test is a development build: \(printed)")
    }

    func testTheBuildHashIsAppendedToADevelopmentBuild() throws {
        let plain = line(try version(nil))
        let hashed = line(try version("0123abcdef0123abcdef0123abcdef0123abcdef"))
        XCTAssertEqual(hashed, plain + "+0123abc")
        XCTAssertNotNil(hashed.range(of: Self.shape, options: .regularExpression), hashed)
        XCTAssertEqual(line(try version("fedcba9")), plain + "+fedcba9")
    }

    func testAnEmptyOrMalformedHashIsIgnored() throws {
        let plain = line(try version(nil))
        for value in ["", "HEAD", "0123ABCDEF", "012345", "0123abc\n", "v0.1.0"] {
            XCTAssertEqual(line(try version(value)), plain, "value \(value.debugDescription)")
        }
    }

    func testVersionIsInTheUsage() throws {
        let help = try pbxedit(["--help"])
        XCTAssertEqual(help.status, 0, help.stderr)
        XCTAssertTrue(help.stdout.contains("--version"), help.stdout)
    }
}
