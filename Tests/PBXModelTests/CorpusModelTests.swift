import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// The corpus as `PBXSyntaxTests` sees it: the committed files plus whatever
/// `PBXEDIT_EXTRA_CORPUS` names (files or directories, `:`-separated).
enum Corpus {
    static let extraVariable = "PBXEDIT_EXTRA_CORPUS"

    struct File {
        let url: URL
        let name: String
    }

    static func committedFiles() -> [File] {
        let prefix = Fixtures.directory.standardizedFileURL.path + "/"
        return Fixtures.projectFiles(under: "corpus").map { url in
            let path = url.standardizedFileURL.path
            return File(url: url, name: path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path)
        }
    }

    static func extraFiles() -> [File] {
        guard let value = ProcessInfo.processInfo.environment[extraVariable], !value.isEmpty else { return [] }
        var files: [File] = []
        for entry in value.split(separator: ":").map(String.init) where !entry.isEmpty {
            let url = URL(fileURLWithPath: (entry as NSString).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                files.append(File(url: url, name: url.path))
                continue
            }
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
            var found: [URL] = []
            for case let child as URL in enumerator where child.pathExtension == "pbxproj" { found.append(child) }
            files.append(contentsOf: found.sorted { $0.path < $1.path }.map { File(url: $0, name: $0.path) })
        }
        return files
    }

    static func allFiles() -> [File] { committedFiles() + extraFiles() }

    static func load(_ file: File) throws -> [UInt8] { Array(try Data(contentsOf: file.url)) }

    static func largestCommittedFile() throws -> (file: File, bytes: [UInt8])? {
        var largest: (file: File, bytes: [UInt8])?
        for file in committedFiles() {
            let bytes = try load(file)
            if bytes.count > (largest?.bytes.count ?? -1) { largest = (file, bytes) }
        }
        return largest
    }
}

/// Task 7.2: every corpus file loads through the model and serializes back
/// byte for byte.
final class CorpusModelTests: XCTestCase {
    func testEveryCorpusFileLoadsAndSerializesByteForByte() throws {
        let files = Corpus.allFiles()
        XCTAssertGreaterThanOrEqual(Corpus.committedFiles().count, 20, "the committed corpus is missing")
        for file in files {
            let input = try Corpus.load(file)
            do {
                let project = try Project.load(input)
                XCTAssertTrue(project.serialize() == input, "\(file.name) does not serialize byte for byte")
                XCTAssertNotNil(project.rootObject, file.name)
                XCTAssertNotNil(project.mainGroup, "\(file.name) has no main group")
                XCTAssertEqual(project.duplicateIDs, [], "\(file.name) has duplicate IDs")
                for reference in project.fileReferences {
                    XCTAssertNotNil(project.resolvedPath(of: reference.id), "\(file.name): \(reference.id) does not resolve")
                }
            } catch {
                XCTFail("\(file.name) does not load: \(error)")
            }
        }
    }

    /// Design D6 against Xcode's own output: wherever an object's definition
    /// line carries a comment and the model has an opinion, they agree. A
    /// disagreement means the annotation table is wrong for that kind.
    func testAnnotationsAgreeWithEveryCommentXcodeWrote() throws {
        var checked = 0
        for file in Corpus.allFiles() {
            let project = try Project.load(try Corpus.load(file))
            for object in project.objects {
                guard let expected = project.tree.keyAnnotation(at: Project.path(of: object.id)),
                      let actual = project.annotation(for: object.id)
                else { continue }
                checked += 1
                XCTAssertEqual(actual, expected, "\(file.name): \(object.id) (\(object.isa ?? "?"))")
            }
        }
        XCTAssertGreaterThan(checked, 3_000)
    }
}
