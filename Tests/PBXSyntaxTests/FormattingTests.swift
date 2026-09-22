import Foundation
import XCTest
@testable import PBXSyntax

/// Task 6.2 — new content is formatted like its neighbours, at the position
/// the caller gives.
final class FormattingTests: XCTestCase {
    // Spec: New content is formatted like its neighbours — Two indentation styles in one file.
    func testEachArrayKeepsItsOwnIndentation() throws {
        let source = try fixtureText("handwritten/mixed-formatting.pbxproj")
        let output = try edited(source) {
            try $0.insert(.string("N1", comment: "deep.swift"), intoArrayAt: ["objects", "G1", "children"])
            try $0.insert(.string("N2", comment: "shallow.swift"), intoArrayAt: ["objects", "G2", "children"], position: .after("B1"))
        }
        let diff = lineDiff(source, output)
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.added, ["\t\t\t\tN1 /* deep.swift */,\r\n", "\t\tN2 /* shallow.swift */,\n"])
    }

    func testAppendingToAnArrayWithoutATrailingCommaKeepsThatStyle() throws {
        let source = try fixtureText("handwritten/mixed-formatting.pbxproj")
        let output = try edited(source) {
            try $0.insert(.string("N2", comment: "last.swift"), intoArrayAt: ["objects", "G2", "children"])
        }
        XCTAssertEqual(
            output,
            replacing(source, "\t\tB2 /* d.swift */\n", with: "\t\tB2 /* d.swift */,\n\t\tN2 /* last.swift */\n"))
    }

    // Spec: New content is formatted like its neighbours — Single-line siblings.
    func testAnEntryAmongSingleLineDictionariesIsWrittenOnOneLine() throws {
        let source = try fixtureText("handwritten/xcode-style.pbxproj")
        let output = try edited(source) {
            try $0.insert(
                NewEntry("AA0000000000000000000013", comment: "New-File.swift", .dictionary([
                    NewEntry("isa", .string("PBXFileReference")),
                    NewEntry("lastKnownFileType", .string("sourcecode.swift")),
                    NewEntry("path", .string("New-File.swift")),
                    NewEntry("sourceTree", .string("<group>")),
                    NewEntry("settings", .dictionary([NewEntry("ATTRIBUTES", .array([.string("Public")]))])),
                ])),
                intoDictionaryAt: ["objects"], position: .after("AA0000000000000000000012"))
        }
        XCTAssertEqual(lineDiff(source, output).added, [
            "\t\tAA0000000000000000000013 /* New-File.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"New-File.swift\"; sourceTree = \"<group>\"; settings = {ATTRIBUTES = (Public, ); }; };\n"
        ])
    }

    func testAnEntryAmongMultiLineDictionariesIsWrittenAcrossLinesAtTheirDepth() throws {
        let source = try fixtureText("handwritten/mixed-formatting.pbxproj")
        let group = NewValue.dictionary([
            NewEntry("isa", .string("PBXGroup")),
            NewEntry("children", .array([.string("X1", comment: "x.swift")])),
            NewEntry("empty", .array([])),
            NewEntry("path", .string("New Group")),
        ])
        let deep = try edited(source) {
            try $0.insert(NewEntry("N1", comment: "New Group", group), intoDictionaryAt: ["objects"], position: .after("G1"))
        }
        XCTAssertEqual(lineDiff(source, deep).added, [
            "\t\tN1 /* New Group */ = {\n", "\t\t\tisa = PBXGroup;\n", "\t\t\tchildren = (\n", "\t\t\t\tX1 /* x.swift */,\n",
            "\t\t\t);\n", "\t\t\tempty = (\n", "\t\t\t);\n", "\t\t\tpath = \"New Group\";\n", "\t\t};\n",
        ])
        let shallow = try edited(source) {
            try $0.insert(NewEntry("N2", comment: "New Group", group), intoDictionaryAt: ["objects"], position: .after("G2"))
        }
        XCTAssertEqual(lineDiff(source, shallow).added, [
            "\tN2 /* New Group */ = {\n", "\t\tisa = PBXGroup;\n", "\t\tchildren = (\n", "\t\t\tX1 /* x.swift */,\n",
            "\t\t);\n", "\t\tempty = (\n", "\t\t);\n", "\t\tpath = \"New Group\";\n", "\t};\n",
        ])
    }

    func testLayoutCanBeForced() throws {
        let source = "{\n\tobjects = {\n\t\tA = {isa = X; };\n\t};\n}\n"
        let value = NewValue.dictionary([NewEntry("isa", .string("PBXGroup")), NewEntry("children", .array([]))])
        XCTAssertEqual(
            try edited(source) { try $0.insert(NewEntry("G", value), intoDictionaryAt: ["objects"], layout: .multiLine) },
            replacing(source, "\t};\n}", with: "\t\tG = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t};\n\t};\n}"))
        let multi = "{\n\tobjects = {\n\t\tG = {\n\t\t\tisa = PBXGroup;\n\t\t};\n\t};\n}\n"
        XCTAssertEqual(
            try edited(multi) {
                try $0.insert(NewEntry("A", .dictionary([NewEntry("isa", .string("X"))])), intoDictionaryAt: ["objects"], layout: .singleLine)
            },
            replacing(multi, "\t\t};\n\t};", with: "\t\t};\n\t\tA = {isa = X; };\n\t};"))
    }

    // Spec: New content is formatted like its neighbours — Empty array.
    func testInsertIntoAnEmptyMultiLineArray() throws {
        let source = try fixtureText("handwritten/xcode-style.pbxproj")
        let output = try edited(source) {
            try $0.insert(.string("AA0000000000000000000011", comment: "App.swift"),
                          intoArrayAt: ["objects", "AA0000000000000000000022", "children"])
        }
        XCTAssertEqual(
            output,
            replacing(source, "\t\t\tchildren = (\n\t\t\t);\n\t\t\tpath = Empty;",
                      with: "\t\t\tchildren = (\n\t\t\t\tAA0000000000000000000011 /* App.swift */,\n\t\t\t);\n\t\t\tpath = Empty;"))
    }

    func testInsertIntoAnEmptyMultiLineDictionary() throws {
        let source = "{\r\n\tclasses = {\r\n\t};\r\n}\r\n"
        XCTAssertEqual(
            try edited(source) { try $0.insert(NewEntry("k", .string("v")), intoDictionaryAt: ["classes"]) },
            "{\r\n\tclasses = {\r\n\t\tk = v;\r\n\t};\r\n}\r\n")
    }

    func testInsertIntoEmptySingleLineContainers() throws {
        XCTAssertEqual(try edited("{ a = (); }") { try $0.insert(.string("x"), intoArrayAt: ["a"]) }, "{ a = (x, ); }")
        XCTAssertEqual(try edited("{ a = ( ); }") { try $0.insert(.string("x"), intoArrayAt: ["a"]) }, "{ a = (x, ); }")
        XCTAssertEqual(try edited("{ d = {}; }") { try $0.insert(NewEntry("k", .string("v")), intoDictionaryAt: ["d"]) }, "{ d = {k = v; }; }")
    }

    func testInsertIntoSingleLineContainers() throws {
        let source = "{ s = {ATTRIBUTES = (Public, ); }; }"
        XCTAssertEqual(
            try edited(source) { try $0.insert(.string("Weak"), intoArrayAt: ["s", "ATTRIBUTES"]) },
            "{ s = {ATTRIBUTES = (Public, Weak, ); }; }")
        XCTAssertEqual(
            try edited(source) { try $0.insert(.string("Weak"), intoArrayAt: ["s", "ATTRIBUTES"], position: .first) },
            "{ s = {ATTRIBUTES = (Weak, Public, ); }; }")
        XCTAssertEqual(
            try edited(source) { try $0.insert(NewEntry("COMPILER_FLAGS", .string("-w")), intoDictionaryAt: ["s"]) },
            "{ s = {ATTRIBUTES = (Public, ); COMPILER_FLAGS = \"-w\"; }; }")
        XCTAssertEqual(
            try edited(source) { try $0.insert(NewEntry("COMPILER_FLAGS", .string("-w")), intoDictionaryAt: ["s"], position: .first) },
            "{ s = {COMPILER_FLAGS = \"-w\"; ATTRIBUTES = (Public, ); }; }")
        XCTAssertEqual(
            try edited("{ f = (a, b, c); }") { try $0.insert(.string("x"), intoArrayAt: ["f"], position: .after("a")) },
            "{ f = (a, x, b, c); }")
        XCTAssertEqual(
            try edited("{ f = (a, b, c); }") { try $0.insert(.string("x", comment: "note"), intoArrayAt: ["f"]) },
            "{ f = (a, b, c, x /* note */); }")
    }

    // Spec: Caller controls position.
    func testPositions() throws {
        let source = "{\n\tc = (\n\t\tA1 /* a */,\n\t\tB2 /* b */,\n\t\tC3 /* c */,\n\t);\n}\n"
        func insert(_ position: InsertPosition) throws -> [String] {
            let output = try edited(source) { try $0.insert(.string("NEW", comment: "n"), intoArrayAt: ["c"], position: position) }
            let diff = lineDiff(source, output)
            XCTAssertEqual(diff.removed, [], "\(position)")
            XCTAssertEqual(diff.added, ["\t\tNEW /* n */,\n"], "\(position)")
            let tree = try XCTUnwrap(parsed(output))
            return try XCTUnwrap(tree.node(at: ["c"])?.array).elements.compactMap { $0.value.stringValue }
        }
        // Spec scenario: Insert after a sibling.
        XCTAssertEqual(try insert(.after("B2")), ["A1", "B2", "NEW", "C3"])
        XCTAssertEqual(try insert(.before("B2")), ["A1", "NEW", "B2", "C3"])
        XCTAssertEqual(try insert(.first), ["NEW", "A1", "B2", "C3"])
        XCTAssertEqual(try insert(.last), ["A1", "B2", "C3", "NEW"])
        XCTAssertEqual(try insert(.at(0)), ["NEW", "A1", "B2", "C3"])
        XCTAssertEqual(try insert(.at(2)), ["A1", "B2", "NEW", "C3"])
        XCTAssertEqual(try insert(.at(3)), ["A1", "B2", "C3", "NEW"])
    }

    func testDictionaryPositions() throws {
        let source = "{\n\ta = 1;\n\tb = 2;\n}\n"
        func insert(_ position: InsertPosition) throws -> String {
            try edited(source) { try $0.insert(NewEntry("n", .string("0")), intoDictionaryAt: [], position: position) }
        }
        XCTAssertEqual(try insert(.first), "{\n\tn = 0;\n\ta = 1;\n\tb = 2;\n}\n")
        XCTAssertEqual(try insert(.before("b")), "{\n\ta = 1;\n\tn = 0;\n\tb = 2;\n}\n")
        XCTAssertEqual(try insert(.after("a")), "{\n\ta = 1;\n\tn = 0;\n\tb = 2;\n}\n")
        XCTAssertEqual(try insert(.last), "{\n\ta = 1;\n\tb = 2;\n\tn = 0;\n}\n")
    }

    /// `.after` puts the new line under the named sibling's line; `.before`
    /// and `.first` put it directly above, below any comments that precede
    /// the sibling — so a new first entry stays inside its section.
    func testPositionsRelativeToSectionComments() throws {
        let source = try fixtureText("handwritten/xcode-style.pbxproj")
        let entry = NewEntry("NEWREF", comment: "N.swift", .dictionary([NewEntry("isa", .string("PBXFileReference"))]))
        let line = "\t\tNEWREF /* N.swift */ = {isa = PBXFileReference; };\n"
        let before = try edited(source) {
            try $0.insert(entry, intoDictionaryAt: ["objects"], position: .before("AA0000000000000000000011"))
        }
        XCTAssertEqual(before, replacing(source, "/* Begin PBXFileReference section */\n", with: "/* Begin PBXFileReference section */\n" + line))
        let after = try edited(source) {
            try $0.insert(entry, intoDictionaryAt: ["objects"], position: .after("TVOSTEST0002"))
        }
        XCTAssertEqual(after, replacing(source, "/* End PBXFileReference section */\n", with: line + "/* End PBXFileReference section */\n"))
        let last = try edited(source) { try $0.insert(entry, intoDictionaryAt: ["objects"]) }
        // The template here is the multi-line build phase, so the value is laid out like it.
        let multiLine = "\t\tNEWREF /* N.swift */ = {\n\t\t\tisa = PBXFileReference;\n\t\t};\n"
        XCTAssertEqual(last, replacing(source, "/* End PBXSourcesBuildPhase section */\n", with: multiLine + "/* End PBXSourcesBuildPhase section */\n"))
    }

    func testCommentsAreNeverCopiedFromTheTemplate() throws {
        let source = "{\n\tc = (\n\t\tA1 /* a */,\n\t);\n}\n"
        XCTAssertEqual(
            try edited(source) { try $0.insert(.string("B2"), intoArrayAt: ["c"]) },
            "{\n\tc = (\n\t\tA1 /* a */,\n\t\tB2,\n\t);\n}\n")
    }
}
