import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 5.5–5.6: hunks, their counterfactual builds,
/// governed sets, `both` eligibility and keys (design D7).
final class HunkTests: XCTestCase {
    private let a1: ObjectID = "1000000000000000000000A1"

    private func analyse(ours: Project, theirs: Project) throws -> [AnalysedHunk] {
        let base = try MergeFixture.base()
        let merge = ThreeWay.merge(base: TextLines.split(base.serialize()), ours: TextLines.split(ours.serialize()),
                                   theirs: TextLines.split(theirs.serialize()))
        return try AnalysedHunk.analyse(merge)
    }

    // Spec: Conflicting setting values.
    func testConflictingSettingValues() throws {
        let base = try MergeFixture.base()
        let hunks = try analyse(ours: try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: base),
                                theirs: try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a1, of: base))
        XCTAssertEqual(hunks.count, 1)
        let hunk = try XCTUnwrap(hunks.first)
        XCTAssertEqual(hunk.governed.map(\.description), ["1000000000000000000000A1 buildSettings.SWIFT_VERSION"])
        let values = try XCTUnwrap(hunk.values.first)
        XCTAssertEqual(values.base, .string("6.0"))
        XCTAssertEqual(values.ours, .string("5.10"))
        XCTAssertEqual(values.theirs, .string("6.2"))
        XCTAssertEqual(hunk.choices, [.ours, .theirs])
        XCTAssertTrue(hunk.key.hasPrefix("h"))
        XCTAssertEqual(hunk.key.count, 13)
    }

    // Spec: Adjacent insertions.
    func testAdjacentInsertionsOfferBoth() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("OTHER_SWIFT_FLAGS", "-DOURS", in: a1, of: base)
        let theirs = try MergeFixture.setting("OTHER_LDFLAGS", "-ObjC", in: a1, of: base)
        let hunks = try analyse(ours: ours, theirs: theirs)
        XCTAssertEqual(hunks.count, 1)
        let hunk = try XCTUnwrap(hunks.first)
        XCTAssertEqual(hunk.choices, [.ours, .theirs, .both])
        XCTAssertEqual(Set(hunk.governed.map(\.description)),
                       ["1000000000000000000000A1 buildSettings.OTHER_SWIFT_FLAGS", "1000000000000000000000A1 buildSettings.OTHER_LDFLAGS"])
        XCTAssertEqual(hunk.resolution(.both), hunk.hunk.ours + hunk.hunk.theirs)
        let both = try Project.load(hunk.counterfactual(.both))
        let leaves = PlistLeaves(both)
        XCTAssertEqual(leaves[["objects", a1.rawValue, "buildSettings", "OTHER_SWIFT_FLAGS"]], .string("-DOURS"))
        XCTAssertEqual(leaves[["objects", a1.rawValue, "buildSettings", "OTHER_LDFLAGS"]], .string("-ObjC"))
    }

    // Spec: Identical hunks in two configurations have two keys.
    func testIdenticalHunksInTwoConfigurationsHaveTwoKeys() throws {
        let base = try MergeFixture.base()
        var ours = base
        var theirs = base
        for configuration: ObjectID in ["1000000000000000000000A2", "1000000000000000000000A3"] {
            ours = try MergeFixture.setting("SWIFT_VERSION", "5.10", in: configuration, of: ours)
            theirs = try MergeFixture.setting("SWIFT_VERSION", "6.2", in: configuration, of: theirs)
        }
        let hunks = try analyse(ours: ours, theirs: theirs)
        XCTAssertEqual(hunks.count, 2)
        XCTAssertEqual(hunks[0].hunk, hunks[1].hunk, "the same three texts")
        XCTAssertNotEqual(hunks[0].key, hunks[1].key)
        XCTAssertEqual(hunks[0].governed.map(\.description), ["1000000000000000000000A2 buildSettings.SWIFT_VERSION"])
        XCTAssertEqual(hunks[1].governed.map(\.description), ["1000000000000000000000A3 buildSettings.SWIFT_VERSION"])
    }

    func testAHunkWhoseTheirsDoesNotParseIsUnsupported() throws {
        let lines = TextLines.split(try MergeFixture.baseBytes())
        let index = try XCTUnwrap(lines.firstIndex { String(decoding: $0, as: UTF8.self).contains("SWIFT_VERSION = 6.0;") })
        let merge = ThreeWay.Merge(regions: [
            .stable(Array(lines[..<index])),
            .hunk(ThreeWay.Hunk(base: [lines[index]], ours: [Array("\t\t\t\tSWIFT_VERSION = 5.10;\n".utf8)],
                                theirs: [Array("\t\t\t\tSWIFT_VERSION = {\n".utf8)])),
            .stable(Array(lines[(index + 1)...])),
        ])
        XCTAssertThrowsError(try AnalysedHunk.analyse(merge)) { error in
            guard case HunkError.unparseable(let hunk, let side, let message) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(hunk, 1)
            XCTAssertEqual(side, .theirs)
            XCTAssertTrue(message.hasPrefix("717:1: expected"), "the parser's line and column: \(message)")
        }
    }

    func testABothThatWouldDuplicateAKeyIsNotOffered() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("OTHER_SWIFT_FLAGS", "-DOURS", in: a1, of: base)
        // Theirs appends a second SDKROOT with the value the first has: no leaf changes.
        let text = String(decoding: base.serialize(), as: UTF8.self)
            .replacingOccurrences(of: "SWIFT_VERSION = 6.0;\n", with: "SWIFT_VERSION = 6.0;\n\t\t\t\tSDKROOT = iphoneos;\n")
        let theirs = try Project.load(Array(text.utf8))
        XCTAssertEqual(PlistValue.duplicateKeyCount(in: theirs.tree.root), 1)
        let hunks = try analyse(ours: ours, theirs: theirs)
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks.first?.choices, [.ours, .theirs])
    }
}
