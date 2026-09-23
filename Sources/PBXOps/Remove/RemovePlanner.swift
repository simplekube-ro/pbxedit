import PBXSyntax
import PBXModel

/// `pbxedit remove`: every trace of a file leaves the project — build files,
/// phase entries, group children, the reference, and the groups that are
/// left empty — as one plan (design D1). With `target`, only that target's
/// membership goes and the reference stays (design D4). It only reads the
/// project; the runner applies the plan.
public enum RemovePlanner {
    /// `paths` are source-root-relative and normalized (see `PathArgument`).
    /// Throws `PlanError` when a path cannot be removed; then nothing is
    /// planned for any path. A group in `keeping` is never pruned, however
    /// empty it is left (merge design D6).
    public static func plan(_ paths: [String], in project: Project, target: String? = nil, all: Bool = false,
                            keeping: Set<ObjectID> = []) throws -> Plan {
        var builder = PlanBuilder(project: project)
        var removedChildren: [ObjectID: [ObjectID]] = [:]
        var emptiedBy: [(group: ObjectID, path: String)] = []
        for path in paths {
            try plan(path, target: target, all: all, builder: &builder, removedChildren: &removedChildren, emptied: &emptiedBy)
        }
        prune(emptiedBy, removedChildren: removedChildren, keeping: keeping, builder: &builder)
        return builder.build()
    }

    /// The merge's replay only (merge design D5): `remove --target` limited to
    /// the rows of `path` in `target`'s phases of kind `phase`, so one of a
    /// target's two rows (Sources and Resources) can go and the other stay.
    static func plan(_ path: String, in project: Project, target: String, phase: PhaseChoice) throws -> Plan {
        var builder = PlanBuilder(project: project)
        guard let reference = project.fileReferences(at: path).first else { throw PlanError.notInProject(path: path) }
        builder.touch(reference.id)
        try detach(path, reference: reference, membership: project.membership(of: reference.id), from: target, phaseIsa: phase.isa,
                   builder: &builder)
        return builder.build()
    }

    private static func plan(_ path: String, target: String?, all: Bool, builder: inout PlanBuilder,
                             removedChildren: inout [ObjectID: [ObjectID]], emptied: inout [(group: ObjectID, path: String)]) throws {
        let project = builder.project
        guard let reference = project.fileReferences(at: path).first else {
            if let synchronized = project.synchronizedRootGroup(covering: path) {
                let folder = project.resolvedPath(of: synchronized.id)?.description ?? synchronized.path ?? ""
                throw PlanError.synchronizedMembership(path: path, group: synchronized.id, folder: folder)
            }
            throw PlanError.notInProject(path: path)
        }
        let parents = project.parents(of: reference.id)
        for parent in parents where parent.isa != Kind.group {
            throw PlanError.unsupportedContainer(path: path, group: parent.id, isa: parent.isa)
        }
        let membership = project.membership(of: reference.id)
        builder.touch(reference.id)

        if let target {
            try detach(path, reference: reference, membership: membership, from: target, phaseIsa: nil, builder: &builder)
            return
        }

        // Design D3: the guard counts distinct targets, not build files.
        let targets = membership.targets
        if targets.count > 1, !all {
            throw PlanError.sharedFile(path: path, targets: targets.map { $0.name ?? $0.id.rawValue })
        }
        if targets.count > 1 {
            builder.note("\(path): removed from \(targets.map { $0.name ?? $0.id.rawValue }.joined(separator: ", ")) (--all)")
        }

        // Design D1: referrers first — phase entries, build files, group children, the reference.
        removeEverything(path, reference: reference, parents: parents, membership: membership, builder: &builder,
                         removedChildren: &removedChildren, emptied: &emptied)
    }

    /// Design D4: only the named target's listings go; a build file left in
    /// no phase is deleted, one still listed elsewhere is kept, and one that
    /// was in no phase to begin with is not this target's business.
    private static func detach(_ path: String, reference: FileReference, membership: Membership, from targetName: String,
                               phaseIsa: String?, builder: inout PlanBuilder) throws {
        let project = builder.project
        guard let target = project.targets.first(where: { $0.name?.utf8.elementsEqual(targetName.utf8) == true }) else {
            throw PlanError.unknownTarget(name: targetName, available: project.targets.compactMap(\.name).sorted())
        }
        guard membership.targets.contains(where: { $0.id == target.id }) else {
            throw PlanError.notMemberOfTarget(path: path, target: targetName, targets: membership.targets.map { $0.name ?? $0.id.rawValue })
        }
        let remaining = detach(path, membership: membership, from: target, phaseIsa: phaseIsa, builder: &builder)
        for parent in project.parents(of: reference.id) { builder.touch(parent.id) }
        if !remaining {
            builder.note("\(path): now built by no target; the file reference and its group child remain")
        }
    }

    /// The steps of design D4 for one target, shared with `MovePlanner`:
    /// each listing in a phase `target` owns goes, a build file left in no
    /// phase is deleted, one still listed elsewhere is kept. Returns whether
    /// some build file of the reference is still in a phase afterwards.
    /// With `phaseIsa`, only listings in phases of that kind go.
    @discardableResult
    static func detach(_ path: String, membership: Membership, from target: Target, phaseIsa: String? = nil, builder: inout PlanBuilder) -> Bool {
        let targetName = target.name ?? target.id.rawValue
        var remaining = false
        for entry in membership.buildFiles {
            let owned = entry.phases.filter { listing in
                listing.targets.contains { $0.id == target.id } && (phaseIsa == nil || listing.phase.isa == phaseIsa)
            }
            guard !owned.isEmpty else {
                if !entry.phases.isEmpty { remaining = true }
                continue
            }
            for listing in owned {
                removePhaseEntry(entry.buildFile.id, from: listing, path: path, builder: &builder)
            }
            if owned.count == entry.phases.count {
                builder.add(.deleteObject(entry.buildFile.id), touching: [entry.buildFile.id])
                builder.record(Change(path: path, action: .deletedObject, object: entry.buildFile.id, detail: "build file in \(targetName)"))
            } else {
                remaining = true
                builder.touch(entry.buildFile.id)
            }
        }
        return remaining
    }

    /// Design D1's referrers-first removal of one reference, shared with
    /// `MovePlanner` (a move into a synchronized folder). The caller has
    /// already checked the parents' kinds and decided about shared targets.
    static func removeEverything(_ path: String, reference: FileReference, parents: [Group], membership: Membership,
                                 describedAs described: String? = nil, builder: inout PlanBuilder,
                                 removedChildren: inout [ObjectID: [ObjectID]], emptied: inout [(group: ObjectID, path: String)]) {
        for entry in membership.buildFiles {
            for listing in entry.phases {
                removePhaseEntry(entry.buildFile.id, from: listing, path: path, builder: &builder)
            }
            builder.add(.deleteObject(entry.buildFile.id), touching: [entry.buildFile.id])
            builder.record(Change(path: path, action: .deletedObject, object: entry.buildFile.id,
                                  detail: "build file in \(RemovePlanner.owners(of: entry))"))
        }
        for parent in parents {
            builder.add(.removeChild(reference.id, from: parent.id), touching: [parent.id])
            builder.record(Change(path: path, action: .removedChild, object: parent.id, detail: "child of group \(builder.describe(parent.id))"))
            removedChildren[parent.id, default: []].append(reference.id)
            emptied.append((parent.id, path))
        }
        builder.add(.deleteObject(reference.id), touching: [reference.id])
        builder.record(Change(path: path, action: .deletedObject, object: reference.id, detail: "file reference \(described ?? path)"))
    }

    private static func removePhaseEntry(_ buildFile: ObjectID, from listing: Membership.PhaseEntry, path: String, builder: inout PlanBuilder) {
        let phase = listing.phase
        builder.add(.removePhaseEntry(buildFile, from: phase.id), touching: [buildFile, phase.id] + listing.targets.map(\.id))
        let owners = listing.targets.map { $0.name ?? $0.id.rawValue }
        let where_ = owners.isEmpty ? "\(phase.displayName) (\(phase.id))" : "\(phase.displayName) of \(owners.joined(separator: ", ")) (\(phase.id))"
        builder.record(Change(path: path, action: .removedPhaseEntry, object: phase.id, detail: "entry in \(where_)"))
    }

    /// `App`, `App, AppExtension`, or `no phase` for a build file's change line.
    private static func owners(of entry: Membership.BuildFileEntry) -> String {
        var names: [String] = []
        for listing in entry.phases {
            for target in listing.targets {
                let name = target.name ?? target.id.rawValue
                if !names.contains(name) { names.append(name) }
            }
        }
        if names.isEmpty { return entry.phases.isEmpty ? "no phase" : "no target" }
        return names.joined(separator: ", ")
    }

    /// Design D5: walk up from each group that lost a child; a `PBXGroup`
    /// left with nothing, other than the main group and the products group,
    /// is removed from its parents and deleted, and the walk continues.
    /// The children the same plan gives a group (`builder.addedChildren`: a
    /// move can empty a group and refill it with a new subgroup) count as
    /// remaining. Shared with `MovePlanner`.
    static func prune(_ emptied: [(group: ObjectID, path: String)], removedChildren: [ObjectID: [ObjectID]], keeping: Set<ObjectID> = [],
                      builder: inout PlanBuilder) {
        let addedChildren = builder.addedChildren
        let project = builder.project
        let mainGroup = project.mainGroup?.id
        let productRefGroup = project.rootObject?.id("productRefGroup")
        var removed = removedChildren
        var queue = emptied
        var pruned: Set<ObjectID> = []
        var index = 0
        while index < queue.count {
            let (id, path) = queue[index]
            index += 1
            guard !pruned.contains(id), !keeping.contains(id), id != mainGroup, id != productRefGroup, let group = project.group(id), group.isa == Kind.group else { continue }
            var remaining = group.children
            for child in removed[id] ?? [] {
                if let position = remaining.firstIndex(of: child) { remaining.remove(at: position) }
            }
            remaining += addedChildren[id] ?? []
            guard remaining.isEmpty else { continue }
            pruned.insert(id)
            for parent in project.parents(of: id) {
                builder.add(.removeChild(id, from: parent.id), touching: [parent.id])
                builder.record(Change(path: path, action: .removedChild, object: parent.id, detail: "child of group \(builder.describe(parent.id))"))
                removed[parent.id, default: []].append(id)
                queue.append((parent.id, path))
            }
            builder.add(.deleteObject(id), touching: [id])
            builder.record(Change(path: path, action: .deletedObject, object: id, detail: "group \(builder.describe(id)), left empty"))
        }
    }
}
