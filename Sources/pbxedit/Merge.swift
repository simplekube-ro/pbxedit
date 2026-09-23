import ArgumentParser
import Foundation
import PBXModel
import PBXOps

/// `pbxedit merge`: a semantic three-way merge of three versions of one
/// `project.pbxproj` (merge design D11). The command reads the three
/// inputs, locates the output (D12), hands bytes to `MergeEngine`, renders
/// its report, and writes the one result — atomically, read back and
/// re-checked. It never prompts.
struct Merge: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Merge three versions of one project.pbxproj: membership is replayed, everything else merged as text.",
        discussion: """
            Pass the common base, ours and theirs (for a git conflict: `git show :1:<path>`, `:2:` and `:3:`). File \
            membership theirs changed is replayed onto ours with add's, remove's and move's planners; everything \
            else is merged line by line. Every change either side made is accounted for before the output is \
            written; nothing is written when a check fails.

            When a unit of membership or a hunk of text needs a choice, the command exits 3 and prints every open \
            item with its key and allowed choices, and a decisions template (JSON) bound to the three inputs. Fill \
            it in and pass it back with --decisions.

            The output is --output, or else the project's project.pbxproj, located as for every command. Exit code 0 \
            when merged or nothing to merge, 1 when a check fails or a step is refused, 2 on a usage error or \
            input the merge does not support, 3 when decisions are needed.
            """)

    @OptionGroup var projectOptions: ProjectOptions
    @OptionGroup var outputOptions: OutputOptions

    @Flag(name: .long, help: "Print the report and a unified diff of ours against the merge; write nothing.")
    var dryRun = false

    @Option(name: .long, help: ArgumentHelp("The decisions file: the template of an earlier run with choices filled in.", valueName: "file"))
    var decisions: String?

    @Option(name: .long, help: ArgumentHelp("The file to write the merge to, instead of the project's project.pbxproj.", valueName: "file"))
    var output: String?

    @Argument(help: ArgumentHelp("The common ancestor.", valueName: "base"))
    var base: String

    @Argument(help: ArgumentHelp("Our version; the merge is made on top of it.", valueName: "ours"))
    var ours: String

    @Argument(help: ArgumentHelp("Their version; its changes are replayed and merged in.", valueName: "theirs"))
    var theirs: String

    func run() throws {
        let json = outputOptions.json
        do {
            // Design D11: the inputs are read fully before anything is written.
            let cwd = URL(fileURLWithPath: ProjectOptions.currentDirectory)
            func read(_ path: String, _ role: String) throws -> [UInt8] {
                let url = URL(fileURLWithPath: path, relativeTo: cwd)
                do {
                    return Array(try Data(contentsOf: url))
                } catch {
                    throw UsageError("cannot read \(role) \(path): \(error.localizedDescription)")
                }
            }
            let baseBytes = try read(base, "base")
            let oursBytes = try read(ours, "ours")
            let theirsBytes = try read(theirs, "theirs")

            // Design D12: where the output goes, and the configuration bound to the located project.
            let target: URL
            var exemptions: Exemptions?
            if let output {
                target = URL(fileURLWithPath: output, relativeTo: cwd).standardizedFileURL
                if projectOptions.project != nil || projectOptions.config != nil {
                    // An explicit --config binds its paths to a project's source root, so it needs one located.
                    let file = try projectOptions.loadConfig()
                    let pbxproj: URL
                    do {
                        pbxproj = try projectOptions.locate(config: file)
                    } catch let error as UsageError where projectOptions.project == nil {
                        throw UsageError("--config binds its paths to a project's source root, and no project was found: \(error.message)")
                    }
                    exemptions = try projectOptions.context(pbxproj: pbxproj, config: file).config?.exemptions
                }
            } else {
                // A broken configuration is reported as itself, not as a missing output.
                let file = try projectOptions.loadConfig()
                let pbxproj: URL
                do {
                    pbxproj = try projectOptions.locate(config: file)
                } catch let error as UsageError {
                    throw UsageError("nowhere to write the merge: \(error.message); pass --output <file>, or --project <path> for the project's project.pbxproj")
                }
                let context = try projectOptions.context(pbxproj: pbxproj, config: file)
                target = context.pbxproj
                exemptions = context.config?.exemptions
            }

            var decided: MergeDecisions?
            if let decisions {
                do {
                    decided = try MergeDecisions.decode(Data(read(decisions, "the decisions file")))
                } catch let error as MergeDecisionsError {
                    throw UsageError("\(decisions): \(error)")
                }
            }

            let engine = MergeEngine(exemptions: exemptions, decisions: decided)
            let report = engine.run(base: baseBytes, ours: oursBytes, theirs: theirsBytes)
            let previous = try? Data(contentsOf: target).map { $0 }
            let renderer = MergeRenderer(output: target, dryRun: dryRun, json: json, paths: (base, ours, theirs))

            var modified = false
            var diff: String?
            var writeFailure: CheckResult?
            var writeError: String?
            if report.status == .merged, let result = report.result {
                if dryRun {
                    diff = UnifiedDiff.make(from: oursBytes, to: result, name: target.lastPathComponent)
                } else if previous != result {
                    (modified, writeFailure, writeError) = Merge.write(result, to: target, previous: previous) { written in
                        engine.recheck(written: written, ours: oursBytes, theirs: theirsBytes, report: report)
                    }
                }
            }
            renderer.render(report, modified: modified, diff: diff, writeFailure: writeFailure, writeError: writeError)
            if writeFailure != nil || writeError != nil { throw CommandOutcome.violations.exitCode }
            switch report.status {
            case .merged: throw CommandOutcome.ok.exitCode
            case .failed: throw CommandOutcome.violations.exitCode
            case .unsupported: throw CommandOutcome.usage.exitCode
            case .decisionsNeeded: throw CommandOutcome.decisionsNeeded.exitCode
            }
        } catch let error as UsageError {
            error.report(json: json)
            throw CommandOutcome.usage.exitCode
        }
    }

    /// Design D11: the atomic write, the read-back and the re-check, the
    /// previous bytes restored (or the new file removed) on failure.
    /// `modified` compares what is on disk afterwards with what was before.
    static func write(_ bytes: [UInt8], to url: URL, previous: [UInt8]?,
                      recheck: ([UInt8]) -> CheckResult?) -> (modified: Bool, failure: CheckResult?, error: String?) {
        func onDisk() -> [UInt8]? { try? Data(contentsOf: url).map { $0 } }
        do {
            try AtomicFile.write(bytes, to: url)
        } catch {
            return (onDisk() != previous, nil, "cannot write \(url.path): \(error)")
        }
        guard let failure = recheck(onDisk() ?? []) else { return (onDisk() != previous, nil, nil) }
        var restoreError: String?
        do {
            if let previous {
                try AtomicFile.write(previous, to: url)
            } else {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            restoreError = "and the previous file could not be restored: \(error)"
        }
        return (onDisk() != previous, failure, restoreError)
    }
}
