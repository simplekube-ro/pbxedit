import PBXSyntax

/// The derived indexes (design D2–D3), each computed in one pass over
/// `objects` when first queried and dropped by the mutations that can change
/// it. Multiplicity is data: every value is an array, and zero or several
/// entries are legal.

/// Which cached indexes a mutation invalidates.
struct IndexSet: OptionSet {
    let rawValue: Int
    static let parents = IndexSet(rawValue: 1)
    /// Paths depend on parents, so dropping parents drops paths too.
    static let paths = IndexSet(rawValue: 2)
    static let membership = IndexSet(rawValue: 4)
    static let all: IndexSet = [.parents, .paths, .membership]
}

/// child → the groups listing it, in object order.
struct ParentIndex: Equatable {
    var parents: [ObjectID: [ObjectID]] = [:]

    init(_ project: Project) {
        var seen: Set<ObjectID> = []
        for object in project.objects where Kind.groups.contains(object.isa ?? "") && seen.insert(object.id).inserted {
            for child in object.ids("children") ?? [] {
                parents[child, default: []].append(object.id)
            }
        }
    }
}

/// Resolved paths (design D4) and the reverse lookups.
///
/// Built in one pass, and patched for the two mutations a bulk repair makes
/// hundreds of times: a new file reference (an orphan at the root) and an
/// orphan gaining its first parent. Every other mutation drops it.
struct PathIndex: Equatable {
    /// Every group-like object, file reference and synchronized root group →
    /// its resolved path (`nil` inside when the parent chain never ends).
    var resolved: [ObjectID: ResolvedPath?] = [:]
    /// normalized path → file references there, in object order.
    var referencesByPath: [String: [ObjectID]] = [:]
    /// normalized directory → groups there, by depth then object order.
    var groupsByPath: [String: [ObjectID]] = [:]
    /// normalized directory → synchronized root groups there, in object order.
    var synchronizedGroupsByPath: [String: [ObjectID]] = [:]

    /// The objects that have a path, for resolution without table lookups.
    /// Their `path` and `sourceTree` are all that is read from them.
    private var objects: [ObjectID: Object] = [:]

    /// Equality of what the index answers, not of the snapshots it resolved from.
    static func == (lhs: PathIndex, rhs: PathIndex) -> Bool {
        lhs.resolved == rhs.resolved && lhs.referencesByPath == rhs.referencesByPath
            && lhs.groupsByPath == rhs.groupsByPath && lhs.synchronizedGroupsByPath == rhs.synchronizedGroupsByPath
    }

    init(_ project: Project, parents: ParentIndex) {
        let parents = parents.parents
        var order: [ObjectID: Int] = [:]
        var depths: [ObjectID: Int] = [:]
        var pathObjects: [Object] = []
        for (position, object) in project.objects.enumerated() {
            // A duplicate ID (rule S3) is indexed once, as the first entry.
            guard let isa = object.isa, PathIndex.hasPath(isa), order[object.id] == nil else { continue }
            order[object.id] = position
            objects[object.id] = object
            pathObjects.append(object)
        }
        for object in pathObjects {
            let isa = object.isa ?? ""
            let path = resolve(object.id, parents: parents)
            guard let key = path?.lookupKey else { continue }
            if isa == Kind.fileReference {
                referencesByPath[key, default: []].append(object.id)
            } else if isa == Kind.synchronizedRootGroup {
                synchronizedGroupsByPath[key, default: []].append(object.id)
            } else {
                groupsByPath[key, default: []].append(object.id)
                depths[object.id] = PathIndex.depth(of: object.id, parents: parents)
            }
        }
        for (key, groups) in groupsByPath where groups.count > 1 {
            groupsByPath[key] = groups.sorted {
                (depths[$0] ?? 0, order[$0] ?? 0) < (depths[$1] ?? 0, order[$1] ?? 0)
            }
        }
    }

    static func hasPath(_ isa: String) -> Bool {
        isa == Kind.fileReference || isa == Kind.synchronizedRootGroup || Kind.groups.contains(isa)
    }

    /// Whether `isa` is indexed here without affecting any other object's
    /// path: a file reference or a synchronized root group, never a group.
    static func isLeaf(_ isa: String) -> Bool {
        isa == Kind.fileReference || isa == Kind.synchronizedRootGroup
    }

    // MARK: Patching

    /// Indexes a newly created leaf. `entryIndex` gives the current position
    /// of an entry among `objects`, to keep every array in object order.
    mutating func add(_ object: Object, parents: [ObjectID: [ObjectID]], entryIndex: (ObjectID) -> Int?) {
        guard let isa = object.isa, PathIndex.isLeaf(isa) else { return }
        objects[object.id] = object
        place(object.id, parents: parents, entryIndex: entryIndex)
    }

    /// Re-resolves a leaf that has just gained a parent.
    mutating func reparent(_ id: ObjectID, parents: [ObjectID: [ObjectID]], entryIndex: (ObjectID) -> Int?) {
        guard let object = objects[id], let isa = object.isa, PathIndex.isLeaf(isa) else { return }
        if let old = resolved[id]??.lookupKey {
            referencesByPath[old]?.removeAll { $0 == id }
            synchronizedGroupsByPath[old]?.removeAll { $0 == id }
            if referencesByPath[old]?.isEmpty == true { referencesByPath[old] = nil }
            if synchronizedGroupsByPath[old]?.isEmpty == true { synchronizedGroupsByPath[old] = nil }
        }
        resolved[id] = nil
        place(id, parents: parents, entryIndex: entryIndex)
    }

    private mutating func place(_ id: ObjectID, parents: [ObjectID: [ObjectID]], entryIndex: (ObjectID) -> Int?) {
        guard let key = resolve(id, parents: parents)?.lookupKey, let isa = objects[id]?.isa else { return }
        if isa == Kind.fileReference {
            PathIndex.insert(id, into: &referencesByPath[key, default: []], entryIndex: entryIndex)
        } else {
            PathIndex.insert(id, into: &synchronizedGroupsByPath[key, default: []], entryIndex: entryIndex)
        }
    }

    /// Inserts `id` keeping `array` in object order.
    private static func insert(_ id: ObjectID, into array: inout [ObjectID], entryIndex: (ObjectID) -> Int?) {
        let position = entryIndex(id) ?? Int.max
        let index = array.firstIndex { (entryIndex($0) ?? Int.max) > position } ?? array.count
        array.insert(id, at: index)
    }

    // MARK: Resolution

    /// Design D4. Memoized. An ID is marked unresolved before its parent is
    /// resolved, so a chain that revisits it resolves to `nil`.
    private mutating func resolve(_ id: ObjectID, parents: [ObjectID: [ObjectID]]) -> ResolvedPath? {
        if let known = resolved[id] { return known }
        guard let object = objects[id] else { return nil }
        let path = object.string("path") ?? ""
        let sourceTree = object.attributes?["sourceTree"]?.string
        let result: ResolvedPath?
        if sourceTree == nil || sourceTree?.matches(Kind.groupSourceTree) == true {
            if let parent = parents[id]?.first {
                resolved[id] = .some(nil)
                switch resolve(parent, parents: parents) {
                case .relative(let base)?:
                    let joined = PathNormalizer.join(base, path)
                    result = PathNormalizer.isAbsolute(joined) ? .absolute(joined) : .relative(joined)
                case .absolute(let base)?:
                    result = .absolute(PathNormalizer.join(base, path))
                case .notProjectRelative(let tree)?:
                    result = .notProjectRelative(sourceTree: tree)
                case nil:
                    result = nil
                }
            } else {
                let joined = PathNormalizer.normalize(path)
                result = PathNormalizer.isAbsolute(joined) ? .absolute(joined) : .relative(joined)
            }
        } else if sourceTree?.matches(Kind.sourceRootSourceTree) == true {
            result = PathNormalizer.isAbsolute(path)
                ? .absolute(PathNormalizer.normalize(path)) : .relative(PathNormalizer.normalize(path))
        } else if sourceTree?.matches(Kind.absoluteSourceTree) == true {
            result = .absolute(PathNormalizer.normalize(PathNormalizer.isAbsolute(path) ? path : "/" + path))
        } else {
            result = .notProjectRelative(sourceTree: sourceTree?.value ?? "")
        }
        resolved[id] = .some(result)
        return result
    }

    /// The number of ancestors through first parents, stopping at a revisit.
    private static func depth(of id: ObjectID, parents: [ObjectID: [ObjectID]]) -> Int {
        var depth = 0
        var current = id
        var seen: Set<ObjectID> = [id]
        while let parent = parents[current]?.first, !seen.contains(parent) {
            depth += 1
            seen.insert(parent)
            current = parent
        }
        return depth
    }
}

/// file reference → build files → phases → targets.
struct MembershipIndex {
    /// file reference → the build files pointing at it, in object order.
    var buildFilesByFileRef: [ObjectID: [ObjectID]] = [:]
    /// build file → the phases listing it, one per listing, in object order.
    var phasesByBuildFile: [ObjectID: [ObjectID]] = [:]
    /// phase → the targets listing it, in object order.
    var targetsByPhase: [ObjectID: [ObjectID]] = [:]
    /// synchronized root group → the targets listing it.
    var targetsBySynchronizedGroup: [ObjectID: [ObjectID]] = [:]

    init(_ project: Project) {
        var seen: Set<ObjectID> = []
        for object in project.objects where seen.insert(object.id).inserted {
            let isa = object.isa ?? ""
            if isa == Kind.buildFile {
                if let fileRef = object.id("fileRef") { buildFilesByFileRef[fileRef, default: []].append(object.id) }
            } else if Kind.buildPhases.contains(isa) {
                for file in object.ids("files") ?? [] { phasesByBuildFile[file, default: []].append(object.id) }
            } else if Kind.targets.contains(isa) {
                for phase in object.ids("buildPhases") ?? [] { targetsByPhase[phase, default: []].append(object.id) }
                for group in object.ids("fileSystemSynchronizedGroups") ?? [] {
                    targetsBySynchronizedGroup[group, default: []].append(object.id)
                }
            }
        }
    }
}
