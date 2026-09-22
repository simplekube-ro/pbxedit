import ArgumentParser
import Foundation

/// `--project` and its default: the single `.xcodeproj` in the current
/// directory (spec: Project location).
struct ProjectOptions: ParsableArguments {
    @Option(
        name: .long,
        help: ArgumentHelp(
            "The .xcodeproj directory or project.pbxproj file to operate on.",
            discussion: "Without it, the single .xcodeproj in the current directory is used.",
            valueName: "path"))
    var project: String?

    /// The `project.pbxproj` to operate on.
    func locate() throws -> URL {
        let manager = FileManager.default
        if let project {
            let url = URL(fileURLWithPath: project)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw UsageError("no such project: \(project)")
            }
            if isDirectory.boolValue {
                let pbxproj = url.appendingPathComponent("project.pbxproj")
                guard url.pathExtension == "xcodeproj", manager.fileExists(atPath: pbxproj.path) else {
                    throw UsageError("expected a .xcodeproj directory containing project.pbxproj, or a project.pbxproj file: \(project)")
                }
                return pbxproj.standardizedFileURL
            }
            guard url.lastPathComponent == "project.pbxproj" else {
                throw UsageError("expected a .xcodeproj directory or a project.pbxproj file: \(project)")
            }
            return url.standardizedFileURL
        }
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
}

struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Print one JSON object instead of text.")
    var json = false
}
