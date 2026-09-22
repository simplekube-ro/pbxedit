import Foundation
import PBXModel

/// Findings a project has agreed to live with (design D6): keyed by rule and
/// object ID — or path, for a finding with no object — so that `lint
/// --baseline` fails only on new damage.
public struct Baseline: Equatable, Sendable {
    public static let schemaVersion = 1

    public struct Entry: Hashable, Sendable, Codable, Comparable {
        public let rule: String
        /// The object ID, or the path of a finding that has no object.
        public let object: String

        public init(rule: String, object: String) {
            self.rule = rule
            self.object = object
        }

        public static func < (lhs: Entry, rhs: Entry) -> Bool {
            if lhs.rule != rhs.rule { return lhs.rule.utf8.lexicographicallyPrecedes(rhs.rule.utf8) }
            return lhs.object.utf8.lexicographicallyPrecedes(rhs.object.utf8)
        }
    }

    public enum ReadError: Error, CustomStringConvertible {
        case notJSON(String)
        case unsupportedSchemaVersion(Int)

        public var description: String {
            switch self {
            case .notJSON(let reason): return "the baseline is not valid JSON: \(reason)"
            case .unsupportedSchemaVersion(let version):
                return "the baseline has schemaVersion \(version); this version of pbxedit reads schemaVersion \(Baseline.schemaVersion)"
            }
        }
    }

    /// Sorted by rule then key, each once.
    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = Array(Set(entries)).sorted()
    }

    public init(findings: [Finding]) {
        self.init(entries: findings.map(Baseline.entry))
    }

    /// The key a finding is baselined under.
    public static func entry(for finding: Finding) -> Entry {
        Entry(rule: finding.rule.rawValue, object: finding.object?.rawValue ?? finding.path ?? "")
    }

    // MARK: Format

    private struct Document: Codable {
        var schemaVersion: Int
        var entries: [Entry]
    }

    public init(data: Data) throws {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw ReadError.notJSON("\(error)")
        }
        guard document.schemaVersion == Baseline.schemaVersion else {
            throw ReadError.unsupportedSchemaVersion(document.schemaVersion)
        }
        self.init(entries: document.entries)
    }

    /// One entry per line, so diffs are reviewable.
    public func encoded() -> String {
        var lines = ["{", "  \"schemaVersion\": \(Baseline.schemaVersion),", "  \"entries\": ["]
        for (index, entry) in entries.enumerated() {
            let comma = index == entries.count - 1 ? "" : ","
            lines.append("    { \"rule\": \(Baseline.quoted(entry.rule)), \"object\": \(Baseline.quoted(entry.object)) }\(comma)")
        }
        lines.append("  ]")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func quoted(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode([string]), let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(text.dropFirst().dropLast())
    }

    // MARK: Application

    public struct Application: Equatable, Sendable {
        /// The findings not in the baseline, in their original order.
        public let findings: [Finding]
        /// How many findings the baseline suppressed.
        public let baselined: Int
        /// Baseline entries that no finding matched any more.
        public let resolved: [Entry]
    }

    public func apply(to findings: [Finding]) -> Application {
        let known = Set(entries)
        var matched: Set<Entry> = []
        var kept: [Finding] = []
        for finding in findings {
            let entry = Baseline.entry(for: finding)
            if known.contains(entry) {
                matched.insert(entry)
            } else {
                kept.append(finding)
            }
        }
        return Application(
            findings: kept,
            baselined: findings.count - kept.count,
            resolved: entries.filter { !matched.contains($0) })
    }
}
