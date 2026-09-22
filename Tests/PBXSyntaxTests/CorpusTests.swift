import Foundation
import XCTest
@testable import PBXSyntax

#if canImport(CryptoKit)
import CryptoKit
#endif

/// The corpus: real `project.pbxproj` files, byte-identical to upstream, with
/// provenance in `Tests/Fixtures/NOTICE`.
enum Corpus {
    /// Names extra files or directories, separated by `:`, to run the corpus
    /// tests against without committing them.
    static let extraVariable = "PBXEDIT_EXTRA_CORPUS"

    struct File {
        let url: URL
        /// Path relative to `Tests/Fixtures`, or the full path for an extra file.
        let name: String
        let isExtra: Bool
    }

    static func committedFiles() -> [File] {
        let prefix = Fixtures.directory.standardizedFileURL.path + "/"
        return Fixtures.allProjectFiles(under: "corpus").map { url in
            let path = url.standardizedFileURL.path
            let name = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
            return File(url: url, name: name, isExtra: false)
        }
    }

    /// The files named by `PBXEDIT_EXTRA_CORPUS`. A directory contributes every
    /// `.pbxproj` below it. A path that does not exist is reported in `missing`
    /// so that a typo cannot pass silently.
    static func extraFiles() -> (files: [File], missing: [String]) {
        guard let value = ProcessInfo.processInfo.environment[extraVariable], !value.isEmpty else {
            return ([], [])
        }
        var files: [File] = []
        var missing: [String] = []
        for entry in value.split(separator: ":").map(String.init) where !entry.isEmpty {
            let url = URL(fileURLWithPath: (entry as NSString).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                missing.append(entry)
                continue
            }
            if !isDirectory.boolValue {
                files.append(File(url: url, name: url.path, isExtra: true))
                continue
            }
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
                missing.append(entry)
                continue
            }
            var found: [URL] = []
            for case let child as URL in enumerator where child.pathExtension == "pbxproj" {
                found.append(child)
            }
            if found.isEmpty { missing.append(entry) }
            files.append(contentsOf: found.sorted { $0.path < $1.path }.map {
                File(url: $0, name: $0.path, isExtra: true)
            })
        }
        return (files, missing)
    }

    static func allFiles() -> [File] { committedFiles() + extraFiles().files }

    static func load(_ file: File) throws -> [UInt8] { Array(try Data(contentsOf: file.url)) }

    /// The largest committed file: the subject of the performance test.
    static func largestCommittedFile() throws -> (file: File, bytes: [UInt8])? {
        var largest: (file: File, bytes: [UInt8])?
        for file in committedFiles() {
            let bytes = try load(file)
            if bytes.count > (largest?.bytes.count ?? -1) { largest = (file, bytes) }
        }
        return largest
    }
}

final class CorpusTests: XCTestCase {
    // Spec: Byte-exact round trip — Real project file (rule S1).
    func testEveryCorpusFileRoundTripsByteForByte() throws {
        let files = Corpus.allFiles()
        XCTAssertGreaterThanOrEqual(Corpus.committedFiles().count, 20, "the committed corpus is missing")
        for file in files {
            let input = try Corpus.load(file)
            XCTAssertFalse(input.isEmpty, "\(file.name) is empty")
            switch SyntaxTree.parse(input) {
            case .failure(let error):
                XCTFail("\(file.name) does not parse: \(error)")
            case .success(let tree):
                XCTAssertTrue(tree.serialize() == input, "\(file.name) does not round-trip byte for byte")
                XCTAssertNotNil(tree.node(at: ["objects"])?.dictionary, "\(file.name) has no objects dictionary")
            }
        }
    }

    func testExtraCorpusPathsExist() {
        let missing = Corpus.extraFiles().missing
        XCTAssertTrue(
            missing.isEmpty,
            "\(Corpus.extraVariable) names paths that do not exist or hold no .pbxproj: \(missing)")
    }

    /// The corpus spans the project formats the tool will meet, including
    /// files saved by Xcode 27.
    func testCorpusCoversObjectVersionsAndXcode27() throws {
        var versions: Set<String> = []
        var savedByXcode27 = 0
        for file in Corpus.committedFiles() {
            let tree = try XCTUnwrap(try? SyntaxTree.parse(Corpus.load(file)).get(), file.name)
            if let version = tree.node(at: ["objectVersion"])?.stringValue { versions.insert(version) }
            let objects = tree.node(at: ["objects"])?.dictionary
            for entry in objects?.entries ?? [] where entry.value.dictionary?["isa"]?.stringValue == "PBXProject" {
                let attributes = entry.value.dictionary?["attributes"]?.dictionary
                if attributes?["LastUpgradeCheck"]?.stringValue == "2700" { savedByXcode27 += 1 }
            }
        }
        for expected in ["45", "46", "47", "48", "50", "52", "54", "56", "60", "73", "77", "100"] {
            XCTAssertTrue(versions.contains(expected), "no corpus file with objectVersion \(expected)")
        }
        XCTAssertGreaterThanOrEqual(savedByXcode27, 2, "no corpus file with LastUpgradeCheck = 2700")
    }

    // MARK: Design D5 evidence

    /// The Xcode versions a file says touched it: `LastUpgradeCheck`,
    /// `LastSwiftUpdateCheck` and every target's `CreatedOnToolsVersion`.
    /// This is the only in-file evidence of which Xcode wrote a file; it shows
    /// that a version saved the file at least once, not that it saved it last.
    private func xcodeMarkers(in tree: SyntaxTree) -> [String] {
        var markers: [String] = []
        let objects = tree.node(at: ["objects"])?.dictionary
        for entry in objects?.entries ?? [] where entry.value.dictionary?["isa"]?.stringValue == "PBXProject" {
            let attributes = entry.value.dictionary?["attributes"]?.dictionary
            for key in ["LastUpgradeCheck", "LastSwiftUpdateCheck"] {
                if let value = attributes?[key]?.stringValue { markers.append(value) }
            }
            for target in attributes?["TargetAttributes"]?.dictionary?.entries ?? [] {
                if let value = target.value.dictionary?["CreatedOnToolsVersion"]?.stringValue { markers.append(value) }
            }
        }
        return markers
    }

    /// Strings whose quoting differs from the D5 write-side rule, as
    /// `(raw text, reason)`.
    private func quotingDisagreements(in tree: SyntaxTree) -> [String] {
        var result: [String] = []
        tree.forEachToken { token in
            switch token.kind {
            case .bareString where StringCoding.needsQuoting(token.text):
                result.append("bare but D5 would quote: \(token.text)")
            case .quotedString where !StringCoding.needsQuoting(StringCoding.decodeQuoted(token.text)):
                result.append("quoted but D5 would leave bare: \(token.text)")
            default:
                break
            }
        }
        return result
    }

    /// What a set of files shows about the quoting rule: which of the
    /// non-alphanumeric characters appear in bare strings, and which single
    /// causes are seen to force quotes on a string that is otherwise bare-able.
    private struct QuotingWitnesses {
        var bareSpecials: Set<String> = []
        var soleCauses: Set<String> = []

        mutating func record(_ token: Token) {
            if token.kind == .bareString {
                for scalar in token.text.unicodeScalars where !CorpusTests.isAlphanumeric(scalar) {
                    bareSpecials.insert(String(scalar))
                }
            } else if token.kind == .quotedString {
                let value = StringCoding.decodeQuoted(token.text)
                if value.isEmpty {
                    soleCauses.insert("empty")
                    return
                }
                var offenders: Set<String> = []
                for scalar in value.unicodeScalars
                where !CorpusTests.isAlphanumeric(scalar) && !"_$/.".unicodeScalars.contains(scalar) {
                    if !scalar.isASCII {
                        offenders.insert("non-ASCII")
                    } else if scalar.value < 0x20 || scalar.value == 0x7F {
                        offenders.insert("control")
                    } else {
                        offenders.insert(String(scalar))
                    }
                }
                // `//` and `___` are causes in their own right: a URL is quoted
                // for `:` and for `//`, so it is a witness for neither alone.
                if value.contains("//") { offenders.insert("//") }
                if value.contains("___") { offenders.insert("___") }
                if offenders.count == 1, let only = offenders.first { soleCauses.insert(only) }
            }
        }
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        default: return false
        }
    }

    /// `LastUpgradeCheck = 9999` is no Xcode release: the file was generated
    /// by another tool, so its quoting says nothing about Xcode's.
    private func isGeneratedByAnotherTool(_ markers: [String]) -> Bool { markers.contains("9999") }

    private func isMarkedByXcode27(_ markers: [String]) -> Bool {
        markers.contains { $0 == "2700" || $0.hasPrefix("27.") }
    }

    /// Design D5, write side: in every corpus file written by Xcode, a string
    /// is quoted if and only if `StringCoding.needsQuoting` says so. This is
    /// the evidence that the rule matches Xcode, Xcode 27 included.
    func testXcodeWrittenFilesQuoteExactlyAsDesignD5Says() throws {
        var generatedElsewhere: [String] = []
        for file in Corpus.committedFiles() {
            let tree = try SyntaxTree.parse(Corpus.load(file)).get()
            if isGeneratedByAnotherTool(xcodeMarkers(in: tree)) {
                generatedElsewhere.append(file.name)
                continue
            }
            let disagreements = quotingDisagreements(in: tree)
            XCTAssertTrue(
                disagreements.isEmpty,
                "\(file.name): \(disagreements.count) strings disagree with design D5, e.g. \(disagreements.prefix(5))")
        }
        // A file may leave this check only by being named here.
        XCTAssertEqual(generatedElsewhere, ["corpus/tuist-XcodeProj/WithoutWorkspace.pbxproj"])
    }

    /// What the Xcode 27 files actually exercise of the D5 rule. The test
    /// above shows no string contradicts the rule; this one pins which parts
    /// of it have a witness, so that the unknowns recorded in design D5 stay
    /// true. If a corpus change makes this fail, update design D5's evidence.
    func testXcode27FilesWitnessTheQuotingRule() throws {
        var xcode27 = QuotingWitnesses()
        var earlier = QuotingWitnesses()
        var xcode27Files = 0
        for file in Corpus.committedFiles() {
            let tree = try SyntaxTree.parse(Corpus.load(file)).get()
            let markers = xcodeMarkers(in: tree)
            if isGeneratedByAnotherTool(markers) { continue }
            let is27 = isMarkedByXcode27(markers)
            if is27 { xcode27Files += 1 }
            tree.forEachToken { token in
                if is27 { xcode27.record(token) } else { earlier.record(token) }
            }
        }
        XCTAssertEqual(xcode27Files, 6)
        // Left bare by Xcode 27. `$` has no Xcode 27 witness, only an earlier one.
        XCTAssertEqual(xcode27.bareSpecials.sorted(), [".", "/", "_"])
        XCTAssertEqual(earlier.bareSpecials.sorted(), ["$", ".", "/", "_"])
        // Quoted by Xcode 27 for this cause alone. `-` is one of the two
        // characters the reader accepts bare and the writer quotes. The other,
        // `:`, has no witness: every Xcode-written string with a `:` is a URL,
        // which also holds `//`.
        XCTAssertEqual(xcode27.soleCauses.sorted(), [" ", "+", ",", "-", "=", "@", "empty"])
        // Nowhere in the corpus is `:`, `//` or `___` the only cause of quoting.
        XCTAssertEqual(
            earlier.soleCauses.sorted(),
            [" ", "*", "+", ",", "-", "=", "@", "control", "empty", "non-ASCII"])
    }

    /// Every committed file is recorded in NOTICE with the digest of the bytes
    /// fetched from upstream, so a fixture cannot drift from its source, and
    /// every licence NOTICE names is present.
    func testNoticeRecordsEveryCorpusFile() throws {
        let notice = try String(contentsOf: Fixtures.directory.appendingPathComponent("NOTICE"), encoding: .utf8)
        for file in Corpus.committedFiles() {
            XCTAssertTrue(notice.contains(file.name), "NOTICE does not record \(file.name)")
            #if canImport(CryptoKit)
            let digest = SHA256.hash(data: Data(try Corpus.load(file)))
                .map { byte in
                    let digits = String(byte, radix: 16)
                    return digits.count == 1 ? "0" + digits : digits
                }
                .joined()
            XCTAssertTrue(notice.contains(digest), "NOTICE does not record the SHA-256 of \(file.name) (\(digest))")
            #endif
        }
        let owners = Set(Corpus.committedFiles().compactMap { $0.name.split(separator: "/").dropFirst().first })
        for owner in owners {
            let licence = "licenses/\(owner).LICENSE"
            XCTAssertTrue(notice.contains(licence), "NOTICE does not name \(licence)")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: Fixtures.directory.appendingPathComponent(licence).path),
                "\(licence) is missing")
        }
    }
}
