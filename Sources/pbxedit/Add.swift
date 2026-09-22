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
            let context = try projectOptions.context()
            let pbxproj = context.pbxproj
            var runner: OperationRunner
            do {
                runner = try OperationRunner(projectFile: pbxproj)
            } catch {
                throw UsageError("\(error)")
            }
            let project = runner.project
            try context.validate(project)
            runner.exemptions = context.config?.exemptions
            let cwd = ProjectOptions.currentDirectory
            let sourceRoot = context.sourceRoot
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
            let renderer = OperationReport(pbxproj: pbxproj, dryRun: dryRun, json: output.json)
            if let refusal = Add.missingFiles(resolved, under: sourceRoot) {
                renderer.refused(refusal, project: project, paths: resolved)
                throw CommandOutcome.violations.exitCode
            }
            let plan: Plan
            do {
                plan = try AddPlanner.plan(resolved, in: project, conventions: Conventions(flags: flags, config: context.config?.conventions),
                                           exemptions: context.config?.exemptions)
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
