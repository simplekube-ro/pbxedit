import PBXModel

/// Why a path argument cannot name a file of the project (design D1).
public enum PathArgumentError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The argument, made absolute and normalized, is not inside the source root.
    case outsideSourceRoot(path: String, sourceRoot: String)
    /// The argument names the source root itself, which is a directory, not a file.
    case isSourceRoot(sourceRoot: String)

    public var description: String {
        switch self {
        case .outsideSourceRoot(let path, let sourceRoot):
            return "\(path) is outside the source root \(sourceRoot) (the directory holding the .xcodeproj)"
        case .isSourceRoot(let sourceRoot):
            return "the path is the source root \(sourceRoot) itself, not a file in it"
        }
    }
}

/// The one interpretation of a path argument every command shares (design D1):
/// relative to the current directory on the way in, relative to the source
/// root — the directory holding the `.xcodeproj` — inside. Purely lexical:
/// no symlink is resolved and the disk is never read, so a moved or deleted
/// file is still addressable.
public enum PathArgument {
    /// `raw`, made absolute against `cwd` unless already absolute, normalized,
    /// and stripped of the `sourceRoot` prefix. `cwd` and `sourceRoot` must
    /// be absolute.
    public static func resolve(_ raw: String, cwd: String, sourceRoot: String) throws -> String {
        let root = PathNormalizer.normalize(sourceRoot)
        let absolute = PathNormalizer.normalize(raw.hasPrefix("/") ? raw : cwd + "/" + raw)
        if absolute == root { throw PathArgumentError.isSourceRoot(sourceRoot: root) }
        let prefix = root == "/" ? "/" : root + "/"
        guard absolute.hasPrefix(prefix) else {
            throw PathArgumentError.outsideSourceRoot(path: absolute, sourceRoot: root)
        }
        return String(absolute.dropFirst(prefix.count))
    }
}
