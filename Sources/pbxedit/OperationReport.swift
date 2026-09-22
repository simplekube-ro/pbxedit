import Foundation
import PBXModel
import PBXOps

/// What a mutating command (`add`, `remove`) prints, in either form. One
/// JSON object with every key present (absent values `null`); human output
/// grouped by path — decisions, changes, notes, the membership after the
/// operation — ending with the one line derived from whether the bytes were
/// replaced. Introduced by `add-command` as `AddReport`; `remove-command`
/// moved it here unchanged so both commands print the same shape.
struct OperationReport {
    let pbxproj: URL
    let dryRun: Bool
    let json: Bool

    /// A refusal before anything ran: the file is missing or the planner asked a question.
    func refused(_ message: String, project: Project, paths: [String]) {
        if json {
            print(OperationReport.json(modified: false, dryRun: dryRun, plan: Plan(), findings: [], warnings: [], error: message, diff: nil,
                                       results: paths.map { MembershipReport(project: project, path: $0) }), terminator: "")
        } else {
            FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
            print(modifiedLine(false))
        }
    }

    func render(_ result: OperationResult, fallback: Project, paths: [String]) {
        let project = result.project ?? fallback
        let results = paths.map { MembershipReport(project: project, path: $0) }
        if json {
            print(OperationReport.json(modified: result.modified, dryRun: dryRun, plan: result.plan, findings: result.findings, warnings: result.warnings,
                                       error: result.error, diff: result.diff, results: results), terminator: "")
            return
        }
        var lines: [String] = []
        for path in paths {
            lines.append(path)
            for decision in result.plan.decisions where decision.path == path {
                lines.append("  \(decision.attribute): \(decision.value) (\(decision.source.description))")
            }
            for change in result.plan.changes where change.path == path {
                lines.append("  \(OperationReport.words(change.action)) \(change.object): \(change.detail)")
            }
            for note in result.plan.notes where note.hasPrefix(path + ":") {
                lines.append("  note: \(note)")
            }
            if let report = results.first(where: { $0.path == path }), result.outcome == .ok {
                lines.append("  membership: " + OperationReport.membership(report))
            }
        }
        for warning in result.warnings { lines.append("warning: \(warning.description.dropFirst("warning ".count))") }
        for finding in result.findings { lines.append(finding.description) }
        if let error = result.error { FileHandle.standardError.write(Data(("error: " + error + "\n").utf8)) }
        if let diff = result.diff, !diff.isEmpty { lines.append(diff.hasSuffix("\n") ? String(diff.dropLast()) : diff) }
        lines.append(modifiedLine(result.modified))
        print(lines.joined(separator: "\n"))
    }

    private func modifiedLine(_ modified: Bool) -> String {
        "\(pbxproj.lastPathComponent): \(modified ? "modified" : "not modified")\(dryRun ? " (dry run)" : "")"
    }

    static func words(_ action: Change.Action) -> String {
        switch action {
        case .createdFileReference: return "created file reference"
        case .reusedFileReference: return "reused file reference"
        case .createdGroup: return "created group"
        case .reusedGroup: return "reused group"
        case .createdBuildFile: return "created build file"
        case .reusedBuildFile: return "reused build file"
        case .addedChild: return "added child to group"
        case .addedPhaseEntry: return "added phase entry to"
        case .removedChild: return "removed child from group"
        case .removedPhaseEntry: return "removed phase entry from"
        case .deletedObject: return "deleted object"
        case .setAttribute: return "set attribute of"
        case .synchronized: return "synchronized group"
        }
    }

    static func membership(_ report: MembershipReport) -> String {
        if let coverage = report.synchronized {
            return "covered by synchronized group \(coverage.path) (\(coverage.group))"
        }
        guard report.member else { return "not a member" }
        guard !report.memberships.isEmpty else { return "referenced, built by no target" }
        return report.memberships.map { entry in
            let target = entry.target.map { $0.name ?? $0.id.rawValue } ?? "no target"
            let phase = entry.phase.map { $0.name ?? $0.id.rawValue } ?? "no phase"
            let filters = entry.platformFilters.isEmpty ? "" : " [\(entry.platformFilters.joined(separator: ", "))]"
            return "\(target) (\(phase))\(filters)"
        }.joined(separator: ", ")
    }

    // MARK: JSON

    struct Source: Encodable {
        let kind: String
        let siblings: Int?
        let directory: String?
        let rule: Int?
        let glob: String?

        init(_ source: Decision.Source) {
            kind = source.kind
            switch source {
            case .inferred(let siblings, let directory):
                self.siblings = siblings
                self.directory = directory
                rule = nil
                glob = nil
            case .config(let rule, let glob):
                siblings = nil
                directory = nil
                self.rule = rule
                self.glob = glob
            case .exemption(_, let glob):
                // The rule is the finding's ID, not a position; `kind` says which.
                siblings = nil
                directory = nil
                rule = nil
                self.glob = glob
            case .flag, .fileType, .structure:
                siblings = nil
                directory = nil
                rule = nil
                glob = nil
            }
        }

        enum CodingKeys: String, CodingKey { case kind, siblings, directory, rule, glob }

        // Absent values are `null`, never omitted.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(siblings, forKey: .siblings)
            try container.encode(directory, forKey: .directory)
            try container.encode(rule, forKey: .rule)
            try container.encode(glob, forKey: .glob)
        }
    }

    struct DecisionJSON: Encodable {
        let path: String
        let attribute: String
        let value: String
        let source: Source
    }

    struct ChangeJSON: Encodable {
        let path: String
        let action: String
        let object: String
        let detail: String
    }

    struct JSON: Encodable {
        let schemaVersion = 1
        let modified: Bool
        let dryRun: Bool
        let decisions: [DecisionJSON]
        let changes: [ChangeJSON]
        let notes: [String]
        let findings: [LintReport.JSON.Finding]
        let error: String?
        let diff: String?
        let results: [MembershipReport]

        enum CodingKeys: String, CodingKey { case schemaVersion, modified, dryRun, decisions, changes, notes, findings, error, diff, results }

        // Absent values are `null`, never omitted.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(modified, forKey: .modified)
            try container.encode(dryRun, forKey: .dryRun)
            try container.encode(decisions, forKey: .decisions)
            try container.encode(changes, forKey: .changes)
            try container.encode(notes, forKey: .notes)
            try container.encode(findings, forKey: .findings)
            try container.encode(error, forKey: .error)
            try container.encode(diff, forKey: .diff)
            try container.encode(results, forKey: .results)
        }
    }

    static func json(modified: Bool, dryRun: Bool, plan: Plan, findings: [Finding], warnings: [Finding], error: String?, diff: String?,
                     results: [MembershipReport]) -> String {
        let object = JSON(
            modified: modified,
            dryRun: dryRun,
            decisions: plan.decisions.map { DecisionJSON(path: $0.path, attribute: $0.attribute, value: $0.value, source: Source($0.source)) },
            changes: plan.changes.map { ChangeJSON(path: $0.path, action: $0.action.rawValue, object: $0.object.rawValue, detail: $0.detail) },
            notes: plan.notes,
            findings: (findings + warnings).map {
                LintReport.JSON.Finding(
                    rule: $0.rule.rawValue, severity: $0.severity.rawValue, object: $0.object?.rawValue, path: $0.path,
                    related: $0.related.map(\.rawValue), message: $0.message)
            },
            error: error,
            diff: diff,
            results: results)
        guard let data = try? JSONEncoder.pbxedit.encode(object) else { return "{}\n" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
