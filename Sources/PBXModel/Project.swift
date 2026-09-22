import PBXSyntax

/// Why a parsed file cannot be read as a project. Anything else — dangling
/// references, orphans, duplicates — loads and is observable through the model.
public enum LoadError: Error, Equatable, CustomStringConvertible {
    case rootIsNotADictionary
    case missingObjects
    case objectsIsNotADictionary
    case missingRootObject
    case rootObjectNotFound(ObjectID)

    public var description: String {
        switch self {
        case .rootIsNotADictionary: return "the top-level value is not a dictionary"
        case .missingObjects: return "the project has no 'objects' dictionary"
        case .objectsIsNotADictionary: return "'objects' is not a dictionary"
        case .missingRootObject: return "the project has no 'rootObject'"
        case .rootObjectNotFound(let id): return "the root object '\(id)' cannot be found in 'objects'"
        }
    }
}

/// A typed view over the syntax tree of a project file (design D1). The tree
/// is the only state; every query reads it, through indexes that are rebuilt
/// after a mutation (design D2).
public struct Project {
    public static let objectsKey = "objects"

    /// The tree. Read it to diff or to serialize; mutate it only through the
    /// model's primitives, which keep the indexes honest.
    public private(set) var tree: SyntaxTree
    public let rootObjectID: ObjectID
    private var cache = Cache()

    public init(tree: SyntaxTree) throws {
        guard let root = tree.root.dictionary else { throw LoadError.rootIsNotADictionary }
        guard let objects = root[Project.objectsKey] else { throw LoadError.missingObjects }
        guard objects.dictionary != nil else { throw LoadError.objectsIsNotADictionary }
        guard let rootObject = root["rootObject"]?.stringValue else { throw LoadError.missingRootObject }
        self.tree = tree
        self.rootObjectID = ObjectID(rootObject)
        guard contains(rootObjectID) else { throw LoadError.rootObjectNotFound(rootObjectID) }
    }

    /// Parses and loads. Throws a `ParseError` or a `LoadError`.
    public static func load(_ bytes: [UInt8]) throws -> Project {
        try Project(tree: try SyntaxTree.parse(bytes).get())
    }

    public func serialize() -> [UInt8] { tree.serialize() }

    public var objectVersion: String? { tree.node(at: ["objectVersion"])?.stringValue }

    // MARK: Object table

    /// The entries of the `objects` dictionary. Loading guarantees it exists;
    /// the empty fallback only satisfies the type system.
    var objectEntries: [DictionaryNode.Entry] {
        tree.node(at: [.key(Project.objectsKey)])?.dictionary?.entries ?? []
    }

    /// Every entry of `objects` in source order, duplicates included.
    public var objects: [Object] {
        objectEntries.map { Object(id: ObjectID($0.key.value), value: $0.value) }
    }

    /// IDs that key more than one entry (rule S3); the first entry is the one
    /// lookups return.
    public var duplicateIDs: [ObjectID] { table.duplicates }

    public func contains(_ id: ObjectID) -> Bool { table.index[id] != nil }

    /// The object keyed by exactly `id`.
    public func object(_ id: ObjectID) -> Object? {
        guard let index = entryIndex(of: id) else { return nil }
        return Object(id: id, value: objectEntries[index].value)
    }

    /// The position of `id`'s entry. The table's positions are hints: an
    /// insertion or deletion shifts the entries after it, so a hint is
    /// checked against the entry it names and corrected by a scan when stale.
    func entryIndex(of id: ObjectID) -> Int? {
        guard let hint = table.index[id] else { return nil }
        let entries = objectEntries
        if entries.indices.contains(hint), entries[hint].key.matches(id.rawValue) { return hint }
        guard let found = entries.firstIndex(where: { $0.key.matches(id.rawValue) }) else { return nil }
        cache.table?.index[id] = found
        return found
    }

    public subscript(id: ObjectID) -> Object? { object(id) }

    /// The `PBXProject` object. Loading guarantees it exists; only deleting
    /// it can make this `nil`.
    public var rootObject: Object? { object(rootObjectID) }

    // MARK: Typed views

    public func fileReference(_ id: ObjectID) -> FileReference? {
        object(id).flatMap { $0.isa == Kind.fileReference ? FileReference(object: $0) : nil }
    }

    public func buildFile(_ id: ObjectID) -> BuildFile? {
        object(id).flatMap { $0.isa == Kind.buildFile ? BuildFile(object: $0) : nil }
    }

    public func group(_ id: ObjectID) -> Group? {
        object(id).flatMap { Kind.groups.contains($0.isa ?? "") ? Group(object: $0) : nil }
    }

    public func synchronizedRootGroup(_ id: ObjectID) -> SynchronizedRootGroup? {
        object(id).flatMap { $0.isa == Kind.synchronizedRootGroup ? SynchronizedRootGroup(object: $0) : nil }
    }

    public func buildPhase(_ id: ObjectID) -> BuildPhase? {
        object(id).flatMap { Kind.buildPhases.contains($0.isa ?? "") ? BuildPhase(object: $0) : nil }
    }

    public func target(_ id: ObjectID) -> Target? {
        object(id).flatMap { Kind.targets.contains($0.isa ?? "") ? Target(object: $0) : nil }
    }

    /// The file reference a build file points at, or `nil` when its `fileRef`
    /// is absent or does not resolve.
    public func fileReference(of buildFile: BuildFile) -> FileReference? {
        buildFile.fileRef.flatMap(fileReference)
    }

    public var fileReferences: [FileReference] { objects.filter { $0.isa == Kind.fileReference }.map(FileReference.init) }
    public var buildFiles: [BuildFile] { objects.filter { $0.isa == Kind.buildFile }.map(BuildFile.init) }
    public var groups: [Group] { objects.filter { Kind.groups.contains($0.isa ?? "") }.map(Group.init) }
    public var variantGroups: [Group] { groups.filter { $0.isa == Kind.variantGroup } }
    public var synchronizedRootGroups: [SynchronizedRootGroup] {
        objects.filter { $0.isa == Kind.synchronizedRootGroup }.map(SynchronizedRootGroup.init)
    }
    public var buildPhases: [BuildPhase] { objects.filter { Kind.buildPhases.contains($0.isa ?? "") }.map(BuildPhase.init) }
    public var targets: [Target] { objects.filter { Kind.targets.contains($0.isa ?? "") }.map(Target.init) }
    public var nativeTargets: [Target] { targets.filter { $0.isa == Kind.nativeTarget } }

    /// The root object's `mainGroup`, when it resolves to a group.
    public var mainGroup: Group? { rootObject?.id("mainGroup").flatMap(group) }

    // MARK: Mutation and cache (design D2)

    /// An edit that leaves every entry of `objects` where it is — children,
    /// phase entries, attributes, comments. The object table and the section
    /// map stay valid; the derived indexes named by `dropping` are dropped.
    mutating func mutateValues(dropping: IndexSet, _ body: (inout SyntaxTree) throws -> Void) rethrows {
        try body(&tree)
        cache.drop(dropping)
    }

    /// An edit that inserts the entry `id` into `objects`. The table, the
    /// section map and — for a file reference or synchronized root group —
    /// the path index are patched rather than rebuilt (design D2's cost).
    mutating func insertObject(_ id: ObjectID, isa: String, _ body: (inout SyntaxTree) throws -> Void) rethrows {
        try body(&tree)
        if let position = objectEntries.firstIndex(where: { $0.key.matches(id.rawValue) }) {
            cache.table?.index[id] = position
            cache.sections?.inserted(id.rawValue, at: position, isa: isa)
        } else {
            cache.table = nil
            cache.sections = nil
        }
        if Kind.groups.contains(isa) {
            cache.drop(.parents)
        } else if PathIndex.isLeaf(isa), var paths = cache.paths, let parents = cache.parents, let object = object(id) {
            cache.paths = nil
            paths.add(object, parents: parents.parents, entryIndex: entryIndex)
            cache.paths = paths
        }
        if isa == Kind.buildFile || Kind.buildPhases.contains(isa) || Kind.targets.contains(isa) {
            cache.drop(.membership)
        }
    }

    /// An edit that adds `child` to a group's `children`. When the child had
    /// no parent, the parent and path indexes are patched; otherwise the
    /// order of its parents would have to be recomputed, so they are dropped.
    mutating func insertChild(_ child: ObjectID, into group: ObjectID, _ body: (inout SyntaxTree) throws -> Void) rethrows {
        try body(&tree)
        let isa = object(child)?.isa ?? ""
        guard !Kind.groups.contains(isa), var parents = cache.parents, parents.parents[child] == nil else {
            cache.drop(.parents)
            return
        }
        cache.parents = nil
        parents.parents[child] = [group]
        cache.parents = parents
        if var paths = cache.paths {
            cache.paths = nil
            paths.reparent(child, parents: parents.parents, entryIndex: entryIndex)
            cache.paths = paths
        }
    }

    /// An edit that removes the entry at `position` of `objects`.
    mutating func removeObject(_ id: ObjectID, at position: Int, _ body: (inout SyntaxTree) throws -> Void) rethrows {
        try body(&tree)
        if table.duplicates.contains(id) {
            // Another entry with this ID remains; rebuild rather than reason about it.
            cache.table = nil
        } else {
            cache.table?.index[id] = nil
        }
        cache.sections?.removed(at: position)
        cache.drop(.all)
    }

    /// The path of an object's entry in the tree.
    static func path(of id: ObjectID) -> SyntaxPath { [.key(objectsKey), .key(id.rawValue)] }

    static func path(of id: ObjectID, _ key: String) -> SyntaxPath { path(of: id) + [.key(key)] }

    final class Cache {
        var table: ObjectTable?
        var sections: SectionMap?
        var parents: ParentIndex?
        var paths: PathIndex?
        var membership: MembershipIndex?

        func drop(_ indexes: IndexSet) {
            if indexes.contains(.parents) {
                parents = nil
                paths = nil
            }
            if indexes.contains(.paths) { paths = nil }
            if indexes.contains(.membership) { membership = nil }
        }
    }

    struct ObjectTable {
        /// ID → index of the first entry with that key.
        var index: [ObjectID: Int] = [:]
        var duplicates: [ObjectID] = []

        init(_ entries: [DictionaryNode.Entry]) {
            for (position, entry) in entries.enumerated() {
                let id = ObjectID(entry.key.value)
                if index[id] == nil {
                    index[id] = position
                } else if !duplicates.contains(id) {
                    duplicates.append(id)
                }
            }
        }
    }

    var table: ObjectTable {
        if let table = cache.table { return table }
        let table = ObjectTable(objectEntries)
        cache.table = table
        return table
    }

    var parentIndex: ParentIndex {
        if let index = cache.parents { return index }
        let index = ParentIndex(self)
        cache.parents = index
        return index
    }

    var pathIndex: PathIndex {
        if let index = cache.paths { return index }
        let index = PathIndex(self, parents: parentIndex)
        cache.paths = index
        return index
    }

    var membershipIndex: MembershipIndex {
        if let index = cache.membership { return index }
        let index = MembershipIndex(self)
        cache.membership = index
        return index
    }

    var sections: SectionMap {
        if let sections = cache.sections { return sections }
        let sections = SectionMap(tree)
        cache.sections = sections
        return sections
    }
}
