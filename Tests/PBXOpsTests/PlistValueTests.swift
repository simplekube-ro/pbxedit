import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 2.1–2.2: a comment-free value view of a tree and its
/// leaf flattening (design D8), the vocabulary of check C and of hunks.
final class PlistValueTests: XCTestCase {
    private func tree(_ text: String) throws -> SyntaxTree { try SyntaxTree.parse(text).get() }

    func testATreeIsReadWithoutTrivia() throws {
        let commented = try tree("{ /* c */ a = (x /* one */, \"y\", ); b = { c = <0a0b>; }; }")
        let plain = try tree("{\n\ta = (\n\t\tx,\n\t\ty\n\t);\n\tb = {c = <0A 0B>;};\n}")
        XCTAssertEqual(PlistValue(commented.root), PlistValue(plain.root))
        XCTAssertEqual(PlistValue(commented.root), .dictionary([
            .init(key: "a", value: .array([.string("x"), .string("y")])),
            .init(key: "b", value: .dictionary([.init(key: "c", value: .data([0x0A, 0x0B]))])),
        ]))
    }

    func testStringsCompareByteForByte() {
        XCTAssertNotEqual(PlistValue.string("\u{E9}"), PlistValue.string("e\u{301}"), "canonically equivalent is not equal")
    }

    func testLeavesKeyEveryBuildSettingByObjectID() throws {
        let project = try loadProject(MergeFixture.basePath)
        let leaves = PlistLeaves(project.tree)
        for suffix in ["A2", "A3", "A4", "A5", "A6"] {
            let id = "1000000000000000000000\(suffix)"
            XCTAssertEqual(leaves[["objects", id, "buildSettings", "PRODUCT_NAME"]], .string("$(TARGET_NAME)"), id)
        }
        XCTAssertEqual(leaves[["objects", "1000000000000000000000A1", "buildSettings", "SWIFT_VERSION"]], .string("6.0"))
        XCTAssertEqual(leaves[["objects", "1000000000000000000000A1", "name"]], .string("Debug"))
        let path = LeafPath(["objects", "1000000000000000000000A1", "buildSettings", "SWIFT_VERSION"])
        XCTAssertEqual(path.description, "1000000000000000000000A1 buildSettings.SWIFT_VERSION")
        XCTAssertEqual(path.objectID, "1000000000000000000000A1")
        XCTAssertEqual(LeafPath(["rootObject"]).description, "rootObject")
        XCTAssertNil(LeafPath(["rootObject"]).objectID)
    }

    func testAnArrayIsOneOrderedLeaf() throws {
        let project = try loadProject(MergeFixture.basePath)
        let leaves = PlistLeaves(project.tree)
        let phases = leaves[["objects", "DD0000000000000000000001", "buildPhases"]]
        XCTAssertEqual(phases, .array([.string("CC0000000000000000000001"), .string("CC0000000000000000000002"), .string("CC0000000000000000000003")]))
        XCTAssertNil(leaves[["objects", "DD0000000000000000000001", "buildPhases", "0"]])
        let reordered = try tree("{ a = (y, x); }")
        XCTAssertNotEqual(PlistLeaves(reordered)[["a"]], PlistLeaves(try tree("{ a = (x, y); }"))[["a"]])
    }

    func testAnEmptyDictionaryIsALeaf() throws {
        let leaves = PlistLeaves(try tree("{ classes = { }; a = { b = c; }; }"))
        XCTAssertEqual(leaves[["classes"]], .dictionary([]))
        XCTAssertNil(leaves[["a"]])
        XCTAssertEqual(leaves[["a", "b"]], .string("c"))
        XCTAssertEqual(leaves.paths, [["classes"], ["a", "b"]].map(LeafPath.init))
    }

    func testTheFirstEntryWinsOnADuplicateKeyAndDuplicatesAreCounted() throws {
        let duplicated = try tree("{ a = { k = 1; k = 2; j = 3; }; b = x; b = y; c = { k = 1; }; }")
        let leaves = PlistLeaves(duplicated)
        XCTAssertEqual(leaves[["a", "k"]], .string("1"))
        XCTAssertEqual(leaves[["b"]], .string("x"))
        XCTAssertEqual(PlistValue.duplicateKeyCount(in: duplicated.root), 2)
        XCTAssertEqual(PlistValue.duplicateKeyCount(in: try tree("{ a = { k = 1; }; b = { k = 1; }; }").root), 0)
        XCTAssertEqual(PlistValue.duplicateKeyCount(in: try loadProject(MergeFixture.basePath).tree.root), 0)
    }
}
