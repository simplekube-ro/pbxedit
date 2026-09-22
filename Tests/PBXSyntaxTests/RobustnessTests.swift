import Foundation
import XCTest
@testable import PBXSyntax

/// SplitMix64: small, fast, and the same sequence on every platform, so a
/// failure is reproducible from its seed and iteration.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<bound`; `bound` must be positive.
    mutating func next(below bound: Int) -> Int {
        bound <= 1 ? 0 : Int(next() % UInt64(bound))
    }
}

final class FuzzTests: XCTestCase {
    static let defaultSeed: UInt64 = 0x5042_5845_4449_5431  // "PBXEDIT1"
    static let defaultIterations = 2_000
    static let timeLimit: TimeInterval = 30

    /// Bytes that steer a mutation towards the grammar rather than towards
    /// an early UTF-8 error.
    static let structural: [UInt8] = Array("{}()=;,\"\\/*<>\n\r\t -+:$_.Ax09".utf8)

    private func environmentValue(_ name: String) -> UInt64? {
        ProcessInfo.processInfo.environment[name].flatMap { UInt64($0) }
    }

    /// 1-based line of `offset`, counted independently of `ParseError`.
    private func line(of offset: Int, in bytes: [UInt8]) -> Int {
        var line = 1
        var index = 0
        while index < offset, index < bytes.count {
            if bytes[index] == 0x0A {
                line += 1
            } else if bytes[index] == 0x0D, !(index + 1 < bytes.count && bytes[index + 1] == 0x0A) {
                line += 1
            }
            index += 1
        }
        return line
    }

    private func mutate(_ input: [UInt8], using generator: inout SeededGenerator) -> [UInt8] {
        var bytes = input
        let mutations = 1 + generator.next(below: 8)
        for _ in 0..<mutations {
            let byte: UInt8 = generator.next(below: 2) == 0
                ? FuzzTests.structural[generator.next(below: FuzzTests.structural.count)]
                : UInt8(truncatingIfNeeded: generator.next())
            switch generator.next(below: 3) {
            case 0:
                bytes.insert(byte, at: generator.next(below: bytes.count + 1))
            case 1:
                if !bytes.isEmpty { bytes.remove(at: generator.next(below: bytes.count)) }
            default:
                if !bytes.isEmpty { bytes[generator.next(below: bytes.count)] = byte }
            }
        }
        return bytes
    }

    // Spec: Located errors, never a crash — Fuzzed input.
    func testMutatedCorpusFilesRoundTripOrFailWithALocatedError() throws {
        let seed = environmentValue("PBXEDIT_FUZZ_SEED") ?? FuzzTests.defaultSeed
        let iterations = environmentValue("PBXEDIT_FUZZ_ITERATIONS").map(Int.init) ?? FuzzTests.defaultIterations
        let inputs = try Corpus.committedFiles().map { (name: $0.name, bytes: try Corpus.load($0)) }
        XCTAssertFalse(inputs.isEmpty, "the committed corpus is missing")
        guard !inputs.isEmpty else { return }

        var generator = SeededGenerator(seed: seed)
        var parsed = 0
        var rejected = 0
        var kinds: Set<String> = []
        let start = Date()
        for iteration in 0..<iterations {
            let input = inputs[generator.next(below: inputs.count)]
            let mutated = mutate(input.bytes, using: &generator)
            let context = "seed \(seed), iteration \(iteration), \(input.name)"
            switch SyntaxTree.parse(mutated) {
            case .success(let tree):
                parsed += 1
                if tree.serialize() != mutated {
                    XCTFail("mutated input parses but does not round-trip (\(context))")
                    return
                }
            case .failure(let error):
                rejected += 1
                kinds.insert(String(describing: error.kind))
                let located = error.line >= 1 && error.column >= 1
                    && (0...mutated.count).contains(error.byteOffset)
                    && error.line == line(of: error.byteOffset, in: mutated)
                    && !error.expected.isEmpty && !error.found.isEmpty
                if !located {
                    XCTFail("parse error is not located: \(error) (\(context))")
                    return
                }
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        print("FUZZ seed=\(seed) iterations=\(iterations) parsed=\(parsed) rejected=\(rejected) "
            + "kinds=\(kinds.sorted()) elapsed=\(String(format: "%.2f", elapsed))s")
        // Both outcomes must occur, or the fuzzer is not exercising the parser.
        XCTAssertGreaterThan(parsed, 0)
        XCTAssertGreaterThan(rejected, 0)
        if iterations <= FuzzTests.defaultIterations {
            XCTAssertLessThan(elapsed, FuzzTests.timeLimit, "the fuzzer must finish in under 30 s")
        }
    }
}

final class PerformanceTests: XCTestCase {
    /// Design, Risks: parse + 100 edits + serialize stays under this in a
    /// release build.
    static let releaseLimit: TimeInterval = 0.100
    /// Debug builds are not held to the limit; this only catches a blow-up.
    static let debugLimit: TimeInterval = 10

    private struct Targets {
        var arrayPath: SyntaxPath
        var pathValue: SyntaxPath
    }

    /// The first build phase with a `files` array, and the first file
    /// reference with a `path`.
    private func targets(in tree: SyntaxTree) -> Targets? {
        var arrayPath: SyntaxPath?
        var pathValue: SyntaxPath?
        for entry in tree.node(at: ["objects"])?.dictionary?.entries ?? [] {
            let object = entry.value.dictionary
            let id = entry.key.value
            if arrayPath == nil, object?["isa"]?.stringValue == "PBXSourcesBuildPhase", object?["files"]?.array != nil {
                arrayPath = ["objects", .key(id), "files"]
            }
            if pathValue == nil, object?["isa"]?.stringValue == "PBXFileReference", object?["path"]?.string != nil {
                pathValue = ["objects", .key(id), "path"]
            }
        }
        guard let arrayPath, let pathValue else { return nil }
        return Targets(arrayPath: arrayPath, pathValue: pathValue)
    }

    /// Parse, 100 edits (25 each of: insert an object, insert an array
    /// element, replace a value, remove an array element), serialize.
    private func workload(_ input: [UInt8]) throws -> [UInt8] {
        var tree = try SyntaxTree.parse(input).get()
        let targets = try XCTUnwrap(self.targets(in: tree))
        for round in 0..<25 {
            let buildFile = "FEEDFACE00000000000000" + (round < 10 ? "0\(round)" : "\(round)")
            try tree.insert(
                NewEntry(
                    buildFile, comment: "New\(round).swift in Sources",
                    .dictionary([
                        NewEntry("isa", .string("PBXBuildFile")),
                        NewEntry("fileRef", .string("FEEDFACE0000000000000100", comment: "New\(round).swift")),
                    ])),
                intoDictionaryAt: ["objects"])
            try tree.insert(.string(buildFile, comment: "New\(round).swift in Sources"), intoArrayAt: targets.arrayPath)
            try tree.replaceValue(at: targets.pathValue, with: .string("Renamed-\(round).swift"))
            if round % 2 == 1 {
                try tree.removeElement(equalTo: buildFile, fromArrayAt: targets.arrayPath)
            } else {
                try tree.removeElement(at: 0, fromArrayAt: targets.arrayPath)
            }
        }
        return tree.serialize()
    }

    func testParseHundredEditsSerializeOnTheLargestCorpusFile() throws {
        let largest = try XCTUnwrap(try Corpus.largestCommittedFile())
        let lines = largest.bytes.reduce(1) { $0 + ($1 == 0x0A ? 1 : 0) }

        // The workload is a real edit: its output parses, round-trips, and
        // differs from the input.
        let output = try workload(largest.bytes)
        XCTAssertNotEqual(output, largest.bytes)
        XCTAssertTrue(try SyntaxTree.parse(output).get().serialize() == output)

        var samples: [TimeInterval] = []
        for _ in 0..<7 {
            let start = Date()
            _ = try workload(largest.bytes)
            samples.append(Date().timeIntervalSince(start))
        }
        samples.sort()
        let median = samples[samples.count / 2]
        #if DEBUG
        let configuration = "debug"
        let limit = PerformanceTests.debugLimit
        #else
        let configuration = "release"
        let limit = PerformanceTests.releaseLimit
        #endif
        print("PERF \(configuration) \(largest.file.name) bytes=\(largest.bytes.count) lines=\(lines) "
            + "median=\(String(format: "%.1f", median * 1000))ms "
            + "min=\(String(format: "%.1f", (samples.first ?? 0) * 1000))ms "
            + "max=\(String(format: "%.1f", (samples.last ?? 0) * 1000))ms")
        XCTAssertLessThan(median, limit, "parse + 100 edits + serialize (\(configuration) build)")
    }
}
