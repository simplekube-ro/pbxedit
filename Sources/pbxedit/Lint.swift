import ArgumentParser
import Foundation
import PBXModel
import PBXOps

/// `pbxedit lint`: evaluates the rule set over the whole project and reports.
/// Never edits the project (spec: The lint command reports and never edits),
/// except with `--fix`, which repairs the fixable membership findings as one
/// plan through the shared operation pipeline (integrity-repair); the only
/// other file it writes is the one `--write-baseline` names.
struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check the project file against the integrity rules, and with --fix repair what is unambiguous.",
        discussion: """
            Rules: \(RuleID.allCases.map { "\($0.rawValue) \($0.title) (\($0.severity.rawValue))" }.joined(separator: "; ")).

            --fix repairs M1 (a build file in no phase joins the phase for its file's type in the one target its \
            siblings belong to; one whose file does not resolve is deleted), M2 (a phase entry naming nothing, or a \
            build file whose file does not resolve, is removed) and M3 (a file reference in no group becomes a child \
            of the group for its directory, created as needed) as one plan and one write, reusing every existing \
            object; findings it cannot repair safely are listed with the reason. The whole rule set is evaluated \
            before and after: a repair that would leave a selected finding or introduce any finding is refused.

            Exit code 1 when an error is reported, 0 otherwise; warnings count as errors with --strict.
            """)

    @OptionGroup var projectOptions: ProjectOptions
    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Also run the disk rules D1 and D2, which read the file system under the project's directory.")
    var disk = false

    @Flag(name: .long, help: "Exit 1 on warnings too.")
    var strict = false

    @Option(name: .long, help: ArgumentHelp("Report only findings not recorded in this baseline file.", valueName: "file"))
    var baseline: String?

    @Flag(name: .long, help: "Ignore the baseline named by lint.baseline in .pbxedit.yml.")
    var noBaseline = false

    @Option(name: .long, help: ArgumentHelp("Record the current findings in this baseline file and exit 0.", valueName: "file"))
    var writeBaseline: String?

    @Flag(name: .long, help: "Repair the fixable findings (M1, M2, M3) as one plan and one write.")
    var fix = false

    @Flag(name: .long, help: "With --fix: print the repair report and a unified diff of project.pbxproj; write nothing.")
    var dryRun = false

    func run() throws {
        do {
            if baseline != nil, noBaseline { throw UsageError("pass either --baseline or --no-baseline, not both") }
            if dryRun, !fix { throw UsageError("--dry-run previews a repair; pass it with --fix") }
            if fix, writeBaseline != nil {
                throw UsageError("--fix and --write-baseline do not go together; repair first, then run lint --write-baseline \(writeBaseline ?? "") for what remains")
            }
            let context = try projectOptions.context()
            let pbxproj = context.pbxproj
            let bytes: [UInt8]
            do {
                bytes = Array(try Data(contentsOf: pbxproj))
            } catch {
                throw UsageError("cannot read \(pbxproj.path): \(error.localizedDescription)")
            }
            // A project that does not load is the S1 finding below; the
            // target check needs a loaded project and waits for one.
            if let project = try? Project.load(bytes) { try context.validate(project) }
            // The baseline: the flag, else the configured default unless
            // --no-baseline or --write-baseline (spec: Lint baseline default).
            var baselinePath = baseline
            if baselinePath == nil, !noBaseline, writeBaseline == nil, let configured = context.config?.file.baselineURL {
                baselinePath = configured.path
            }
            let existing = try baselinePath.map(Lint.readBaseline)
            let reader: (any DiskReader)? = disk ? FileSystemDiskReader(sourceRoot: context.sourceRoot) : nil
            let exemptions = context.config?.exemptions ?? Exemptions([:])
            if fix {
                try repair(context: context, bytes: bytes, baseline: existing, baselinePath: baselinePath, reader: reader, exemptions: exemptions)
            }
            let evaluated = RuleSet.standard.evaluate(bytes: bytes, disk: reader)
            // Exemptions first, then the baseline (spec: Path exemptions).
            let (findings, exempt) = exemptions.apply(to: evaluated)
            let applied = existing?.apply(to: findings)
            var report = LintReport(
                project: pbxproj.path,
                findings: applied?.findings ?? findings,
                baselined: applied?.baselined ?? 0,
                resolved: applied?.resolved ?? [],
                exempt: exempt.count)
            if let writeBaseline {
                let written = Baseline(findings: findings)
                do {
                    try Data(written.encoded().utf8).write(to: URL(fileURLWithPath: writeBaseline))
                } catch {
                    throw UsageError("cannot write the baseline \(writeBaseline): \(error.localizedDescription)")
                }
                report.baselineWritten = (writeBaseline, written.entries.count)
            }
            print(output.json ? report.json() : report.text(), terminator: "")
            throw (writeBaseline != nil ? CommandOutcome.ok : report.outcome(strict: strict)).exitCode
        } catch let error as UsageError {
            error.report(json: output.json)
            throw CommandOutcome.usage.exitCode
        }
    }

    /// `--fix` (integrity-repair design D5, D7, D8): plan over the findings
    /// as loaded, run through the operation pipeline in whole-project
    /// verification, then report the result as `lint` would, baseline and
    /// disk rules included. Always ends in an exit code.
    private func repair(context: ProjectContext, bytes: [UInt8], baseline: Baseline?, baselinePath: String?,
                        reader: (any DiskReader)?, exemptions: Exemptions) throws {
        let pbxproj = context.pbxproj
        var runner: OperationRunner
        do {
            runner = try OperationRunner(projectFile: pbxproj)
        } catch {
            // Not a project: the S1 finding, nothing to repair.
            let s1 = RuleSet.standard.evaluate(bytes: bytes)
            let report = RepairReport(pbxproj: pbxproj, remaining: s1, dryRun: dryRun)
            print(output.json ? report.json() : report.text(), terminator: "")
            throw CommandOutcome.violations.exitCode
        }
        runner.exemptions = exemptions
        let project = runner.project
        // The findings as loaded, exemptions applied, no disk rules: what is
        // repaired and the basis of the verification.
        let before = RuleSet.standard.evaluate(project, exemptions: exemptions)
        let repair = RepairPlanner.plan(before, in: project, conventions: Conventions(config: context.config?.conventions), exemptions: exemptions)
        let result = runner.run(repair.plan, dryRun: dryRun, verification: .wholeProject(before: before, selected: repair.repaired))
        let report: RepairReport
        switch result.outcome {
        case .ok:
            let after = result.project ?? project
            let (findings, exempt) = exemptions.apply(to: RuleSet.standard.evaluate(after, disk: reader))
            let applied = baseline?.apply(to: findings)
            report = RepairReport(
                pbxproj: pbxproj, repair: repair, remaining: applied?.findings ?? findings, baselined: applied?.baselined ?? 0,
                resolved: applied?.resolved ?? [], exempt: exempt.count, baselinePath: baselinePath, modified: result.modified,
                dryRun: dryRun, diff: result.diff, error: nil)
            print(output.json ? report.json() : report.text(), terminator: "")
            throw report.outcome(strict: strict).exitCode
        case .violations(let stage):
            let when = stage == .beforeWrite ? "nothing was written" : "the original bytes were restored"
            let what = LintReport.count(result.findings.count, "finding")
            let error = "the repair would leave or introduce \(what); \(when)" + (result.error.map { " \($0)" } ?? "")
            report = RepairReport(pbxproj: pbxproj, remaining: result.findings, dryRun: dryRun, modified: result.modified, error: error)
        case .failed:
            report = RepairReport(pbxproj: pbxproj, remaining: [], dryRun: dryRun, modified: result.modified, error: result.error ?? "the repair failed")
        }
        print(output.json ? report.json() : report.text(), terminator: "")
        throw CommandOutcome.violations.exitCode
    }

    private static func readBaseline(_ path: String) throws -> Baseline {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw UsageError("no baseline at \(path); create one with --write-baseline \(path)")
        }
        do {
            return try Baseline(data: data)
        } catch {
            throw UsageError("cannot read the baseline \(path): \(error)")
        }
    }
}

/// What `lint` prints, in either form.
struct LintReport {
    let project: String
    /// After exemptions and the baseline, when one was given.
    let findings: [Finding]
    let baselined: Int
    let resolved: [Baseline.Entry]
    /// How many findings `lint.exempt` suppressed.
    let exempt: Int
    var baselineWritten: (path: String, entries: Int)?

    var errors: Int { findings.filter { $0.severity == .error }.count }
    var warnings: Int { findings.filter { $0.severity == .warning }.count }

    func outcome(strict: Bool) -> CommandOutcome {
        if errors > 0 { return .violations }
        if strict, warnings > 0 { return .violations }
        return .ok
    }

    func text() -> String {
        var lines = findings.map(\.description)
        for entry in resolved {
            lines.append("resolved \(entry.rule) \(entry.object): no longer reported; remove it from the baseline")
        }
        var summary = "\(LintReport.count(errors, "error")), \(LintReport.count(warnings, "warning"))"
        if baselined > 0 || !resolved.isEmpty { summary += ", \(baselined) baselined" }
        if !resolved.isEmpty { summary += ", \(resolved.count) resolved" }
        if exempt > 0 { summary += ", \(exempt) exempt" }
        lines.append(summary)
        if let baselineWritten {
            lines.append("baseline written: \(baselineWritten.path) (\(LintReport.count(baselineWritten.entries, "entry", "entries")))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func count(_ number: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(number) \(number == 1 ? singular : (plural ?? singular + "s"))"
    }

    struct JSON: Encodable {
        struct Finding: Encodable {
            let rule: String
            let severity: String
            let object: String?
            let path: String?
            let related: [String]
            let message: String

            enum CodingKeys: String, CodingKey { case rule, severity, object, path, related, message }

            // Absent values are `null`, never omitted (design D7).
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(rule, forKey: .rule)
                try container.encode(severity, forKey: .severity)
                try container.encode(object, forKey: .object)
                try container.encode(path, forKey: .path)
                try container.encode(related, forKey: .related)
                try container.encode(message, forKey: .message)
            }
        }

        struct Summary: Encodable {
            let errors: Int
            let warnings: Int
            let baselined: Int
            let resolved: Int
            let exempt: Int
        }

        let schemaVersion = 1
        let project: String
        let findings: [Finding]
        let resolved: [Baseline.Entry]
        let summary: Summary
    }

    func json() -> String {
        let object = JSON(
            project: project,
            findings: findings.map {
                JSON.Finding(
                    rule: $0.rule.rawValue, severity: $0.severity.rawValue, object: $0.object?.rawValue, path: $0.path,
                    related: $0.related.map(\.rawValue), message: $0.message)
            },
            resolved: resolved,
            summary: JSON.Summary(errors: errors, warnings: warnings, baselined: baselined, resolved: resolved.count, exempt: exempt))
        guard let data = try? JSONEncoder.pbxedit.encode(object) else { return "{}\n" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
