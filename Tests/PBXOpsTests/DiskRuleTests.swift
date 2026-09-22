import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// An in-memory file system: a set of file paths; directories are implied.
/// Counts every call so a test can prove the reader was never consulted.
final class MemoryDisk: DiskReader, @unchecked Sendable {
    let files: Set<String>
    private(set) var calls = 0

    init(_ files: [String]) { self.files = Set(files) }

    private var directories: Set<String> {
        var result: Set<String> = [""]
        for file in files {
            var path = file
            while let slash = path.lastIndex(of: "/") {
                path = String(path[..<slash])
                result.insert(path)
            }
        }
        return result
    }

    func exists(_ path: String) -> Bool {
        calls += 1
        return files.contains(path) || directories.contains(path)
    }

    func files(in path: String) -> [String] {
        calls += 1
        let prefix = path.isEmpty ? "" : path + "/"
        return files.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
            .map { String($0.dropFirst(prefix.count)) }.sorted()
    }
}

/// Task 5.1: D1 and D2 against an in-memory `DiskReader`.
final class DiskRuleTests: XCTestCase {
    /// Every file `model/app.pbxproj` references, plus the synchronized folder's contents.
    static let complete = [
        "App/AppMain.swift", "App/Views/Foo.swift", "App/Shared.swift", "AppTests/Views/FooTests.swift",
        "AppTests/Foo/Bar.swift", "App/Extension/ExtensionMain.swift", "App/Resources/en.lproj/Localizable.strings",
        "App/Generated/User.swift", "App/Generated/Models/Account.swift",
    ]

    private func disk(_ findings: [Finding]) -> [Finding] { findings.filter { $0.rule == .D1 || $0.rule == .D2 } }

    func testACompleteDiskProducesNoDiskFindings() throws {
        let project = try loadProject("model/app.pbxproj")
        let reader = MemoryDisk(DiskRuleTests.complete)
        XCTAssertEqual(disk(RuleSet.standard.evaluate(project, disk: reader)), [])
        XCTAssertGreaterThan(reader.calls, 0)
    }

    // Spec: Disk rules are opt-in — D1 on a deleted file.
    func testD1OnADeletedFile() throws {
        let project = try loadProject("model/app.pbxproj")
        let reader = MemoryDisk(DiskRuleTests.complete.filter { $0 != "App/Views/Foo.swift" })
        XCTAssertEqual(disk(RuleSet.standard.evaluate(project, disk: reader)), [
            Finding(rule: .D1, object: "AA0000000000000000000120", path: "App/Views/Foo.swift",
                    message: "file reference AA0000000000000000000120 resolves to App/Views/Foo.swift, which does not exist"),
        ])
    }

    func testD1SkipsProductsAndReferencesThatAreNotProjectRelative() throws {
        // Foundation.framework (SDKROOT) and the three products (BUILT_PRODUCTS_DIR) never exist under the source root.
        let project = try loadProject("model/app.pbxproj")
        let reader = MemoryDisk(DiskRuleTests.complete)
        XCTAssertEqual(disk(RuleSet.standard.evaluate(project, disk: reader)).filter { $0.rule == .D1 }, [])
    }

    func testD2OnAnUnreferencedSourceInAGroupDirectory() throws {
        let project = try loadProject("model/app.pbxproj")
        let reader = MemoryDisk(DiskRuleTests.complete + ["App/Views/Bar.swift", "App/Views/notes.txt", "App/Views/Assets.xcassets"])
        XCTAssertEqual(disk(RuleSet.standard.evaluate(project, disk: reader)), [
            Finding(rule: .D2, object: nil, path: "App/Views/Assets.xcassets", related: ["AA0000000000000000000003"],
                    message: "App/Views/Assets.xcassets is on disk in the directory of group AA0000000000000000000003 (App/Views) but no file reference resolves to it"),
            Finding(rule: .D2, object: nil, path: "App/Views/Bar.swift", related: ["AA0000000000000000000003"],
                    message: "App/Views/Bar.swift is on disk in the directory of group AA0000000000000000000003 (App/Views) but no file reference resolves to it"),
        ])
    }

    func testD2IgnoresSubdirectoriesWithoutAGroup() throws {
        // App/Views/Sub has no group, so its contents are not "inside a directory some group resolves to".
        let project = try loadProject("model/app.pbxproj")
        let reader = MemoryDisk(DiskRuleTests.complete + ["App/Views/Sub/Deep.swift"])
        XCTAssertEqual(disk(RuleSet.standard.evaluate(project, disk: reader)), [])
    }

    // Spec: Disk rules are opt-in — D2 respects synchronized folders.
    func testD2RespectsSynchronizedFolders() throws {
        // App/Generated is a synchronized root group; App/Generated/User.swift is unreferenced and covered.
        // A group resolving to App/Generated would make D2 look there; give it one to prove the exemption.
        let source = try Fixtures.text("model/app.pbxproj")
        let withGroup = replacing(
            source, "\t\t\t\tAA0000000000000000000010 /* Resources */,\n",
            with: "\t\t\t\tAA0000000000000000000010 /* Resources */,\n\t\t\t\tAA0000000000000000000011 /* Generated */,\n")
            .replacingOccurrences(
                of: "/* End PBXGroup section */",
                with: "\t\tAA0000000000000000000011 /* Generated */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t\tpath = Generated;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n/* End PBXGroup section */")
        let project = try Project.load(Array(withGroup.utf8))
        XCTAssertEqual(project.groups(at: "App/Generated").map(\.id), ["AA0000000000000000000011"])
        let reader = MemoryDisk(DiskRuleTests.complete)
        XCTAssertEqual(disk(RuleSet.standard.evaluate(project, disk: reader)), [])
    }

    // Spec: Disk rules are opt-in — no reader, no disk access.
    func testWithoutAReaderNothingIsRead() throws {
        let project = try loadProject("model/app.pbxproj")
        let reader = MemoryDisk([])  // an empty disk would produce D1 for every file
        let withReader = RuleSet.standard.evaluate(project, disk: reader)
        XCTAssertGreaterThan(disk(withReader).count, 5)
        XCTAssertGreaterThan(reader.calls, 0)
        let without = RuleSet.standard.evaluate(project)
        XCTAssertEqual(disk(without), [])
        // Only DiskRules can hold a reader; the rules that do are D1 and D2 and nothing else.
        XCTAssertEqual(RuleSet.standard.diskRules.map(\.id), [.D1, .D2])
        XCTAssertFalse(RuleSet.standard.rules.contains { $0.id == .D1 || $0.id == .D2 })
    }
}

/// `source` with the first occurrence of `target` replaced.
func replacing(_ source: String, _ target: String, with replacement: String,
               file: StaticString = #filePath, line: UInt = #line) -> String {
    guard let range = source.range(of: target) else {
        XCTFail("fixture does not contain \(target.debugDescription)", file: file, line: line)
        return source
    }
    return source.replacingCharacters(in: range, with: replacement)
}
