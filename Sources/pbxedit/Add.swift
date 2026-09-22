import ArgumentParser
import Foundation
import PBXModel
import PBXOps

extension PhaseChoice: ExpressibleByArgument {}

/// `pbxedit add`: files on disk become members of the project — reference,
/// group chain, build file and phase entry — as one plan, checked before and
/// after it is written. The command validates, plans and renders; the
/// planner decides and `OperationRunner` writes.
struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add files that exist on disk to the project, inferring targets and platform filters from their siblings.",
        discussion: """
            Each path gets a file reference in the group for its directory (created as needed), and a build file \
            in the right phase of each target — the targets every sibling file of the same kind belongs to, unless \
            --target says otherwise. Re-adding a member changes nothing; partial membership is completed with the \
            existing objects. The rule set is checked over the touched objects before the file is written and again \
            after; any error aborts and nothing is written.

            Paths are relative to the current directory, as for query. Exit code 0 on success or no-op, 1 when a \
            file is missing, a decision cannot be made or a rule is violated, 2 on a usage error.
            """)

    @OptionGroup var projectOptions: ProjectOptions
    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Print the plan and a unified diff of project.pbxproj; write nothing.")
    var dryRun = false

    @Option(name: .long, help: ArgumentHelp("A target to join instead of the inferred ones; repeatable.", valueName: "name"))
    var target: [String] = []

    @Option(name: .long, help: ArgumentHelp("platformFilters for the new build files: comma-separated names, or none.", valueName: "list"))
    var platform: String?

    @Option(name: .long, help: ArgumentHelp("The build phase, instead of the one the file type implies.", valueName: "sources|resources|headers|none"))
    var phase: PhaseChoice?

    @Argument(help: ArgumentHelp("Files to add, relative to the current directory.", valueName: "path"))
    var paths: [String] = []

    func run() throws {
        do {
            guard !paths.isEmpty else { throw UsageError("pass at least one path") }
            let pbxproj = try projectOptions.locate()
            let runner: OperationRunner
            do {
                runner = try OperationRunner(projectFile: pbxproj)
            } catch {
                throw UsageError("\(error)")
            }
            let project = runner.project
            let cwd = ProjectOptions.currentDirectory
            let sourceRoot = ProjectOptions.sourceRoot(of: pbxproj)
            var resolved: [String] = []
            for raw in paths {
                do {
                    resolved.append(try PathArgument.resolve(raw, cwd: cwd, sourceRoot: sourceRoot.path))
                } catch let error as PathArgumentError {
                    throw UsageError("\(raw): \(error)")
                }
            }
            let available = project.targets.compactMap(\.name).sorted()
            for name in target where !project.targets.contains(where: { $0.name?.utf8.elementsEqual(name.utf8) == true }) {
                throw UsageError(PlanError.unknownTarget(name: name, available: available).description)
            }
            var flags = Conventions.Flags(targets: target.isEmpty ? nil : target, platformFilters: nil, phase: phase)
            if let platform {
                do {
                    flags.platformFilters = try PlatformFilters.parse(platform)
                } catch {
                    throw UsageError("\(error)")
                }
            }

            // Everything from here on is reported in the command's own shape.
            let renderer = AddReport(pbxproj: pbxproj, dryRun: dryRun, json: output.json)
            if let refusal = Add.missingFiles(resolved, under: sourceRoot) {
                renderer.refused(refusal, project: project, paths: resolved)
                throw CommandOutcome.violations.exitCode
            }
            let plan: Plan
            do {
                plan = try AddPlanner.plan(resolved, in: project, conventions: Conventions(flags: flags))
            } catch let error as PlanError {
                renderer.refused(error.description, project: project, paths: resolved)
                throw CommandOutcome.violations.exitCode
            }
            let result = runner.run(plan, dryRun: dryRun)
            renderer.render(result, fallback: project, paths: resolved)
            switch result.outcome {
            case .ok: throw CommandOutcome.ok.exitCode
            case .violations, .failed: throw CommandOutcome.violations.exitCode
            }
        } catch let error as UsageError {
            error.report(json: output.json)
            throw CommandOutcome.usage.exitCode
        }
    }

    /// Spec: the file must exist, and be a file — or a bundle Xcode treats as one.
    static func missingFiles(_ paths: [String], under sourceRoot: URL) -> String? {
        var problems: [String] = []
        for path in paths {
            let url = sourceRoot.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                problems.append("\(path): no such file")
                continue
            }
            if isDirectory.boolValue, !DiskEntry.bundleExtensions.contains(url.pathExtension.lowercased()) {
                problems.append("\(path): is a directory, not a file")
            }
        }
        return problems.isEmpty ? nil : problems.joined(separator: "\n")
    }
}

/// What `add` prints, in either form. One JSON object with every key present
/// (absent values `null`); human output grouped by path, ending with the
/// one line derived from whether the bytes were replaced.
struct AddReport {
    let pbxproj: URL
    let dryRun: Bool
    let json: Bool

    /// A refusal before anything ran: the file is missing or the planner asked a question.
    func refused(_ message: String, project: Project, paths: [String]) {
        if json {
            print(AddReport.json(modified: false, dryRun: dryRun, plan: Plan(), findings: [], warnings: [], error: message, diff: nil,
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
            print(AddReport.json(modified: result.modified, dryRun: dryRun, plan: result.plan, findings: result.findings, warnings: result.warnings,
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
                lines.append("  \(AddReport.words(change.action)) \(change.object): \(change.detail)")
            }
            for note in result.plan.notes where note.hasPrefix(path + ":") {
                lines.append("  note: \(note)")
            }
            if let report = results.first(where: { $0.path == path }), result.outcome == .ok {
                lines.append("  membership: " + AddReport.membership(report))
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

        init(_ source: Decision.Source) {
            kind = source.kind
            if case .inferred(let siblings, let directory) = source {
                self.siblings = siblings
                self.directory = directory
            } else {
                self.siblings = nil
                self.directory = nil
            }
        }

        enum CodingKeys: String, CodingKey { case kind, siblings, directory }

        // Absent values are `null`, never omitted.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(siblings, forKey: .siblings)
            try container.encode(directory, forKey: .directory)
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
