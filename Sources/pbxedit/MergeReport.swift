import Foundation
import PBXModel
import PBXOps

/// What `merge` prints (spec: Output, dry run and exit codes): each unit
/// with its paths, outcome, decision, the replay's changes and owed
/// residuals; each hunk with its key, governed keys and decision; each
/// check; the decisions template when decisions are needed; and the last
/// line derived from whether the output's bytes were replaced. With
/// `--json`, one object with every key present, absent values `null`.
struct MergeRenderer {
    let output: URL
    let dryRun: Bool
    let json: Bool
    let paths: (base: String, ours: String, theirs: String)

    func render(_ report: MergeReport, modified: Bool, diff: String?, writeFailure: CheckResult?, writeError: String?) {
        let checks = report.checks + (writeFailure.map { [$0] } ?? [])
        let error = MergeRenderer.error(report, writeFailure: writeFailure, writeError: writeError)
        let status = writeFailure != nil || writeError != nil ? "failed" : report.status.rawValue
        if json {
            print(MergeRenderer.json(report, status: status, modified: modified, dryRun: dryRun, output: output.path, paths: paths, checks: checks,
                                     diff: diff, error: error), terminator: "")
            return
        }
        var lines: [String] = []
        if report.nothingToMerge { lines.append("ours and theirs are identical: nothing to merge") }
        for unit in report.units { lines += MergeRenderer.lines(unit) }
        for hunk in report.hunks { lines += MergeRenderer.lines(hunk) }
        for check in checks {
            lines.append("check \(check.check.rawValue) (\(check.check.title)): \(check.passed ? "passed" : "failed")")
            for problem in check.problems { lines.append("  \(problem)") }
        }
        for residual in report.owed {
            lines.append("owed: \(residual.path): \(residual.kind) \(residual.theirs.map { "= \($0)" } ?? "absent") (theirs), not written")
        }
        for finding in report.findings { lines.append(finding.description) }
        if let error { FileHandle.standardError.write(Data(("error: " + error + "\n").utf8)) }
        if let diff, !diff.isEmpty { lines.append(diff.hasSuffix("\n") ? String(diff.dropLast()) : diff) }
        if let template = report.template, let data = try? JSONEncoder.pbxedit.encode(template) {
            lines.append("decisions needed: fill in the template and pass it with --decisions <file>")
            lines.append("```json")
            lines.append(String(decoding: data, as: UTF8.self))
            lines.append("```")
        }
        lines.append("\(output.lastPathComponent): \(modified ? "modified" : "not modified")\(dryRun ? " (dry run)" : "")")
        print(lines.joined(separator: "\n"))
    }

    /// The one error line. A failed re-check carries `writeError` only when
    /// the restore failed too ("and the previous file could not be
    /// restored: …"), so the check is always named first.
    static func error(_ report: MergeReport, writeFailure: CheckResult?, writeError: String?) -> String? {
        if let writeFailure {
            return "the file read back failed check \(writeFailure.check.rawValue)" + (writeError.map { " " + $0 } ?? "; the previous bytes were restored")
        }
        return writeError ?? report.error
    }

    // MARK: Text

    static func lines(_ unit: MergeReport.UnitEntry) -> [String] {
        let classified = unit.classified
        let outcome: String
        switch classified.outcome {
        case .replayed: outcome = "replayed"
        case .skipped: outcome = "skipped: ours already has it"
        case .decision:
            outcome = unit.decision.map { "decided \($0.rawValue)" }
                ?? "decision needed: \(classified.choices.map(\.rawValue).joined(separator: " | "))"
        }
        var lines = ["unit \(unit.key) (\(outcome)): \(classified.unit.paths.joined(separator: ", "))"]
        if classified.outcome == .decision {
            for state in classified.states {
                lines.append("  \(state.path)")
                lines.append("    base:   \(describe(state.base))")
                lines.append("    ours:   \(describe(state.ours))")
                lines.append("    theirs: \(describe(state.theirs))")
            }
            for residual in classified.residuals { lines.append("  residual: \(residual)") }
            if let reason = classified.reason { lines.append("  theirs cannot be replayed: \(reason)") }
        }
        for change in unit.changes { lines.append("  \(OperationReport.words(change.action)) \(change.object): \(change.detail)") }
        return lines
    }

    static func lines(_ hunk: MergeReport.HunkEntry) -> [String] {
        let analysed = hunk.analysed
        let outcome = hunk.decision.map { "decided \($0.rawValue)" }
            ?? "decision needed: \(analysed.choices.map(\.rawValue).joined(separator: " | "))"
        var lines = ["hunk \(hunk.key) (\(outcome))"]
        for values in analysed.values {
            lines.append("  \(values.path): base \(show(values.base)), ours \(show(values.ours)), theirs \(show(values.theirs))")
        }
        if analysed.values.isEmpty { lines.append("  governs no key: the sides differ only in layout") }
        return lines
    }

    static func describe(_ state: MembershipSnapshot.MaskedState?) -> String {
        guard let state else { return "absent" }
        let rows = state.rows.isEmpty ? "built by no target" : state.rows.map(\.description).joined(separator: ", ")
        let group = state.groupPaths.first.map { "in group \($0.isEmpty ? "<main group>" : $0)" } ?? "in no group"
        return "\(rows); \(group)"
    }

    static func show(_ value: PlistValue?) -> String { value?.description ?? "absent" }

    // MARK: JSON

    struct JSON: Encodable {
        let schemaVersion = 1
        let status: String
        let modified: Bool
        let dryRun: Bool
        let output: String
        let inputs: [String: Input]
        let units: [Unit]
        let hunks: [Hunk]
        let checks: [Check]
        let owed: [Owed]
        let findings: [LintReport.JSON.Finding]
        let template: MergeDecisions?
        let diff: String?
        let error: String?

        struct Input: Encodable {
            let path: String
            let sha256: String
        }

        struct State: Encodable {
            let path: String?
            let name: String?
            let sourceTree: String
            let groupPaths: [String]
            let rows: [String]
        }

        struct PathStates: Encodable {
            let path: String
            let base: State?
            let ours: State?
            let theirs: State?

            enum CodingKeys: String, CodingKey { case path, base, ours, theirs }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(path, forKey: .path)
                try container.encode(base, forKey: .base)
                try container.encode(ours, forKey: .ours)
                try container.encode(theirs, forKey: .theirs)
            }
        }

        struct ResidualJSON: Encodable {
            let path: String
            let what: String
            let object: String?
            let theirs: String?
            let merged: String?

            enum CodingKeys: String, CodingKey { case path, what, object, theirs, merged }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(path, forKey: .path)
                try container.encode(what, forKey: .what)
                try container.encode(object, forKey: .object)
                try container.encode(theirs, forKey: .theirs)
                try container.encode(merged, forKey: .merged)
            }
        }

        struct Unit: Encodable {
            let key: String
            let paths: [String]
            let outcome: String
            let decision: String?
            let choices: [String]
            let reason: String?
            let residuals: [ResidualJSON]
            let states: [PathStates]
            let changes: [OperationReport.ChangeJSON]

            enum CodingKeys: String, CodingKey { case key, paths, outcome, decision, choices, reason, residuals, states, changes }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(key, forKey: .key)
                try container.encode(paths, forKey: .paths)
                try container.encode(outcome, forKey: .outcome)
                try container.encode(decision, forKey: .decision)
                try container.encode(choices, forKey: .choices)
                try container.encode(reason, forKey: .reason)
                try container.encode(residuals, forKey: .residuals)
                try container.encode(states, forKey: .states)
                try container.encode(changes, forKey: .changes)
            }
        }

        struct Governed: Encodable {
            let object: String?
            let keyPath: String
            let base: String?
            let ours: String?
            let theirs: String?

            enum CodingKeys: String, CodingKey { case object, keyPath, base, ours, theirs }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(object, forKey: .object)
                try container.encode(keyPath, forKey: .keyPath)
                try container.encode(base, forKey: .base)
                try container.encode(ours, forKey: .ours)
                try container.encode(theirs, forKey: .theirs)
            }
        }

        struct Hunk: Encodable {
            let key: String
            let decision: String?
            let choices: [String]
            let governed: [Governed]
            let base: String
            let ours: String
            let theirs: String

            enum CodingKeys: String, CodingKey { case key, decision, choices, governed, base, ours, theirs }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(key, forKey: .key)
                try container.encode(decision, forKey: .decision)
                try container.encode(choices, forKey: .choices)
                try container.encode(governed, forKey: .governed)
                try container.encode(base, forKey: .base)
                try container.encode(ours, forKey: .ours)
                try container.encode(theirs, forKey: .theirs)
            }
        }

        struct Problem: Encodable {
            let object: String?
            let subject: String
            let message: String

            enum CodingKeys: String, CodingKey { case object, subject, message }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(object, forKey: .object)
                try container.encode(subject, forKey: .subject)
                try container.encode(message, forKey: .message)
            }
        }

        struct Check: Encodable {
            let check: String
            let title: String
            let passed: Bool
            let problems: [Problem]
        }

        typealias Owed = ResidualJSON

        enum CodingKeys: String, CodingKey {
            case schemaVersion, status, modified, dryRun, output, inputs, units, hunks, checks, owed, findings, template, diff, error
        }

        // Absent values are `null`, never omitted.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(status, forKey: .status)
            try container.encode(modified, forKey: .modified)
            try container.encode(dryRun, forKey: .dryRun)
            try container.encode(output, forKey: .output)
            try container.encode(inputs, forKey: .inputs)
            try container.encode(units, forKey: .units)
            try container.encode(hunks, forKey: .hunks)
            try container.encode(checks, forKey: .checks)
            try container.encode(owed, forKey: .owed)
            try container.encode(findings, forKey: .findings)
            try container.encode(template, forKey: .template)
            try container.encode(diff, forKey: .diff)
            try container.encode(error, forKey: .error)
        }
    }

    static func residual(_ residual: Residual) -> JSON.ResidualJSON {
        JSON.ResidualJSON(path: residual.path, what: residual.kind.description, object: residual.object?.rawValue, theirs: residual.theirs,
                          merged: residual.merged)
    }

    static func state(_ state: MembershipSnapshot.MaskedState?) -> JSON.State? {
        state.map { JSON.State(path: $0.path, name: $0.name, sourceTree: $0.sourceTree, groupPaths: $0.groupPaths, rows: $0.rows.map(\.description)) }
    }

    static func json(_ report: MergeReport, status: String, modified: Bool, dryRun: Bool, output: String,
                     paths: (base: String, ours: String, theirs: String), checks: [CheckResult], diff: String?, error: String?) -> String {
        let text = { (lines: [[UInt8]]) in String(decoding: lines.flatMap { $0 }, as: UTF8.self) }
        let object = JSON(
            status: status,
            modified: modified,
            dryRun: dryRun,
            output: output,
            inputs: [
                "base": JSON.Input(path: paths.base, sha256: report.inputs.base),
                "ours": JSON.Input(path: paths.ours, sha256: report.inputs.ours),
                "theirs": JSON.Input(path: paths.theirs, sha256: report.inputs.theirs),
            ],
            units: report.units.map { unit in
                let classified = unit.classified
                return JSON.Unit(
                    key: unit.key, paths: classified.unit.paths, outcome: classified.outcome.rawValue, decision: unit.decision?.rawValue,
                    choices: classified.choices.map(\.rawValue), reason: classified.reason, residuals: classified.residuals.map(residual),
                    states: classified.states.map { JSON.PathStates(path: $0.path, base: state($0.base), ours: state($0.ours), theirs: state($0.theirs)) },
                    changes: unit.changes.map { OperationReport.ChangeJSON(path: $0.path, action: $0.action.rawValue, object: $0.object.rawValue, detail: $0.detail) })
            },
            hunks: report.hunks.map { hunk in
                let analysed = hunk.analysed
                return JSON.Hunk(
                    key: hunk.key, decision: hunk.decision?.rawValue, choices: analysed.choices.map(\.rawValue),
                    governed: analysed.values.map {
                        JSON.Governed(object: $0.path.objectID?.rawValue, keyPath: $0.path.keyPath, base: $0.base?.description,
                                      ours: $0.ours?.description, theirs: $0.theirs?.description)
                    },
                    base: text(analysed.hunk.base), ours: text(analysed.hunk.ours), theirs: text(analysed.hunk.theirs))
            },
            checks: checks.map { check in
                JSON.Check(check: check.check.rawValue, title: check.check.title, passed: check.passed,
                           problems: check.problems.map { JSON.Problem(object: $0.object?.rawValue, subject: $0.subject, message: $0.message) })
            },
            owed: report.owed.map(residual),
            findings: report.findings.map {
                LintReport.JSON.Finding(rule: $0.rule.rawValue, severity: $0.severity.rawValue, object: $0.object?.rawValue, path: $0.path,
                                        related: $0.related.map(\.rawValue), message: $0.message)
            },
            template: report.template,
            diff: diff,
            error: error)
        guard let data = try? JSONEncoder.pbxedit.encode(object) else { return "{}\n" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
