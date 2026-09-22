import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// Task 7.1: the `lint --fix` shape at scale. Design.md's first risk:
/// rebuilding the indexes after every mutation is quadratic for bulk repairs.
/// This measures 700 repairs — create a file reference, add it as a child,
/// query the parent index — and decides whether change 9 needs a batch scope.
final class ModelPerformanceTests: XCTestCase {
    static let mutations = 700
    /// Design.md's threshold, in a release build.
    static let releaseLimit: TimeInterval = 1.0
    /// Debug builds only guard against a blow-up.
    static let debugLimit: TimeInterval = 30

    enum Shape: String {
        /// Plan then apply: the cache is dropped after each repair but never
        /// rebuilt, because nothing is queried until the end.
        case planned = "no-queries"
        /// The parent index is queried after each repair, forcing its rebuild.
        case parents = "parent-queries"
        /// The path index — the lookup an M3 repair needs to pick the group
        /// for a directory — is queried after each repair.
        case paths = "path-queries"
    }

    private func workload(_ input: [UInt8], shape: Shape) throws -> (project: Project, elapsed: TimeInterval) {
        var project = try Project.load(input)
        let group = try XCTUnwrap(project.mainGroup).id
        let start = Date()
        for index in 0..<ModelPerformanceTests.mutations {
            let hex = String(index, radix: 16, uppercase: true)
            let id = ObjectID("FEEDFACE0000000000000000".dropLast(hex.count) + hex)
            try project.createObject(id, isa: "PBXFileReference", attributes: [
                NewEntry("lastKnownFileType", .string("sourcecode.swift")),
                NewEntry("path", .string("Repaired\(index).swift")),
                NewEntry("sourceTree", .string("<group>")),
            ])
            try project.addChild(id, to: group)
            switch shape {
            case .planned: break
            case .parents: XCTAssertEqual(project.parents(of: id).map(\.id), [group])
            case .paths: XCTAssertEqual(project.fileReferences(at: "Repaired\(index).swift").map(\.id), [id])
            }
        }
        return (project, Date().timeIntervalSince(start))
    }

    func testSevenHundredRepairsOnTheLargestCorpusFile() throws {
        let largest = try XCTUnwrap(try Corpus.largestCommittedFile())
        try measure(largest.file, largest.bytes)
        for file in Corpus.extraFiles() {
            try measure(file, try Corpus.load(file))
        }
    }

    private func measure(_ file: Corpus.File, _ bytes: [UInt8]) throws {
        let planned = try workload(bytes, shape: .planned).elapsed
        let (project, elapsed) = try workload(bytes, shape: .parents)
        let paths = try workload(bytes, shape: .paths).elapsed
        // The result is a real edit: it parses, it round-trips, and the
        // repairs are in the model.
        let output = project.serialize()
        XCTAssertTrue(try SyntaxTree.parse(output).get().serialize() == output)
        XCTAssertEqual(project.mainGroup?.children.count, (try Project.load(bytes).mainGroup?.children.count ?? 0) + ModelPerformanceTests.mutations)
        XCTAssertEqual(lineDiff(text(bytes), text(output)).added.count, 2 * ModelPerformanceTests.mutations)
        #if DEBUG
        let configuration = "debug"
        let limit = ModelPerformanceTests.debugLimit
        #else
        let configuration = "release"
        let limit = ModelPerformanceTests.releaseLimit
        #endif
        print("SCALE \(configuration) \(file.name) bytes=\(bytes.count) objects=\(try Project.load(bytes).objects.count) "
            + "mutations=\(ModelPerformanceTests.mutations)x(create+addChild) "
            + "\(Shape.planned.rawValue)=\(String(format: "%.3f", planned))s "
            + "\(Shape.parents.rawValue)=\(String(format: "%.3f", elapsed))s "
            + "\(Shape.paths.rawValue)=\(String(format: "%.3f", paths))s")
        XCTAssertLessThan(elapsed, limit, "\(ModelPerformanceTests.mutations) repairs on \(file.name) (\(configuration) build)")
        XCTAssertLessThan(paths, limit, "\(ModelPerformanceTests.mutations) repairs with path lookups on \(file.name) (\(configuration) build)")
    }
}
