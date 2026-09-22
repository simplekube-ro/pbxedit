import PBXSyntax

/// Where a group or file reference lives, computed from its `path`, its
/// `sourceTree` and its chain of parent groups (design D4).
public enum ResolvedPath: Equatable, Sendable, CustomStringConvertible {
    /// Relative to the source root (the directory holding the `.xcodeproj`),
    /// normalized: no `.`, no `..` that a preceding component can absorb, no
    /// empty components, no trailing slash. The source root itself is `""`.
    case relative(String)
    /// An `<absolute>` path, normalized the same way.
    case absolute(String)
    /// `sourceTree` is neither `<group>`, `SOURCE_ROOT` nor `<absolute>`, or
    /// an ancestor's is; such references are not files of the project.
    case notProjectRelative(sourceTree: String)

    /// The key under which project-relative and absolute paths are indexed.
    var lookupKey: String? {
        switch self {
        case .relative(let path), .absolute(let path): return path
        case .notProjectRelative: return nil
        }
    }

    public var description: String {
        switch self {
        case .relative(let path): return path
        case .absolute(let path): return path
        case .notProjectRelative(let sourceTree): return "<not project-relative: \(sourceTree)>"
        }
    }
}

/// Path arithmetic on the strings a project file holds. Paths are compared
/// case-sensitively, as the project file itself does.
public enum PathNormalizer {
    /// Collapses `.`, `..` and empty components and drops a trailing slash.
    /// A leading `..` that nothing absorbs is kept for a relative path and
    /// dropped for an absolute one.
    public static func normalize(_ path: String) -> String {
        let absolute = path.utf8.first == 0x2F
        var stack: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." {
                if let last = stack.last, last != ".." {
                    stack.removeLast()
                } else if !absolute {
                    stack.append(component)
                }
                continue
            }
            stack.append(component)
        }
        let joined = stack.joined(separator: "/")
        return absolute ? "/" + joined : joined
    }

    /// `base`, already normalized, joined with `path`; an absolute `path`
    /// replaces `base`.
    static func join(_ base: String, _ path: String) -> String {
        if path.utf8.isEmpty { return base }
        if isAbsolute(path) { return normalize(path) }
        if isPlain(path) { return base.utf8.isEmpty ? path : base + "/" + path }
        return normalize(base.utf8.isEmpty ? path : base + "/" + path)
    }

    static func isAbsolute(_ path: String) -> Bool { path.utf8.first == 0x2F }

    /// Whether every component is a name: no empty, `.` or `..` components,
    /// so that appending `path` to a normalized base needs no normalization.
    static func isPlain(_ path: String) -> Bool {
        var length = 0
        var dots = 0
        for byte in path.utf8 {
            if byte == 0x2F {
                if length == 0 || (dots == length && dots <= 2) { return false }
                length = 0
                dots = 0
            } else {
                length += 1
                if byte == 0x2E { dots += 1 }
            }
        }
        return length > 0 && !(dots == length && dots <= 2)
    }
}

extension Project {
    /// The resolved path of a group, variant group, version group, file
    /// reference or synchronized root group; `nil` for any other object and
    /// for one whose chain of parents never ends.
    public func resolvedPath(of id: ObjectID) -> ResolvedPath? {
        pathIndex.resolved[id] ?? nil
    }

    /// The groups listing `id` among their `children`, in object order: none,
    /// one, or several (design D3; rule M3).
    public func parents(of id: ObjectID) -> [Group] {
        (parentIndex.parents[id] ?? []).compactMap(group)
    }

    /// The file references whose resolved path is `path`, in object order.
    /// Never by basename: `Bar.swift` matches nothing unless a reference
    /// resolves to exactly that at the source root.
    public func fileReferences(at path: String) -> [FileReference] {
        (pathIndex.referencesByPath[PathNormalizer.normalize(path)] ?? []).compactMap(fileReference)
    }

    /// The groups whose resolved path is the directory `path`, ordered by
    /// depth in the group tree and then by object order.
    public func groups(at path: String) -> [Group] {
        (pathIndex.groupsByPath[PathNormalizer.normalize(path)] ?? []).compactMap(group)
    }
}
