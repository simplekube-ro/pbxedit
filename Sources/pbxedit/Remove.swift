import ArgumentParser
import Foundation
import PBXModel
import PBXOps

/// `pbxedit remove`: every trace of a file leaves the project — or, with
/// `--target`, one target's membership — as one plan, checked before and
/// after it is written. The command validates, plans and renders; the
/// planner decides and `OperationRunner` writes. Nothing on disk but
/// `project.pbxproj` is touched, and the file itself is never read.
struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove files from the project: build files, phase entries, group children, the reference, and groups left empty.",
        discussion: """
            Each path loses its build files, their phase entries, its group children and its file reference; a group \
            the removal leaves empty is removed too, up the chain (never the main group or the products group). A file \
            that several targets build needs --target <name> to detach it from that target only (the reference and \
            its group child stay), or --all to remove it from the project. The rule set is checked over the touched \
            objects and their former referrers before the file is written and again after; any error aborts and \
            nothing is written.

            Paths are relative to the current directory, as for query; the file need not exist on disk. Exit code 0 \
            on success, 1 when a path is not in the project, is a localized variant, is covered only by a synchronized \
            folder, needs a choice or violates a rule, 2 on a usage error.
            """)

    @OptionGroup var projectOptions: ProjectOptions
    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Print the plan and a unified diff of project.pbxproj; write nothing.")
    var dryRun = false

    @Option(name: .long, help: ArgumentHelp("Detach the files from this target only; the file reference stays.", valueName: "name"))
    var target: String?

    @Flag(name: .long, help: "Remove a file that several targets build from all of them.")
    var all = false

    @Argument(help: ArgumentHelp("Files to remove, relative to the current directory.", valueName: "path"))
    var paths: [String] = []

    func run() throws {
        do {
            guard !paths.isEmpty else { throw UsageError("pass at least one path") }
            if target != nil, all { throw UsageError("pass either --target <name> or --all, not both") }
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
            if let target, !project.targets.contains(where: { $0.name?.utf8.elementsEqual(target.utf8) == true }) {
                let available = project.targets.compactMap(\.name).sorted()
                throw UsageError(PlanError.unknownTarget(name: target, available: available).description)
            }

            // Everything from here on is reported in the command's own shape.
            let renderer = OperationReport(pbxproj: pbxproj, dryRun: dryRun, json: output.json)
            let plan: Plan
            do {
                plan = try RemovePlanner.plan(resolved, in: project, target: target, all: all)
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
}
