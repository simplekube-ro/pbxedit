import Foundation
import XCTest
@testable import PBXSyntax

final class RoundTripTests: XCTestCase {
    private func assertRoundTrips(_ input: [UInt8], _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        switch SyntaxTree.parse(input) {
        case .failure(let error):
            XCTFail("\(name) does not parse: \(error)", file: file, line: line)
        case .success(let tree):
            let output = tree.serialize()
            XCTAssertTrue(output == input, "\(name) does not round-trip byte for byte", file: file, line: line)
        }
    }

    // Spec: Byte-exact round trip — Real project file (Xcode layout, UTF-8
    // header, section comments). The corpus test covers files Xcode wrote.
    func testXcodeStyleFileRoundTrips() throws {
        let input = try Fixtures.load("handwritten/xcode-style.pbxproj")
        XCTAssertTrue(text(input).hasPrefix("// !$*UTF8*$!\n"))
        XCTAssertTrue(text(input).contains("/* Begin PBXGroup section */"))
        assertRoundTrips(input, "xcode-style.pbxproj")
    }

    // Spec: Byte-exact round trip — Mixed formatting.
    func testMixedFormattingRoundTrips() throws {
        let input = try Fixtures.load("handwritten/mixed-formatting.pbxproj")
        XCTAssertTrue(input.contains(0x0D), "fixture must contain CRLF lines")
        XCTAssertNotEqual(input.last, 0x0A, "fixture must not end with a newline")
        assertRoundTrips(input, "mixed-formatting.pbxproj")
    }

    func testEveryFixtureRoundTrips() throws {
        let files = Fixtures.allProjectFiles()
        XCTAssertGreaterThanOrEqual(files.count, 2)
        for url in files {
            assertRoundTrips(Array(try Data(contentsOf: url)), url.lastPathComponent)
        }
    }

    func testSmallInputsRoundTrip() {
        let inputs = [
            "{}", " { } ", "()", "(a)", "(a,)", "( a , b , )", "\"\"", "''", "<>", "< 0f >",
            "{a=b;}", "{ a = ( { b = c; }, ); }\n", "\u{FEFF}{}\n", "{\r\n}\r\n", "{}\r", "{\n}\n\n\n",
            "{ \"k\\\"\" = 'v\\''; }", "/* only */ x // tail",
        ]
        for input in inputs {
            assertRoundTrips(bytes(input), input.debugDescription)
        }
    }

    func testStringSerialization() throws {
        let source = "{ a = 1; }\n"
        XCTAssertEqual(try XCTUnwrap(parsed(source)).description, source)
    }
}
