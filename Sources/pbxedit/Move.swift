import ArgumentParser
import Foundation
import PBXModel
import PBXOps

/// `pbxedit move`: the project catches up with a file or directory that has
/// already been moved on disk — the reference keeps its ID and is re-parented
/// and re-pathed, comments follow, and membership follows the destination's
/// conventions — as one plan, checked before and after it is written. The
/// command validates, plans and renders; the planner decides and
/// `OperationRunner` writes. Nothing on disk but `project.pbxproj` is
/// touched; the disk is read only to confirm the move has happened.
struct Move: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record a move or rename that has already happened on disk: keep the file's identity, re-parent it, follow the destination's membership.",
        discussion: """
            Move the file (or directory) first — git mv, Finder — then run this. The file reference keeps its ID and \
            becomes a child of the group for its new directory (created as needed); its path, sourceTree and name are \
            rewritten only where they change, and every comment naming it follows. Membership is re-derived for the \
            destination as add derives it — flags, then .pbxedit.yml, then the destination's siblings — and the file \
            is detached from targets no longer chosen and attached to new ones; --keep-membership leaves it as it was. \
            A directory as <from> moves every member beneath it. Groups left empty are removed. The rule set is \
            checked over the touched objects before the file is written and again after; any error aborts and \
            nothing is written.

            Paths are relative to the current directory, as for query. Exit code 0 on success, 1 when the disk does \
            not yet reflect the move, the source is not in the project, the destination is taken, a decision cannot \
            be made or a rule is violated, 2 on a usage error.
            """)

    @OptionGroup var projectOptions: ProjectOptions
    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Print the plan and a unified diff of project.pbxproj; write nothing.")
    var dryRun = false

    @Flag(name: .customLong("keep-membership"), help: "Leave targets and platformFilters exactly as they were; do not follow the destination's siblings.")
    var keepMembership = false

    @Option(name: .long, help: ArgumentHelp("A target the file belongs to after the move, instead of the inferred ones; repeatable.", valueName: "name"))
    var target: [String] = []

    @Option(name: .long, help: ArgumentHelp("platformFilters for the file's build files after the move: comma-separated names, or none.", valueName: "list"))
    var platform: String?

    @Argument(help: ArgumentHelp("The old path, relative to the current directory; a directory moves every member beneath it.", valueName: "from"))
    var from: String

    @Argument(help: ArgumentHelp("The new path, which must already exist on disk.", valueName: "to"))
    var to: String

    func run() throws {
        do {
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
            let source: String
            let destination: String
            do {
                source = try PathArgument.resolve(from, cwd: cwd, sourceRoot: sourceRoot.path)
            } catch let error as PathArgumentError {
                throw UsageError("\(from): \(error)")
            }
            do {
                destination = try PathArgument.resolve(to, cwd: cwd, sourceRoot: sourceRoot.path)
            } catch let error as PathArgumentError {
                throw UsageError("\(to): \(error)")
            }
            guard source != destination else { throw UsageError("\(from) and \(to) are the same path; nothing to move") }
            if keepMembership, !target.isEmpty || platform != nil {
                throw UsageError("pass either --keep-membership or --target/--platform, not both")
            }
            let available = project.targets.compactMap(\.name).sorted()
            for name in target where !project.targets.contains(where: { $0.name?.utf8.elementsEqual(name.utf8) == true }) {
                throw UsageError(PlanError.unknownTarget(name: name, available: available).description)
            }
            var flags = Conventions.Flags(targets: target.isEmpty ? nil : target, platformFilters: nil, phase: nil)
            if let platform {
                do {
                    flags.platformFilters = try PlatformFilters.parse(platform)
                } catch {
                    throw UsageError("\(error)")
                }
            }

            // Everything from here on is reported in the command's own shape.
            var renderer = OperationReport(pbxproj: pbxproj, dryRun: dryRun, json: output.json)
            renderer.moves = [Plan.Move(from: source, to: destination)]
            let plan: Plan
            do {
                plan = try MovePlanner.plan(
                    from: source, to: destination, in: project, conventions: Conventions(flags: flags, config: context.config?.conventions),
                    keepMembership: keepMembership, disk: FileSystemDiskReader(sourceRoot: sourceRoot), exemptions: context.config?.exemptions)
            } catch let error as PlanError {
                renderer.refused(error.description, project: project, paths: [destination])
                throw CommandOutcome.violations.exitCode
            }
            let result = runner.run(plan, dryRun: dryRun)
            renderer.render(result, fallback: project, paths: plan.moves.map(\.to))
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
