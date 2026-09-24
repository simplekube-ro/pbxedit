import Foundation

/// What the disk rules may ask about the file system (design D5). Paths are
/// relative to the source root, the directory holding the `.xcodeproj`, or
/// absolute. The reader is only ever handed to `DiskRule`s, and only when
/// `--disk` is set.
public protocol DiskReader: Sendable {
    /// Whether anything — file, directory or link — exists at `path`.
    func exists(_ path: String) -> Bool
    /// Whether an entry exists at `path` with every component below the
    /// source root spelled exactly as its directory lists it. On a
    /// case-insensitive volume `exists` answers yes for any spelling of a
    /// name; this answers yes only for the one the directory holds.
    func existsAsSpelled(_ path: String) -> Bool
    /// The names (not paths) of the entries directly inside `path` that Xcode
    /// shows as files: regular files, and the bundle directories of
    /// `DiskEntry.bundleExtensions`. Empty when `path` is not a directory.
    func files(in path: String) -> [String]
}

extension DiskReader {
    /// Exact for every reader that is not a case-insensitive file system.
    public func existsAsSpelled(_ path: String) -> Bool { exists(path) }
}

public enum DiskEntry {
    /// Directories Xcode shows and references as one file.
    public static let bundleExtensions: Set<String> = [
        "xcassets", "xcdatamodeld", "xcmappingmodel", "bundle", "framework", "xcframework", "app", "appex",
        "playground", "scnassets", "rcproject", "docc",
    ]
}

/// The reader the command line uses: `FileManager` under the source root.
public struct FileSystemDiskReader: DiskReader {
    public let sourceRoot: URL

    public init(sourceRoot: URL) { self.sourceRoot = sourceRoot }

    private func url(_ path: String) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : sourceRoot.appendingPathComponent(path)
    }

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    /// Walks the components from the source root (or `/`), each one looked
    /// up in its directory's listing; `.` and `..` are followed unchecked.
    public func existsAsSpelled(_ path: String) -> Bool {
        var directory = path.hasPrefix("/") ? URL(fileURLWithPath: "/") : sourceRoot
        for component in path.split(separator: "/").map(String.init) {
            if component != "." && component != ".." {
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path), names.contains(component) else {
                    return false
                }
            }
            directory.appendPathComponent(component)
        }
        return true
    }

    public func files(in path: String) -> [String] {
        let directory = url(path)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { name in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path, isDirectory: &isDirectory) else {
                return false
            }
            return !isDirectory.boolValue || DiskEntry.bundleExtensions.contains((name as NSString).pathExtension.lowercased())
        }.sorted()
    }
}
