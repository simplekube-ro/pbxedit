import ArgumentParser
import Foundation
import PBXModel
import PBXOps

/// `pbxedit lint`: evaluates the rule set over the whole project and reports.
/// Never edits the project (spec: The lint command reports and never edits);
/// the only file it writes is the one `--write-baseline` names.
struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check the project file against the integrity rules.",
        discussion: """
            Rules: \(RuleID.allCases.map { "\($0.rawValue) \($0.title) (\($0.severity.rawValue))" }.joined(separator: "; ")).

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

    func run() throws {
        do {
            if baseline != nil, noBaseline { throw UsageError("pass either --baseline or --no-baseline, not both") }
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
            let evaluated = RuleSet.standard.evaluate(bytes: bytes, disk: reader)
            // Exemptions first, then the baseline (spec: Path exemptions).
            let exemptions = context.config?.exemptions ?? Exemptions([:])
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
