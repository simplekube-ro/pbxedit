import Foundation
import PBXModel
import PBXOps

/// What `lint --fix` prints, in either form (integrity-repair design D8):
/// each repaired finding with what was done, each remaining finding with the
/// reason when it is of a fixable rule, the resolved baseline entries, the
/// summary, the baseline hint, the diff of a dry run, and the one line
/// derived from whether the bytes were replaced.
struct RepairReport {
    let pbxproj: URL
    let repair: RepairPlan
    /// After exemptions and the baseline, when one was given — or, when the
    /// verification refused the plan, the findings that refused it.
    let remaining: [Finding]
    let baselined: Int
    let resolved: [Baseline.Entry]
    let exempt: Int
    /// The baseline in use, for the hint.
    let baselinePath: String?
    let modified: Bool
    let dryRun: Bool
    let diff: String?
    /// A refusal or failure, printed to standard error.
    let error: String?

    /// A report that repaired nothing: the S1 case and a refused plan.
    init(pbxproj: URL, remaining: [Finding], dryRun: Bool, modified: Bool = false, error: String? = nil) {
        self.init(pbxproj: pbxproj, repair: RepairPlan(plan: Plan(), repaired: [], notFixable: []), remaining: remaining,
                  baselined: 0, resolved: [], exempt: 0, baselinePath: nil, modified: modified, dryRun: dryRun, diff: nil, error: error)
    }

    init(pbxproj: URL, repair: RepairPlan, remaining: [Finding], baselined: Int, resolved: [Baseline.Entry], exempt: Int,
         baselinePath: String?, modified: Bool, dryRun: Bool, diff: String?, error: String?) {
        self.pbxproj = pbxproj
        self.repair = repair
        self.remaining = remaining
        self.baselined = baselined
        self.resolved = resolved
        self.exempt = exempt
        self.baselinePath = baselinePath
        self.modified = modified
        self.dryRun = dryRun
        self.diff = diff
        self.error = error
    }

    var errors: Int { remaining.filter { $0.severity == .error }.count }
    var warnings: Int { remaining.filter { $0.severity == .warning }.count }

    /// `lint`'s rule over what remains.
    func outcome(strict: Bool) -> CommandOutcome {
        if errors > 0 { return .violations }
        if strict, warnings > 0 { return .violations }
        return .ok
    }

    private func reason(for finding: Finding) -> String? {
        repair.notFixable.first { $0.finding.identity == finding.identity }?.reason
    }

    func text() -> String {
        var lines: [String] = []
        for finding in repair.repaired {
            lines.append("repaired " + finding.description.dropFirst(finding.severity.rawValue.count + 1))
            for decision in repair.decisions(for: finding) {
                lines.append("  \(decision.attribute): \(decision.value) (\(decision.source.description))")
            }
            for change in repair.changes(for: finding) {
                lines.append("  \(OperationReport.words(change.action)) \(change.object): \(change.detail)")
            }
            for note in repair.notes(for: finding) {
                lines.append("  note: \(note)")
            }
        }
        for finding in remaining {
            lines.append(finding.description)
            if let reason = reason(for: finding) { lines.append("  not fixable: \(reason)") }
        }
        for entry in resolved {
            lines.append("resolved \(entry.rule) \(entry.object): no longer reported; remove it from the baseline")
        }
        var summary = "\(LintReport.count(errors, "error")), \(LintReport.count(warnings, "warning"))"
        summary += ", \(repair.repaired.count) repaired, \(repair.notFixable.count) not fixable"
        if baselined > 0 || !resolved.isEmpty { summary += ", \(baselined) baselined" }
        if !resolved.isEmpty { summary += ", \(resolved.count) resolved" }
        if exempt > 0 { summary += ", \(exempt) exempt" }
        lines.append(summary)
        if let baselinePath, !resolved.isEmpty {
            let verb = dryRun ? "would be resolved" : "resolved"
            lines.append("baseline: \(LintReport.count(resolved.count, "entry", "entries")) \(verb) by this repair; rewrite it with --write-baseline \(baselinePath)")
        }
        if let error { FileHandle.standardError.write(Data(("error: " + error + "\n").utf8)) }
        if let diff, !diff.isEmpty { lines.append(diff.hasSuffix("\n") ? String(diff.dropLast()) : diff) }
        lines.append("\(pbxproj.lastPathComponent): \(modified ? "modified" : "not modified")\(dryRun ? " (dry run)" : "")")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: JSON

    struct RepairedJSON: Encodable {
        let rule: String
        let severity: String
        let object: String?
        let path: String?
        let related: [String]
        let message: String
        let decisions: [OperationReport.DecisionJSON]
        let changes: [OperationReport.ChangeJSON]
        let notes: [String]

        enum CodingKeys: String, CodingKey { case rule, severity, object, path, related, message, decisions, changes, notes }

        // Absent values are `null`, never omitted.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rule, forKey: .rule)
            try container.encode(severity, forKey: .severity)
            try container.encode(object, forKey: .object)
            try container.encode(path, forKey: .path)
            try container.encode(related, forKey: .related)
            try container.encode(message, forKey: .message)
            try container.encode(decisions, forKey: .decisions)
            try container.encode(changes, forKey: .changes)
            try container.encode(notes, forKey: .notes)
        }
    }

    struct RemainingJSON: Encodable {
        let rule: String
        let severity: String
        let object: String?
        let path: String?
        let related: [String]
        let message: String
        /// Why a fixable-rule finding was not repaired; `null` otherwise.
        let reason: String?

        enum CodingKeys: String, CodingKey { case rule, severity, object, path, related, message, reason }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rule, forKey: .rule)
            try container.encode(severity, forKey: .severity)
            try container.encode(object, forKey: .object)
            try container.encode(path, forKey: .path)
            try container.encode(related, forKey: .related)
            try container.encode(message, forKey: .message)
            try container.encode(reason, forKey: .reason)
        }
    }

    struct Summary: Encodable {
        let errors: Int
        let warnings: Int
        let baselined: Int
        let resolved: Int
        let exempt: Int
        let repaired: Int
        let notFixable: Int
    }

    struct JSON: Encodable {
        let schemaVersion = 1
        let project: String
        let modified: Bool
        let dryRun: Bool
        let repaired: [RepairedJSON]
        let remaining: [RemainingJSON]
        let resolved: [Baseline.Entry]
        let summary: Summary
        let diff: String?
        let error: String?

        enum CodingKeys: String, CodingKey { case schemaVersion, project, modified, dryRun, repaired, remaining, resolved, summary, diff, error }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(project, forKey: .project)
            try container.encode(modified, forKey: .modified)
            try container.encode(dryRun, forKey: .dryRun)
            try container.encode(repaired, forKey: .repaired)
            try container.encode(remaining, forKey: .remaining)
            try container.encode(resolved, forKey: .resolved)
            try container.encode(summary, forKey: .summary)
            try container.encode(diff, forKey: .diff)
            try container.encode(error, forKey: .error)
        }
    }

    func json() -> String {
        let object = JSON(
            project: pbxproj.path,
            modified: modified,
            dryRun: dryRun,
            repaired: repair.repaired.map { finding in
                RepairedJSON(
                    rule: finding.rule.rawValue, severity: finding.severity.rawValue, object: finding.object?.rawValue, path: finding.path,
                    related: finding.related.map(\.rawValue), message: finding.message,
                    decisions: repair.decisions(for: finding).map {
                        OperationReport.DecisionJSON(path: $0.path, attribute: $0.attribute, value: $0.value, source: OperationReport.Source($0.source))
                    },
                    changes: repair.changes(for: finding).map {
                        OperationReport.ChangeJSON(path: $0.path, action: $0.action.rawValue, object: $0.object.rawValue, detail: $0.detail)
                    },
                    notes: repair.notes(for: finding))
            },
            remaining: remaining.map {
                RemainingJSON(
                    rule: $0.rule.rawValue, severity: $0.severity.rawValue, object: $0.object?.rawValue, path: $0.path,
                    related: $0.related.map(\.rawValue), message: $0.message, reason: reason(for: $0))
            },
            resolved: resolved,
            summary: Summary(errors: errors, warnings: warnings, baselined: baselined, resolved: resolved.count, exempt: exempt,
                             repaired: repair.repaired.count, notFixable: repair.notFixable.count),
            diff: diff,
            error: error)
        guard let data = try? JSONEncoder.pbxedit.encode(object) else { return "{}\n" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
