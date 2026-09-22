import ArgumentParser
import Foundation
import PBXModel
import PBXOps

/// `pbxedit query`: which targets build a file and how, or which files a
/// target builds. Read-only: it loads the project file and nothing else.
struct Query: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Report which targets build a file, and how; or list a target's files.",
        discussion: """
            Paths are relative to the current directory and matched, after lexical normalization \
            (no symlinks resolved, nothing read from disk), against the project's source root: the \
            directory holding the .xcodeproj. File lookup is by full path, never by basename.

            Exit code 0 when every path is a member or lies in a synchronized folder, 1 when any is \
            neither, 2 on a usage error or a project file that does not load.
            """)

    @OptionGroup var projectOptions: ProjectOptions
    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: ArgumentHelp("List every file this target builds instead of querying paths.", valueName: "name"))
    var target: String?

    @Argument(help: ArgumentHelp("Files to report on, relative to the current directory.", valueName: "path"))
    var paths: [String] = []

    func run() throws {
        do {
            if target != nil, !paths.isEmpty {
                throw UsageError("--target lists a target's files; pass either paths or --target, not both")
            }
            if target == nil, paths.isEmpty {
                throw UsageError("pass at least one path, or --target <name>")
            }
            let pbxproj = try projectOptions.locate()
            let project = try Query.load(pbxproj)
            if let target {
                guard let listing = TargetMembers(project: project, target: target) else {
                    let names = TargetMembers.targetNames(in: project)
                    throw UsageError("no target named \(target); the project's targets are: \(names.joined(separator: ", "))")
                }
                print(output.json ? TargetReport(listing).json() : TargetReport(listing).text(), terminator: "")
                throw CommandOutcome.ok.exitCode
            }
            let cwd = ProjectOptions.currentDirectory
            let sourceRoot = ProjectOptions.sourceRoot(of: pbxproj).path
            var reports: [MembershipReport] = []
            for raw in paths {
                let path: String
                do {
                    path = try PathArgument.resolve(raw, cwd: cwd, sourceRoot: sourceRoot)
                } catch let error as PathArgumentError {
                    throw UsageError("\(raw): \(error)")
                }
                reports.append(MembershipReport(project: project, path: path))
            }
            let report = QueryReport(results: reports)
            print(output.json ? report.json() : report.text(), terminator: "")
            throw report.outcome.exitCode
        } catch let error as UsageError {
            error.report(json: output.json)
            throw CommandOutcome.usage.exitCode
        }
    }

    /// A project that does not parse or load is a usage error here (design
    /// D3); only `lint` reports it as a finding.
    static func load(_ pbxproj: URL) throws -> Project {
        let bytes: [UInt8]
        do {
            bytes = Array(try Data(contentsOf: pbxproj))
        } catch {
            throw UsageError("cannot read \(pbxproj.path): \(error.localizedDescription)")
        }
        do {
            return try Project.load(bytes)
        } catch {
            throw UsageError("cannot load \(pbxproj.path): \(error)")
        }
    }
}

/// What `query <path>…` prints, in either form.
struct QueryReport {
    let results: [MembershipReport]

    /// Design D3: a member, or a path a synchronized folder covers, is a success.
    var outcome: CommandOutcome {
        results.allSatisfy { $0.member || $0.synchronized != nil } ? .ok : .violations
    }

    func text() -> String {
        var lines: [String] = []
        for report in results {
            if !report.member {
                if let coverage = report.synchronized {
                    let targets = coverage.targets.map { $0.name ?? $0.id.rawValue }.joined(separator: ", ")
                    lines.append("\(report.path): not a member; covered by synchronized group \(coverage.path) (\(coverage.group))\(targets.isEmpty ? "" : " in \(targets)")")
                } else {
                    lines.append("\(report.path): not a member")
                }
                continue
            }
            lines.append("\(report.path): member")
            lines.append("  reference: \(report.fileReference?.rawValue ?? "none")")
            if report.groups.isEmpty {
                lines.append("  group: none")
            } else {
                lines.append("  group: \(report.groupPath ?? "")" + " (\(report.groups.map(\.rawValue).joined(separator: ", ")))")
            }
            for entry in report.memberships {
                var line = "  target: \(entry.target.map { $0.name ?? $0.id.rawValue } ?? "none")"
                line += ", phase: \(entry.phase.map { $0.name ?? $0.id.rawValue } ?? "none")"
                line += ", build file: \(entry.buildFile.rawValue)"
                if !entry.platformFilters.isEmpty { line += ", platforms: \(entry.platformFilters.joined(separator: ", "))" }
                lines.append(line)
            }
            if QueryReport.needsHint(report) { lines.append("  hint: run pbxedit lint") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Design D4: facts that `lint` would judge — no group or several, a
    /// build file in no phase, a phase in no target.
    static func needsHint(_ report: MembershipReport) -> Bool {
        report.member && (report.groups.count != 1 || report.memberships.contains { $0.phase == nil || $0.target == nil })
    }

    struct JSON: Encodable {
        let schemaVersion = 1
        let results: [MembershipReport]
    }

    func json() -> String {
        guard let data = try? JSONEncoder.pbxedit.encode(JSON(results: results)) else { return "{}\n" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

/// What `query --target` prints, in either form.
struct TargetReport {
    let listing: TargetMembers

    init(_ listing: TargetMembers) { self.listing = listing }

    func text() -> String {
        let name = listing.target.name ?? listing.target.id.rawValue
        var lines = ["\(name) (\(listing.target.id)): \(LintReport.count(listing.members.count, "entry", "entries"))"]
        for member in listing.members {
            var line = "  \(member.phase.name ?? member.phase.id.rawValue): \(member.path ?? "<no file>") (\(member.buildFile))"
            if !member.platformFilters.isEmpty { line += " [\(member.platformFilters.joined(separator: ", "))]" }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    struct JSON: Encodable {
        let schemaVersion = 1
        let target: ObjectRef
        let members: [TargetMembers.Member]
    }

    func json() -> String {
        guard let data = try? JSONEncoder.pbxedit.encode(JSON(target: listing.target, members: listing.members)) else { return "{}\n" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
