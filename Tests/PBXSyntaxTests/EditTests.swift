import Foundation
import XCTest
@testable import PBXSyntax

/// Task 6.1 — every assertion is on the diff against the input.
final class EditTests: XCTestCase {
    /// A project-shaped file of at least 9,000 lines with one twelve-element array.
    private func largeFile() -> String {
        var lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tobjects = {", "", "/* Begin PBXFileReference section */"]
        for index in 0..<9_000 {
            let id = "F" + String(repeating: "0", count: 5 - String(index).count) + String(index)
            lines.append("\t\t\(id) /* File\(index).swift */ = {isa = PBXFileReference; path = File\(index).swift; sourceTree = \"<group>\"; };")
        }
        lines.append(contentsOf: ["/* End PBXFileReference section */", "", "/* Begin PBXGroup section */", "\t\tG1 /* Sources */ = {", "\t\t\tisa = PBXGroup;", "\t\t\tchildren = ("])
        for index in 0..<12 {
            lines.append("\t\t\t\tF0000\(index % 10)\(index >= 10 ? "X" : "") /* File\(index).swift */,")
        }
        lines.append(contentsOf: ["\t\t\t);", "\t\t\tsourceTree = \"<group>\";", "\t\t};", "/* End PBXGroup section */", "\t};", "\trootObject = P1 /* Project object */;", "}", ""])
        return lines.joined(separator: "\n")
    }

    // Spec: Edits leave other bytes untouched — Insert into an array.
    func testInsertIntoAnArrayOfALargeFileAddsExactlyOneLine() throws {
        let source = largeFile()
        XCTAssertGreaterThanOrEqual(source.split(separator: "\n", omittingEmptySubsequences: false).count, 9_000)
        let tree = try XCTUnwrap(parsed(source))
        XCTAssertEqual(tree.node(at: ["objects", "G1", "children"])?.array?.elements.count, 12)
        let output = try edited(source) {
            try $0.insert(.string("NEW1", comment: "New.swift"), intoArrayAt: ["objects", "G1", "children"])
        }
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.added, ["\t\t\t\tNEW1 /* New.swift */,\n"])
    }

    // Spec: Edits leave other bytes untouched — Remove from an array.
    func testRemovingAnArrayElementRemovesExactlyItsLineCommentIncluded() throws {
        let source = "{\n\tchildren = (\n\t\tA1 /* a */,\n\t\tA2 /* b */,\n\t\tA3 /* third, with a comment */,\n\t\tA4 /* d */,\n\t\tA5 /* e */,\n\t);\n}\n"
        let output = try edited(source) { try $0.removeElement(at: 2, fromArrayAt: ["children"]) }
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.removed, ["\t\tA3 /* third, with a comment */,\n"])
        XCTAssertEqual(diff.added, [])
    }

    // Spec: Edits leave other bytes untouched — Replace a value.
    func testReplacingAValueChangesOnlyTheValueBytes() throws {
        let source = try fixtureText("handwritten/xcode-style.pbxproj")
        let output = try edited(source) {
            try $0.replaceValue(at: ["objects", "AA0000000000000000000011", "path"], with: .string("Renamed App.swift"))
        }
        XCTAssertEqual(
            output,
            replacing(source, "path = App.swift; sourceTree", with: "path = \"Renamed App.swift\"; sourceTree"))
    }

    func testInsertingADictionaryEntryAddsExactlyOneLine() throws {
        let source = try fixtureText("handwritten/xcode-style.pbxproj")
        let output = try edited(source) {
            try $0.insert(
                NewEntry("AA0000000000000000000003", comment: "New.swift in Sources", .dictionary([
                    NewEntry("isa", .string("PBXBuildFile")),
                    NewEntry("fileRef", .string("AA0000000000000000000013", comment: "New.swift")),
                ])),
                intoDictionaryAt: ["objects"], position: .after("AA0000000000000000000001"))
        }
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.added, [
            "\t\tAA0000000000000000000003 /* New.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000013 /* New.swift */; };\n"
        ])
    }

    func testRemovingADictionaryEntryRemovesExactlyItsLines() throws {
        let source = try fixtureText("handwritten/xcode-style.pbxproj")
        let output = try edited(source) {
            try $0.removeEntry(forKey: "AA0000000000000000000022", fromDictionaryAt: ["objects"])
        }
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.added, [])
        XCTAssertEqual(diff.removed, [
            "\t\tAA0000000000000000000022 /* Empty */ = {\n", "\t\t\tisa = PBXGroup;\n", "\t\t\tchildren = (\n",
            "\t\t\t);\n", "\t\t\tpath = Empty;\n", "\t\t\tsourceTree = \"<group>\";\n", "\t\t};\n",
        ])
    }

    /// The section comments before a section's first entry are that entry's
    /// leading trivia (design D2); removing the entry must not take them.
    func testRemovingTheFirstEntryOfASectionKeepsTheSectionComments() throws {
        let source = try fixtureText("handwritten/xcode-style.pbxproj")
        let output = try edited(source) {
            try $0.removeEntry(forKey: "AA0000000000000000000011", fromDictionaryAt: ["objects"])
        }
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.added, [])
        XCTAssertEqual(diff.removed.count, 1)
        XCTAssertTrue(diff.removed.first?.hasPrefix("\t\tAA0000000000000000000011 /* App.swift */ = {isa = PBXFileReference;") ?? false)
        XCTAssertTrue(output.contains("/* End PBXBuildFile section */\n\n/* Begin PBXFileReference section */\n\t\tAA0000000000000000000012"))
    }

    func testRemovingTheLastEntryKeepsTheCommentsBeforeTheClosingBrace() throws {
        let source = try fixtureText("handwritten/xcode-style.pbxproj")
        let output = try edited(source) {
            try $0.removeEntry(forKey: "AA0000000000000000000031", fromDictionaryAt: ["objects"])
        }
        XCTAssertTrue(output.contains("/* Begin PBXSourcesBuildPhase section */\n/* End PBXSourcesBuildPhase section */\n\t};"))
        XCTAssertEqual(lineDiff(source, output).removed.count, 9)
    }

    func testRemovingTheLastElementOfAnArrayWithoutATrailingComma() throws {
        let source = "{\n\tc = (\n\t\tB1 /* c.swift */,\n\t\tB2 /* d.swift */\n\t);\n}\n"
        let output = try edited(source) { try $0.removeElement(at: 1, fromArrayAt: ["c"]) }
        XCTAssertEqual(output, "{\n\tc = (\n\t\tB1 /* c.swift */\n\t);\n}\n", "the no-trailing-comma style is kept")
    }

    func testRemovingTheOnlyElement() throws {
        XCTAssertEqual(
            try edited("{\n\tc = (\n\t\tB1 /* c.swift */,\n\t);\n}\n") { try $0.removeElement(at: 0, fromArrayAt: ["c"]) },
            "{\n\tc = (\n\t);\n}\n")
        XCTAssertEqual(try edited("{ c = (Public, ); }") { try $0.removeElement(at: 0, fromArrayAt: ["c"]) }, "{ c = (); }")
        XCTAssertEqual(try edited("{ c = (a /* x */); }") { try $0.removeElement(at: 0, fromArrayAt: ["c"]) }, "{ c = (); }")
    }

    func testRemovingFromASingleLineArray() throws {
        let source = "{ f = (ios, tvos, macos, ); }"
        XCTAssertEqual(try edited(source) { try $0.removeElement(at: 0, fromArrayAt: ["f"]) }, "{ f = (tvos, macos, ); }")
        XCTAssertEqual(try edited(source) { try $0.removeElement(at: 1, fromArrayAt: ["f"]) }, "{ f = (ios, macos, ); }")
        XCTAssertEqual(try edited(source) { try $0.removeElement(at: 2, fromArrayAt: ["f"]) }, "{ f = (ios, tvos, ); }")
    }

    func testRemovingFromASingleLineDictionary() throws {
        let source = "{ A = {isa = X; fileRef = B2 /* Foo.swift */; settings = {k = v; }; }; }"
        XCTAssertEqual(
            try edited(source) { try $0.removeEntry(forKey: "isa", fromDictionaryAt: ["A"]) },
            "{ A = {fileRef = B2 /* Foo.swift */; settings = {k = v; }; }; }")
        XCTAssertEqual(
            try edited(source) { try $0.removeEntry(forKey: "fileRef", fromDictionaryAt: ["A"]) },
            "{ A = {isa = X; settings = {k = v; }; }; }")
    }

    func testRemoveElementByValue() throws {
        let source = "{\n\tc = (\n\t\tA1 /* a */,\n\t\tA2 /* b */,\n\t);\n}\n"
        XCTAssertEqual(
            try edited(source) { try $0.removeElement(equalTo: "A1", fromArrayAt: ["c"]) },
            "{\n\tc = (\n\t\tA2 /* b */,\n\t);\n}\n")
    }

    func testReplacingAValueWithACommentUpdatesItsAnnotation() throws {
        let source = "{\n\tfileRef = B2 /* Old.swift */;\n\tc = (\n\t\tA1 /* Old.swift in Sources */,\n\t\tA2\n\t);\n}\n"
        XCTAssertEqual(
            try edited(source) { try $0.replaceValue(at: ["fileRef"], with: .string("B3", comment: "New.swift")) },
            replacing(source, "B2 /* Old.swift */;", with: "B3 /* New.swift */;"))
        XCTAssertEqual(
            try edited(source) { try $0.replaceValue(at: ["c", 0], with: .string("A9", comment: "New.swift in Sources")) },
            replacing(source, "A1 /* Old.swift in Sources */,", with: "A9 /* New.swift in Sources */,"))
        XCTAssertEqual(
            try edited(source) { try $0.replaceValue(at: ["c", 1], with: .string("A7", comment: "added")) },
            replacing(source, "\t\tA2\n", with: "\t\tA7 /* added */\n"))
        XCTAssertEqual(
            try edited(source) { try $0.replaceValue(at: ["fileRef"], with: .string("B4")) },
            replacing(source, "B2 /* Old.swift */;", with: "B4 /* Old.swift */;"),
            "without a comment the existing trivia is left alone")
    }

    func testReplacingAContainerValueKeepsItsLayout() throws {
        let source = "{\n\tc = (\n\t\tA1 /* a */,\n\t);\n\ts = {ATTRIBUTES = (Public, ); };\n}\n"
        XCTAssertEqual(
            try edited(source) {
                try $0.replaceValue(at: ["c"], with: .array([.string("Z1", comment: "z"), .string("Z2")]))
            },
            "{\n\tc = (\n\t\tZ1 /* z */,\n\t\tZ2,\n\t);\n\ts = {ATTRIBUTES = (Public, ); };\n}\n")
        XCTAssertEqual(
            try edited(source) {
                try $0.replaceValue(at: ["s"], with: .dictionary([NewEntry("ATTRIBUTES", .array([.string("Private")]))]))
            },
            replacing(source, "(Public, )", with: "(Private, )"))
    }

    func testReplacingTheRootValue() throws {
        XCTAssertEqual(try edited("// h\n{ a = b; }\n") { try $0.replaceValue(at: [], with: .string("x y")) }, "// h\n\"x y\"\n")
    }

    /// Motivation table, row 1, at the edit level: `X` and `X0`.
    func testEditsAddressKeysExactly() throws {
        let source = "{\n\tobjects = {\n\t\tTVOSTEST00020 = {name = long; };\n\t\tTVOSTEST0002 = {name = short; };\n\t};\n}\n"
        XCTAssertEqual(
            try edited(source) { try $0.replaceValue(at: ["objects", "TVOSTEST0002", "name"], with: .string("edited")) },
            replacing(source, "name = short;", with: "name = edited;"))
        XCTAssertEqual(
            try edited(source) { try $0.removeEntry(forKey: "TVOSTEST0002", fromDictionaryAt: ["objects"]) },
            replacing(source, "\t\tTVOSTEST0002 = {name = short; };\n", with: ""))
        XCTAssertThrowsError(try edited(source) { try $0.removeEntry(forKey: "TVOSTEST000", fromDictionaryAt: ["objects"]) })
    }

    func testNodeAtPath() throws {
        let tree = try XCTUnwrap(parsed(try fixtureText("handwritten/xcode-style.pbxproj")))
        XCTAssertEqual(tree.node(at: ["objects", "AA0000000000000000000021", "children", 1])?.stringValue, "AA0000000000000000000012")
        XCTAssertEqual(tree.node(at: [])?.dictionary?.keys.first, "archiveVersion")
        XCTAssertNil(tree.node(at: ["objects", "missing"]))
        XCTAssertNil(tree.node(at: ["objects", "AA0000000000000000000021", "children", 3]))
        XCTAssertNil(tree.node(at: ["objects", "AA0000000000000000000021", "children", -1]))
        XCTAssertNil(tree.node(at: ["archiveVersion", "x"]))
    }

    func testEditErrors() throws {
        let source = "{\n\ta = (\n\t\tx,\n\t);\n\td = {\n\t\tk = v;\n\t};\n}\n"
        func attempt(_ edit: (inout SyntaxTree) throws -> Void) -> EditError? {
            guard var tree = parsed(source) else { return nil }
            let before = tree
            do {
                try edit(&tree)
                XCTFail("expected an error")
                return nil
            } catch {
                XCTAssertEqual(tree, before, "a failed edit must leave the tree unchanged")
                return error as? EditError
            }
        }
        XCTAssertEqual(attempt { try $0.insert(.string("y"), intoArrayAt: ["missing"]) }, .pathNotFound(["missing"]))
        XCTAssertEqual(attempt { try $0.insert(.string("y"), intoArrayAt: ["d"]) }, .notAnArray(["d"]))
        XCTAssertEqual(attempt { try $0.insert(NewEntry("k2", .string("v")), intoDictionaryAt: ["a"]) }, .notADictionary(["a"]))
        XCTAssertEqual(attempt { try $0.insert(NewEntry("k", .string("v")), intoDictionaryAt: ["d"]) }, .duplicateKey("k"))
        XCTAssertEqual(attempt { try $0.insert(.string("y"), intoArrayAt: ["a"], position: .after("nope")) }, .siblingNotFound("nope"))
        XCTAssertEqual(attempt { try $0.insert(.string("y"), intoArrayAt: ["a"], position: .at(2)) }, .indexOutOfRange(2))
        XCTAssertEqual(attempt { try $0.insert(.string("y"), intoArrayAt: ["a"], position: .at(-1)) }, .indexOutOfRange(-1))
        XCTAssertEqual(attempt { try $0.removeElement(at: 1, fromArrayAt: ["a"]) }, .indexOutOfRange(1))
        XCTAssertEqual(attempt { try $0.removeElement(equalTo: "nope", fromArrayAt: ["a"]) }, .siblingNotFound("nope"))
        XCTAssertEqual(attempt { try $0.removeEntry(forKey: "nope", fromDictionaryAt: ["d"]) }, .pathNotFound(["d", "nope"]))
        XCTAssertEqual(attempt { try $0.replaceValue(at: ["d", "nope"], with: .string("v")) }, .pathNotFound(["d", "nope"]))
        XCTAssertEqual(attempt { try $0.insert(.string("y", comment: "bad */ comment"), intoArrayAt: ["a"]) }, .invalidComment("bad */ comment"))
        var deep = NewValue.string("leaf")
        for _ in 0..<SyntaxTree.maximumNestingDepth { deep = .array([deep]) }
        XCTAssertEqual(attempt { try $0.insert(deep, intoArrayAt: ["a"]) }, .nestingTooDeep)
    }
}
