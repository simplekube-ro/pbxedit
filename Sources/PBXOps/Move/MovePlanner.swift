import PBXSyntax
import PBXModel

/// `pbxedit move`: the project catches up with a file or directory that has
/// already moved on disk, keeping every object's identity (design D1). Per
/// file: the destination group (add's resolution), the reference's spelling
/// (add's rule), its parents, its membership against the destination's
/// conventions, and finally remove's pruning over the whole plan. It reads
/// the project and, for the preconditions of design D4 only, the disk.
public enum MovePlanner {
    /// One file to move, source-root-relative and normalized.
    struct FileMove: Equatable {
        let from: String
        let to: String
        let reference: FileReference
    }

    /// `from` and `to` are source-root-relative and normalized (see
    /// `PathArgument`). Throws `PlanError` when the move cannot be planned;
    /// then nothing is planned for any file.
    public static func plan(from: String, to: String, in project: Project, conventions: Conventions, keepMembership: Bool = false,
                            disk: any DiskReader, exemptions: Exemptions? = nil, minter: IDMinter = IDMinter()) throws -> Plan {
        var builder = PlanBuilder(project: project, minter: minter)
        let (moves, isDirectory) = try resolveMoves(from: from, to: to, in: project)
        for move in moves { try validate(move, in: project) }
        try checkDisk(moves, disk: disk)
        var removedChildren: [ObjectID: [ObjectID]] = [:]
        var emptied: [(group: ObjectID, path: String)] = []
        for move in moves {
            try plan(move, conventions: conventions, keepMembership: keepMembership, exemptions: exemptions, builder: &builder,
                     removedChildren: &removedChildren, emptied: &emptied)
        }
        RemovePlanner.prune(emptied, removedChildren: removedChildren, builder: &builder)
        if isDirectory { noteExtraFiles(under: to, moves: moves, disk: disk, builder: &builder) }
        return builder.build()
    }

    /// The files `from` names (design D5): the one reference resolving to
    /// it, or — when none does and some resolve beneath it — every member
    /// under the directory, mapped by prefix, in object order.
    static func resolveMoves(from: String, to: String, in project: Project) throws -> (moves: [FileMove], isDirectory: Bool) {
        if let reference = project.fileReferences(at: from).first {
            return ([FileMove(from: from, to: to, reference: reference)], false)
        }
        let prefix = from + "/"
        for group in project.synchronizedRootGroups {
            guard case .relative(let folder)? = project.resolvedPath(of: group.id), folder == from || folder.hasPrefix(prefix) else { continue }
            throw PlanError.synchronizedBeneath(from: from, group: group.id, folder: folder)
        }
        var members: [FileMove] = []
        for reference in project.fileReferences {
            guard case .relative(let path)? = project.resolvedPath(of: reference.id), path.hasPrefix(prefix) else { continue }
            members.append(FileMove(from: path, to: to + "/" + path.dropFirst(prefix.count), reference: reference))
        }
        if !members.isEmpty { return (members, true) }
        if let synchronized = project.synchronizedRootGroup(covering: from) {
            let folder = project.resolvedPath(of: synchronized.id)?.description ?? synchronized.path ?? ""
            throw PlanError.synchronizedSource(from: from, to: to, group: synchronized.id, folder: folder)
        }
        throw PlanError.notInProject(path: from)
    }

    /// Design D5: files directly inside the destination directories the
    /// members land in, which no member accounts for, counted in one note.
    private static func noteExtraFiles(under to: String, moves: [FileMove], disk: any DiskReader, builder: inout PlanBuilder) {
        var expected: [String: Set<String>] = [:]
        for move in moves {
            expected[SiblingInference.directory(of: move.to), default: []].insert(PlanBuilder.basename(of: move.to))
        }
        var extras: [String] = []
        for (directory, names) in expected {
            for name in disk.files(in: directory) where !names.contains(name) {
                extras.append(directory == to ? name : String(directory.dropFirst(to.count + 1)) + "/" + name)
            }
        }
        guard !extras.isEmpty else { return }
        extras.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let count = extras.count == 1 ? "1 file on disk under \(to) is" : "\(extras.count) files on disk under \(to) are"
        let pronoun = extras.count == 1 ? "it" : "them"
        builder.note("\(to): \(count) not in the project: \(extras.joined(separator: ", ")); pbxedit add registers \(pronoun)")
    }

    /// The project-side checks: the reference is not a localized variant or a
    /// model version, and nothing resolves to the destination yet.
    private static func validate(_ move: FileMove, in project: Project) throws {
        for parent in project.parents(of: move.reference.id) where parent.isa != Kind.group {
            throw PlanError.unsupportedContainer(path: move.from, group: parent.id, isa: parent.isa)
        }
        if let taken = project.fileReferences(at: move.to).first {
            throw PlanError.destinationTaken(to: move.to, reference: taken.id)
        }
    }

    /// Design D4: two questions per file, and nothing else is read from the disk.
    private static func checkDisk(_ moves: [FileMove], disk: any DiskReader) throws {
        for move in moves {
            let destinationExists = disk.exists(move.to)
            let sourceExists = disk.exists(move.from)
            switch (sourceExists, destinationExists) {
            case (true, false): throw PlanError.notMovedOnDisk(from: move.from, to: move.to)
            case (false, false): throw PlanError.destinationMissing(from: move.from, to: move.to)
            case (true, true): throw PlanError.looksLikeACopy(from: move.from, to: move.to)
            case (false, true): continue
            }
        }
    }

    // MARK: One file

    private static func plan(_ move: FileMove, conventions: Conventions, keepMembership: Bool, exemptions: Exemptions?,
                             builder: inout PlanBuilder, removedChildren: inout [ObjectID: [ObjectID]],
                             emptied: inout [(group: ObjectID, path: String)]) throws {
        let project = builder.project
        let (from, to, reference) = (move.from, move.to, move.reference)
        builder.move(Plan.Move(from: from, to: to))
        let parents = project.parents(of: reference.id)
        let membership = project.membership(of: reference.id)

        // Design D6: the folder builds it now; the explicit entries go, as remove takes them.
        if let synchronized = project.synchronizedRootGroup(covering: to) {
            let folder = project.resolvedPath(of: synchronized.id)?.description ?? synchronized.path ?? ""
            builder.record(Change(path: to, action: .synchronized, object: synchronized.id,
                                  detail: "membership now comes from synchronized group \(folder) (\(synchronized.id))"))
            RemovePlanner.removeEverything(to, reference: reference, parents: parents, membership: membership, describedAs: from,
                                           builder: &builder, removedChildren: &removedChildren, emptied: &emptied)
            return
        }
        builder.record(Change(path: to, action: .reusedFileReference, object: reference.id, detail: "file reference \(from)"))

        // Step 1: the destination group, and with it the spelling.
        let spelling: ReferenceSpelling
        let destination: ObjectID?
        if let glob = exemptions?.match(.M3, path: to) {
            spelling = ReferenceSpelling(path: to, name: PlanBuilder.basename(of: to), sourceTree: Kind.sourceRootSourceTree)
            destination = nil
            builder.decide(Decision(
                path: to, attribute: "location", value: "path = \(to); sourceTree = \(Kind.sourceRootSourceTree); in no group",
                source: .exemption(rule: .M3, glob: glob.pattern)))
        } else {
            let location = try builder.group(forDirectory: SiblingInference.directory(of: to), path: to)
            spelling = builder.reference(for: to, in: location)
            destination = location.group
            builder.decide(Decision(
                path: to, attribute: "location",
                value: "path = \(spelling.path); sourceTree = \(spelling.sourceTree); in group \(builder.describe(location.group))",
                source: .structure))
        }

        // Step 2: only the attributes whose value changes. `setAttribute`
        // refreshes the comments naming the file (model D6), so this goes
        // before the group child is written.
        if FileTypes.type(of: from) != FileTypes.type(of: to), let type = FileTypes.type(of: to), reference.explicitFileType == nil {
            set("lastKnownFileType", of: reference.id, from: reference.lastKnownFileType, to: type.lastKnownFileType, path: to, builder: &builder)
        }
        set("name", of: reference.id, from: reference.name, to: spelling.name, path: to, builder: &builder)
        set("path", of: reference.id, from: reference.path, to: spelling.path, path: to, builder: &builder)
        set("sourceTree", of: reference.id, from: reference.sourceTree, to: spelling.sourceTree, path: to, builder: &builder)

        // Step 3: parents.
        for parent in parents where parent.id != destination {
            builder.add(.removeChild(reference.id, from: parent.id), touching: [parent.id])
            builder.record(Change(path: to, action: .removedChild, object: parent.id, detail: "child of group \(builder.describe(parent.id))"))
            removedChildren[parent.id, default: []].append(reference.id)
            emptied.append((parent.id, to))
        }
        if let destination, !parents.contains(where: { $0.id == destination }) {
            builder.addChild(reference.id, named: spelling.name ?? spelling.path, to: destination)
            builder.record(Change(path: to, action: .addedChild, object: destination, detail: "child of group \(builder.describe(destination))"))
        }

        // Step 4: membership against the destination's conventions.
        try planMembership(to, reference: reference, membership: membership, conventions: conventions, keepMembership: keepMembership,
                           builder: &builder)
    }

    /// `setAttribute` when `from` and `to` differ, with a change line that
    /// names both values.
    private static func set(_ key: String, of id: ObjectID, from old: String?, to new: String?, path: String, builder: inout PlanBuilder) {
        guard old != new else { return }
        builder.add(.setAttribute(key: key, of: id, to: new.map { .string($0) }), touching: [id])
        let detail: String
        switch (old, new) {
        case (let old?, let new?): detail = "\(key) = \(new) (was \(old))"
        case (let old?, nil): detail = "\(key) removed (was \(old))"
        case (nil, let new?): detail = "\(key) = \(new) (was absent)"
        case (nil, nil): return
        }
        builder.record(Change(path: path, action: .setAttribute, object: id, detail: detail))
    }

    // MARK: Membership

    /// Design D1 step 4. `current` is what the model says; `desired` is what
    /// `Conventions` says for `to` unless membership is kept.
    private static func planMembership(_ to: String, reference: FileReference, membership: Membership, conventions: Conventions,
                                       keepMembership: Bool, builder: inout PlanBuilder) throws {
        let project = builder.project
        let current = Conventions.byName(membership.targets)
        func reuse(_ target: Target) {
            let name = target.name ?? target.id.rawValue
            for entry in membership.buildFiles where entry.phases.contains(where: { $0.targets.contains { $0.id == target.id } }) {
                builder.record(Change(path: to, action: .reusedBuildFile, object: entry.buildFile.id, detail: "build file in \(name)"))
            }
        }
        // A file nothing builds and nothing would build has no membership to follow.
        guard let kind = kind(of: to, membership: membership), let phaseIsa = conventions.phase(for: to, kind: kind).value.isa else {
            for target in current { reuse(target) }
            return
        }
        let names = { (targets: [Target]) in targets.map { $0.name ?? $0.id.rawValue }.joined(separator: ", ") }

        if keepMembership {
            for target in current { reuse(target) }
            builder.decide(Decision(path: to, attribute: "targets", value: current.isEmpty ? "none" : names(current), source: .flag))
            // Design D2: consulted for the note, never to decide; an inference error is no error here.
            if let choice = try? conventions.targets(for: to, kind: kind, in: project),
               Set(choice.targets.map(\.id)) != Set(current.map(\.id)), case .inferred(let siblings, let directory) = choice.source {
                let count = siblings == 1 ? "the 1 sibling" : "the \(siblings) siblings"
                let verb = siblings == 1 ? "belongs" : "belong"
                builder.note("\(to): membership kept (--keep-membership); \(count) in \(directory) \(verb) to \(names(choice.targets))")
            }
            return
        }

        let choice: Conventions.TargetChoice
        do {
            choice = try conventions.targets(for: to, kind: kind, in: project)
        } catch let error as PlanError {
            throw MovePlanner.orKeepMembership(error)
        }
        builder.decide(Decision(path: to, attribute: "targets", value: names(choice.targets), source: choice.source))
        for extra in choice.extras {
            let name = extra.target.name ?? extra.target.id.rawValue
            let all = (choice.targets + [extra.target]).map { "--target \($0.name ?? $0.id.rawValue)" }.joined(separator: " ")
            let directory: String
            if case .inferred(_, let inferredFrom) = choice.source { directory = inferredFrom } else { directory = SiblingInference.directory(of: to) }
            let verb = extra.count == 1 ? "is also a member" : "are also members"
            builder.note("\(to): \(extra.count) of \(extra.of) siblings in \(directory) \(verb) of \(name); pass \(all) to join it too")
        }
        let desired = choice.targets
        let retained = current.filter { target in desired.contains { $0.id == target.id } }
        let detached = current.filter { target in !desired.contains { $0.id == target.id } }
        let attached = desired.filter { target in !current.contains { $0.id == target.id } }

        for target in retained {
            reuse(target)
            let filters = try platformFilters(for: to, kind: kind, target: target, conventions: conventions, in: project)
            var decided = false
            for entry in membership.buildFiles where entry.phases.contains(where: { $0.targets.contains { $0.id == target.id } }) {
                let existing = entry.platformFilters ?? entry.platformFilter.map { [$0] } ?? []
                guard existing != filters.value else { continue }
                if !decided {
                    builder.decide(Decision(path: to, attribute: "platformFilters", value: "\(target.name ?? target.id.rawValue): \(describe(filters.value))",
                                            source: filters.source))
                    decided = true
                }
                let value: NewValue? = filters.value.isEmpty ? nil : .array(filters.value.map { .string($0) })
                builder.add(.setAttribute(key: "platformFilters", of: entry.buildFile.id, to: value), touching: [entry.buildFile.id])
                if entry.buildFile.platformFilter != nil {
                    builder.add(.setAttribute(key: "platformFilter", of: entry.buildFile.id, to: nil), touching: [entry.buildFile.id])
                }
                let detail = filters.value.isEmpty ? "platformFilters removed (was \(describe(existing)))"
                    : "platformFilters = \(describe(filters.value)) (was \(describe(existing)))"
                builder.record(Change(path: to, action: .setAttribute, object: entry.buildFile.id, detail: detail))
            }
        }
        for target in detached {
            RemovePlanner.detach(to, membership: membership, from: target, builder: &builder)
        }
        for target in attached {
            let targetName = target.name ?? target.id.rawValue
            guard let targetPhase = target.buildPhases.compactMap(project.buildPhase).first(where: { $0.isa == phaseIsa }) else {
                throw PlanError.noSuchPhase(path: to, target: targetName, phase: PhaseChoice(kind: kind).displayName)
            }
            let filters = try platformFilters(for: to, kind: kind, target: target, conventions: conventions, in: project)
            builder.decide(Decision(path: to, attribute: "platformFilters", value: "\(targetName): \(describe(filters.value))", source: filters.source))
            let buildFile = builder.mint()
            builder.add(.createBuildFile(id: buildFile, fileRef: reference.id, platformFilters: filters.value), touching: [buildFile])
            builder.record(Change(path: to, action: .createdBuildFile, object: buildFile, detail: "build file for \(targetName)"))
            builder.add(.addPhaseEntry(buildFile, to: targetPhase.id, position: .last), touching: [buildFile, targetPhase.id, target.id])
            builder.record(Change(path: to, action: .addedPhaseEntry, object: targetPhase.id,
                                  detail: "entry in \(targetPhase.displayName) of \(targetName) (\(targetPhase.id))"))
        }
    }

    private static func platformFilters(for to: String, kind: FileKind, target: Target, conventions: Conventions,
                                        in project: Project) throws -> Decided<[String]> {
        do {
            return try conventions.platformFilters(for: to, kind: kind, target: target, in: project)
        } catch let error as PlanError {
            throw orKeepMembership(error)
        }
    }

    /// Design D3: an inference question at the destination has one more answer than in `add`.
    static func orKeepMembership(_ error: PlanError) -> PlanError {
        switch error {
        case .noSiblings, .noCommonTarget, .ambiguousPlatformFilters: return .orKeepMembership(error)
        default: return error
        }
    }

    private static func describe(_ filters: [String]) -> String {
        filters.isEmpty ? "none" : filters.joined(separator: ", ")
    }

    /// The file's kind: from its extension, else from the phase its build
    /// files are in; `nil` when neither says (nothing is built, nothing to follow).
    static func kind(of path: String, membership: Membership) -> FileKind? {
        if let type = FileTypes.type(of: path) { return type.kind }
        for entry in membership.buildFiles {
            for listing in entry.phases {
                if let choice = PhaseChoice.allCases.first(where: { $0.isa == listing.phase.isa }) { return choice.kind }
            }
        }
        return nil
    }
}
