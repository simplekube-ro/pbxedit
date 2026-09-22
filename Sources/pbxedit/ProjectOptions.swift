import ArgumentParser
import Foundation
import PBXModel
import PBXOps

/// `--project`, `--config` and their defaults: the single `.xcodeproj` in the
/// current directory (spec: Project location), or the one `.pbxedit.yml`
/// names (conventions-config: Default project).
struct ProjectOptions: ParsableArguments {
    @Option(
        name: .long,
        help: ArgumentHelp(
            "The .xcodeproj directory or project.pbxproj file to operate on.",
            discussion: "Without it, the project named by .pbxedit.yml is used, else the single .xcodeproj in the current directory.",
            valueName: "path"))
    var project: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "The configuration file to use.",
            discussion: "Without it, the nearest .pbxedit.yml in the current directory or its ancestors is used, if any.",
            valueName: "path"))
    var config: String?

    /// The project file, its source root and the configuration bound to
    /// that root — everything a command needs before it loads the project.
    func context() throws -> ProjectContext {
        let file = try loadConfig()
        let pbxproj: URL
        if let project {
            pbxproj = try ProjectOptions.locate(project, source: "--project")
        } else if let file, let configured = file.projectURL {
            pbxproj = try ProjectOptions.locate(configured.path, source: "project: in \(file.url.path)")
        } else {
            pbxproj = try ProjectOptions.locateInCurrentDirectory()
        }
        let sourceRoot = ProjectOptions.sourceRoot(of: pbxproj)
        var bound: BoundConfig?
        if let file {
            do {
                bound = try file.bind(sourceRoot: sourceRoot)
            } catch {
                throw UsageError("\(error)")
            }
        }
        return ProjectContext(pbxproj: pbxproj, sourceRoot: sourceRoot, config: bound)
    }

    /// `--config`, or the discovered `.pbxedit.yml`, decoded strictly; any
    /// problem is a usage error (spec: Strict validation).
    private func loadConfig() throws -> ConfigFile? {
        do {
            if let config {
                let url = URL(fileURLWithPath: config)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                    throw UsageError("no such configuration file: \(config)")
                }
                return try ConfigFile.load(url)
            }
            return try ConfigFile.discover(from: URL(fileURLWithPath: ProjectOptions.currentDirectory))
        } catch let error as ConfigError {
            throw UsageError(error.description)
        }
    }

    /// The `project.pbxproj` for a path given by `source`: a `.xcodeproj`
    /// directory or a `project.pbxproj` file.
    private static func locate(_ path: String, source: String) throws -> URL {
        let manager = FileManager.default
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw UsageError("no such project: \(path) (\(source))")
        }
        if isDirectory.boolValue {
            let pbxproj = url.appendingPathComponent("project.pbxproj")
            guard url.pathExtension == "xcodeproj", manager.fileExists(atPath: pbxproj.path) else {
                throw UsageError("expected a .xcodeproj directory containing project.pbxproj, or a project.pbxproj file: \(path) (\(source))")
            }
            return pbxproj.standardizedFileURL
        }
        guard url.lastPathComponent == "project.pbxproj" else {
            throw UsageError("expected a .xcodeproj directory or a project.pbxproj file: \(path) (\(source))")
        }
        return url.standardizedFileURL
    }

    private static func locateInCurrentDirectory() throws -> URL {
        let manager = FileManager.default
        let cwd = URL(fileURLWithPath: manager.currentDirectoryPath)
        let candidates = ((try? manager.contentsOfDirectory(atPath: cwd.path)) ?? [])
            .filter { $0.hasSuffix(".xcodeproj") }
            .sorted()
        switch candidates.count {
        case 1:
            let pbxproj = cwd.appendingPathComponent(candidates[0]).appendingPathComponent("project.pbxproj")
            guard manager.fileExists(atPath: pbxproj.path) else {
                throw UsageError("\(candidates[0]) has no project.pbxproj")
            }
            return pbxproj.standardizedFileURL
        case 0:
            throw UsageError("no .xcodeproj in \(cwd.path); pass --project")
        default:
            throw UsageError("several .xcodeproj in \(cwd.path): \(candidates.joined(separator: ", ")); pass --project")
        }
    }

    /// The directory holding the `.xcodeproj`: what paths in the project file
    /// are relative to.
    static func sourceRoot(of pbxproj: URL) -> URL {
        pbxproj.deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The current directory, standardized exactly as `context()` standardizes
    /// `--project` (Foundation drops a leading `/private` from an existing
    /// path, for one), so a relative path argument and a relative `--project`
    /// always agree on the source root.
    static var currentDirectory: String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.path
    }
}

/// What `ProjectOptions.context()` resolved.
struct ProjectContext {
    let pbxproj: URL
    let sourceRoot: URL
    /// `nil` without a configuration file.
    let config: BoundConfig?

    /// The project-dependent validation of the configuration (spec: Target
    /// that does not exist): before any command acts on a loaded project.
    func validate(_ project: Project) throws {
        do {
            try config?.validate(targets: project.targets.compactMap(\.name))
        } catch {
            throw UsageError("\(error)")
        }
    }
}

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Print one JSON object instead of text.")
    var json = false
}
