import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// The corpus as the lower layers' tests see it: the committed files plus
/// whatever `PBXEDIT_EXTRA_CORPUS` names (files or directories, `:`-separated).
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
}

/// Task 3.3: design.md's first risk. Every attribute value in the corpus that
/// is the ID of an object in the same file is held by a key S2 checks, or by
/// a key named here with the reason it is not checked.
final class CorpusRuleTests: XCTestCase {
    /// Keys whose values can be IDs of objects in this file but which S2 does
    /// not check, and why.
    static let ignoredReferenceKeys: [String: String] = [
        "remoteGlobalIDString": "an ID in the container portal's project, which is another file unless the "
            + "project references itself (CocoaPods-Xcodeproj/Circular.pbxproj); not a reference into this table",
    ]

    func testEveryIDShapedAttributeKeyIsCheckedBySOrIgnored() throws {
        var keysHoldingIDs: [String: Set<String>] = [:]
        var checked = 0
        func collect(_ project: Project, _ name: String) {
            for object in project.objects {
                guard let attributes = object.attributes else { continue }
                CorpusRuleTests.visit(attributes) { key, value in
                    guard project.contains(ObjectID(value)) else { return }
                    checked += 1
                    keysHoldingIDs[key, default: []].insert(name)
                }
            }
        }
        for file in Corpus.allFiles() {
            collect(try Project.load(try Corpus.load(file)), file.name)
        }
        XCTAssertGreaterThan(checked, 6_000, "the committed corpus holds about 6,900 in-file references")
        let unaccounted = keysHoldingIDs.keys.filter {
            !S2Rule.referenceKeys.contains($0) && CorpusRuleTests.ignoredReferenceKeys[$0] == nil
        }.sorted()
        XCTAssertEqual(unaccounted, [], "keys holding object IDs that S2 neither checks nor ignores: "
            + unaccounted.map { "\($0) in \(keysHoldingIDs[$0]!.sorted().prefix(3))" }.joined(separator: "; "))
        // Every checked and ignored key has a witness — in the corpus, or in
        // a rule fixture that exercises it — so the lists do not accumulate
        // guesses. The only key without a corpus witness is
        // `baseConfigurationReference` (an xcconfig; no corpus project uses
        // one), which rules/s2-dangling-xcconfig.pbxproj exercises.
        for url in Fixtures.projectFiles(under: "rules") where url.lastPathComponent.hasPrefix("s2-") {
            collect(try Project.load(Array(try Data(contentsOf: url))), "rules/" + url.lastPathComponent)
        }
        for key in S2Rule.referenceKeys + Array(CorpusRuleTests.ignoredReferenceKeys.keys) {
            XCTAssertNotNil(keysHoldingIDs[key], "no corpus file or S2 fixture has an object ID under '\(key)'")
        }
    }

    /// Task 4.4 / design.md Evidence: every corpus file evaluates, and the
    /// counts per rule are printed so the change's design.md can record them.
    func testEveryCorpusFileEvaluatesAndCountsArePrinted() throws {
        var table: [String] = []
        for file in Corpus.allFiles() {
            let findings = RuleSet.standard.evaluate(bytes: try Corpus.load(file))
            var counts: [RuleID: Int] = [:]
            for finding in findings { counts[finding.rule, default: 0] += 1 }
            let summary = RuleID.allCases.compactMap { rule in counts[rule].map { count in "\(rule.rawValue)=\(count)" } }
            table.append("\(file.name): \(summary.isEmpty ? "clean" : summary.joined(separator: " "))")
            for finding in findings where finding.rule != .S5 { table.append("    \(finding)") }
        }
        print("corpus findings:\n" + table.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(table.count, 26)
    }

    /// Task 4.4: the committed corpus — Xcode-generated projects, the tuist
    /// template fixtures (`ProjectWithSwiftPackageTraits` has a Swift package
    /// dependency) included — is free of errors, except three real defects in
    /// tuist fixtures, each checked against the file text and pinned here. The
    /// only warnings are S5 on the one file another tool generated (see
    /// `PBXSyntaxTests.CorpusTests`). A new finding on a corpus file is either
    /// a rule bug or a defect to record here.
    func testCommittedCorpusHasNoErrorsExceptTheKnownDefects() throws {
        let knownErrors: [String: [(RuleID, ObjectID, [ObjectID])]] = [
            // Two references to the same file in the same group.
            "corpus/tuist-XcodeProj/FileSharedAcrossTargets.pbxproj": [
                (.M4, "6CB965012A49DC1F009186C6", ["6C103C072A49CC5400D7EFE4"]),
            ],
            // ViewController.swift's build file listed twice in the Sources phase.
            "corpus/tuist-XcodeProj/ProjectWithSwiftPackageTraits.pbxproj": [
                (.S3, "23766C0E1EAA3484007A9026", ["23766C181EAA3484007A9026"]),
            ],
            "corpus/tuist-XcodeProj/iOS-Project.pbxproj": [
                (.S3, "23766C0E1EAA3484007A9026", ["23766C181EAA3484007A9026"]),
            ],
        ]
        let knownWarnings: [String: (RuleID, Int)] = [
            "corpus/tuist-XcodeProj/WithoutWorkspace.pbxproj": (.S5, 234),
        ]
        for file in Corpus.committedFiles() {
            let findings = RuleSet.standard.evaluate(bytes: try Corpus.load(file))
            let errors = findings.filter { $0.severity == .error }
            let expected = knownErrors[file.name] ?? []
            XCTAssertEqual(errors.count, expected.count, "\(file.name): \(errors)")
            for (finding, known) in zip(errors, expected) {
                XCTAssertEqual(finding.rule, known.0, file.name)
                XCTAssertEqual(finding.object, known.1, file.name)
                XCTAssertEqual(finding.related, known.2, file.name)
            }
            let warnings = findings.filter { $0.severity == .warning }
            if let (rule, count) = knownWarnings[file.name] {
                XCTAssertEqual(warnings.count, count, file.name)
                XCTAssertTrue(warnings.allSatisfy { $0.rule == rule }, file.name)
            } else {
                XCTAssertEqual(warnings, [], file.name)
            }
        }
    }

    /// Every string value at any depth, with the key that holds it (an array's
    /// elements are held by the array's key).
    static func visit(_ dictionary: DictionaryNode, _ body: (String, String) -> Void) {
        for entry in dictionary.entries {
            visit(entry.value, key: entry.key.value, body)
        }
    }

    private static func visit(_ node: Node, key: String, _ body: (String, String) -> Void) {
        switch node {
        case .string(let string):
            body(key, string.value)
        case .array(let array):
            for element in array.elements { visit(element.value, key: key, body) }
        case .dictionary(let dictionary):
            visit(dictionary, body)
        case .data:
            break
        }
    }
}
