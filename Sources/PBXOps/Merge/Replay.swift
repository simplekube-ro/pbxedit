import PBXSyntax
import PBXModel

/// The transition planner (merge design D5): a unit's membership taken from
/// what the file holds to what theirs holds, through `add`'s, `remove`'s and
/// `move`'s planners and `move`'s filter rewrite only, each plan made
/// against the project the previous one produced. It never infers: every
/// `add` names its target, platforms and phase.
public enum Replay {
    public struct Outcome {
        public let project: Project
        /// In the order they were applied; empty when nothing changes.
        public let plans: [Plan]

        /// Every object any plan touched, for the scoped check and the report.
        public var touched: Set<ObjectID> { plans.reduce(into: []) { $0.formUnion($1.touched) } }

        public var changes: [Change] { plans.flatMap(\.changes) }
    }

    /// Replays `paths` (one unit) onto `current`. Throws the planner's
    /// `PlanError` (or a `PlanExecutionError`) when a step cannot be made.
    /// Groups in `keeping` (`Neutralise.keptGroups`) are never pruned: theirs
    /// holds them, so the result does too.
    public static func run(paths: [String], current: Project, theirs: MembershipSnapshot, exemptions: Exemptions? = nil,
                           minter: IDMinter = IDMinter(), removeAll: Bool = false, keeping: Set<ObjectID> = []) throws -> Outcome {
        var project = current
        var plans: [Plan] = []
        var snapshot = MembershipSnapshot(project)
        func apply(_ plan: Plan) throws {
            guard !plan.isNoOp else { return }
            project = try plan.apply(to: project)
            plans.append(plan)
            snapshot = MembershipSnapshot(project)
        }
        func add(_ path: String, _ flags: Conventions.Flags) throws {
            try apply(AddPlanner.plan([path], in: project, conventions: Conventions(flags: flags), exemptions: exemptions, minter: minter,
                                      perPhase: true))
        }
        let unit = Set(paths)

        // The `replayRemoveAll` fault: what the downstream's first revision did.
        if removeAll {
            for path in paths where snapshot.references[path] != nil {
                try apply(RemovePlanner.plan([path], in: project, all: true, keeping: keeping))
            }
        }

        // 1. Moves: theirs holds an ID here that the file holds at another path of the unit.
        for path in paths {
            guard let wanted = theirs.references[path], snapshot.references[path] == nil,
                  let held = snapshot.byID[wanted.id], held.resolvedPath != path, unit.contains(held.resolvedPath)
            else { continue }
            try apply(MovePlanner.plan(from: held.resolvedPath, to: path, in: project, conventions: Conventions(), keepMembership: true,
                                       disk: ReplayDisk(destination: path), exemptions: exemptions, minter: minter, keeping: keeping))
        }

        // 2. Removals: paths the file holds and theirs does not.
        for path in paths where snapshot.references[path] != nil && theirs.references[path] == nil {
            try apply(RemovePlanner.plan([path], in: project, all: true, keeping: keeping))
        }

        // 3. References: paths theirs holds and the file does not; reference and group child only.
        for path in paths where theirs.references[path] != nil && snapshot.references[path] == nil {
            try add(path, Conventions.Flags(phase: .notBuilt))
        }

        // 4. Rows, per path, per target.
        for path in paths {
            guard let wanted = theirs.references[path] else { continue }
            let targets = Set(wanted.rows.map(\.target)).union(snapshot.references[path]?.rows.map(\.target) ?? [])
            for target in targets.sorted() {
                let have = (snapshot.references[path]?.rows ?? []).filter { $0.target == target }
                let want = wanted.rows.filter { $0.target == target }
                // `settings` has no verb: it is compared by the trial, never written.
                // Compared as sorted lists: row order follows build-file IDs, which differ between versions.
                let sortedWritable = { (rows: [MembershipSnapshot.Row]) in rows.map(Replay.writable).sorted { $0.lexicographicallyPrecedes($1) } }
                guard sortedWritable(have) != sortedWritable(want) else { continue }
                if want.isEmpty {
                    try apply(RemovePlanner.plan([path], in: project, target: target))
                    continue
                }
                // Matched by phase kind: a row in both keeps its build file (filters rewritten
                // in place), one only `current` has is detached, one only theirs has is attached.
                // Two rows of one kind in a target (two Sources phases) cannot be matched: every
                // row goes and theirs' are attached, and the trial names what that loses.
                let kinds = { (rows: [MembershipSnapshot.Row]) in rows.map(\.phase) }
                guard Set(kinds(have)).count == have.count, Set(kinds(want)).count == want.count else {
                    if !have.isEmpty { try apply(RemovePlanner.plan([path], in: project, target: target)) }
                    for row in want { try add(path, Conventions.Flags(targets: [target], platformFilters: row.filters, phase: row.phase)) }
                    continue
                }
                for kind in Set(kinds(have) + kinds(want)).sorted(by: { $0.rawValue < $1.rawValue }) {
                    let had = have.first { $0.phase == kind }
                    let wanted = want.first { $0.phase == kind }
                    if let had, let wanted {
                        guard had.filters != wanted.filters, let buildFile = project.buildFile(had.buildFile) else { continue }
                        var builder = PlanBuilder(project: project, minter: minter)
                        builder.rewriteFilters(of: buildFile, to: wanted.filters, path: path)
                        try apply(builder.build())
                    } else if had != nil {
                        try apply(RemovePlanner.plan(path, in: project, target: target, phase: kind))
                    } else if let wanted {
                        try add(path, Conventions.Flags(targets: [target], platformFilters: wanted.filters, phase: kind))
                    }
                }
            }
        }
        return Outcome(project: project, plans: plans)
    }

    /// What a replay can write of a row: its phase kind and its filters.
    static func writable(_ row: MembershipSnapshot.Row) -> [String] { [row.phase.rawValue] + row.filters }
}

/// The disk `move` asks during a replay (merge design D5): the file is at
/// its destination and nowhere else, and no directory lists anything.
struct ReplayDisk: DiskReader {
    let destination: String

    func exists(_ path: String) -> Bool { path == destination }

    func files(in path: String) -> [String] { [] }
}

/// What a replay could not reproduce of theirs at one path (merge design
/// D4): pbxedit has no verb that writes it.
public struct Residual: Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Hashable, Sendable, CustomStringConvertible {
        /// A build file's `settings` in the target's row.
        case settings(target: String)
        /// The group the reference is a child of.
        case parentGroup
        /// `path`, `name` or `sourceTree` of the reference.
        case spelling(String)
        /// Any other attribute of the reference.
        case attribute(String)
        /// Any other attribute of the build file in the target's row.
        case buildFileAttribute(target: String, key: String)
        /// The rows themselves: phase kinds or filters the replay could not write.
        case rows
        /// Whether a reference resolves to the path at all.
        case presence

        public var description: String {
            switch self {
            case .settings(let target): return "settings of the build file in \(target)"
            case .parentGroup: return "parent group"
            case .spelling(let key): return key
            case .attribute(let key): return key
            case .buildFileAttribute(let target, let key): return "\(key) of the build file in \(target)"
            case .rows: return "rows"
            case .presence: return "file reference"
            }
        }
    }

    public let path: String
    public let kind: Kind
    /// The object the difference is on in the replayed project, when it exists there.
    public let object: ObjectID?
    /// The object whose value was expected: theirs', or ours' for an
    /// attribute only ours changed.
    public var source: ObjectID? = nil
    /// What theirs has, and what the replay produced; `nil` for absent.
    public let theirs: String?
    public let merged: String?

    public var description: String {
        let subject = object.map { "\(path) (\($0))" } ?? path
        return "\(subject): \(kind) is \(merged ?? "absent"), theirs \(theirs ?? "absent")"
    }
}

/// The trial of merge design D4: the unit's transition applied to ours in
/// memory and compared with theirs.
public enum Trial {
    public enum Result: Equatable, Sendable {
        /// The replay ran; these are what it could not reproduce.
        case replayed([Residual])
        /// A planner refused; the message says why.
        case failed(String)
    }

    /// `oursSnapshot`, when given, is `MembershipSnapshot(ours)`: a caller
    /// trying many units passes it once rather than having it rebuilt per unit.
    public static func run(paths: [String], base: MembershipSnapshot, ours: Project, oursSnapshot: MembershipSnapshot? = nil,
                           theirs: MembershipSnapshot, exemptions: Exemptions? = nil, minter: IDMinter = IDMinter(),
                           removeAll: Bool = false) -> Result {
        let outcome: Replay.Outcome
        do {
            outcome = try Replay.run(paths: paths, current: ours, theirs: theirs, exemptions: exemptions, minter: minter, removeAll: removeAll)
        } catch {
            return .failed("\(error)")
        }
        return .replayed(PathComparison.compare(paths: paths, base: base, ours: oursSnapshot ?? MembershipSnapshot(ours), theirs: theirs,
                                                result: MembershipSnapshot(outcome.project)))
    }
}

/// The per-path comparison of merge design D9 E, shared by the trial and
/// check E: spelling, parent group and rows equal theirs'; every other
/// attribute of the reference and its build files equals theirs' where
/// only theirs changed it and ours' where only ours did.
public enum PathComparison {
    public static func compare(paths: [String], base: MembershipSnapshot, ours: MembershipSnapshot, theirs: MembershipSnapshot,
                               result: MembershipSnapshot) -> [Residual] {
        var residuals: [Residual] = []
        for path in paths {
            let merged = result.references[path]
            guard let wanted = theirs.references[path] else {
                if let merged {
                    residuals.append(Residual(path: path, kind: .presence, object: merged.id, theirs: nil, merged: merged.id.rawValue))
                }
                continue
            }
            guard let merged else {
                residuals.append(Residual(path: path, kind: .presence, object: nil, theirs: wanted.id.rawValue, merged: nil))
                continue
            }
            func differ(_ kind: Residual.Kind, _ theirsValue: String?, _ mergedValue: String?, object: ObjectID? = merged.id,
                        source: ObjectID? = wanted.id) {
                guard theirsValue != mergedValue else { return }
                residuals.append(Residual(path: path, kind: kind, object: object, source: source, theirs: theirsValue, merged: mergedValue))
            }
            differ(.spelling("path"), wanted.path, merged.path)
            differ(.spelling("name"), wanted.name, merged.name)
            differ(.spelling("sourceTree"), wanted.sourceTree, merged.sourceTree)
            differ(.parentGroup, wanted.groupPaths.joined(separator: ", "), merged.groupPaths.joined(separator: ", "))

            // Counterparts in base and ours: by the ID theirs kept, else by path.
            let before = base.byID[wanted.id] ?? base.references[path]
            let held = before.flatMap { ours.byID[$0.id] } ?? ours.references[path]
            let referenceKeys = [wanted.attributes, merged.attributes, before?.attributes ?? [:], held?.attributes ?? [:]].flatMap(\.keys)
            for key in Set(referenceKeys).sorted() {
                // Where ours holds no counterpart, ours changed nothing about it: theirs' value stands.
                let expected = held == nil ? wanted.attributes[key]
                    : expectation(base: before?.attributes[key], ours: held?.attributes[key], theirs: wanted.attributes[key],
                                  merged: merged.attributes[key])
                let fromTheirs = held == nil || wanted.attributes[key] != before?.attributes[key]
                differ(.attribute(key), expected?.description, merged.attributes[key]?.description,
                       source: fromTheirs ? wanted.id : held?.id ?? wanted.id)
            }

            // Rows: what the replay writes, then what it cannot.
            let writable = { (rows: [MembershipSnapshot.Row]) in rows.map { Replay.writable($0) + [$0.target] }.sorted { $0.lexicographicallyPrecedes($1) } }
            if writable(wanted.rows) != writable(merged.rows) {
                differ(.rows, wanted.masked.rows.map(\.description).joined(separator: "; "),
                       merged.masked.rows.map(\.description).joined(separator: "; "))
            }
            for target in Set(wanted.rows.map(\.target)).sorted() {
                guard let want = wanted.rows.first(where: { $0.target == target }),
                      let have = merged.rows.first(where: { $0.target == target })
                else { continue }
                differ(.settings(target: target), want.settings?.description, have.settings?.description, object: have.buildFile)
                let was = before?.rows.first { $0.target == target }
                let ourRow = held?.rows.first { $0.target == target }
                let rowKeys = [want.attributes, have.attributes, was?.attributes ?? [:], ourRow?.attributes ?? [:]].flatMap(\.keys)
                for key in Set(rowKeys).sorted() {
                    let expected = ourRow == nil ? want.attributes[key]
                        : expectation(base: was?.attributes[key], ours: ourRow?.attributes[key], theirs: want.attributes[key],
                                      merged: have.attributes[key])
                    differ(.buildFileAttribute(target: target, key: key), expected?.description, have.attributes[key]?.description,
                           object: have.buildFile)
                }
            }
        }
        return residuals
    }

    /// Theirs' value where theirs changed it, else ours'. Where both changed
    /// it, either side's value is accepted: the one the result has.
    private static func expectation(base: PlistValue?, ours: PlistValue?, theirs: PlistValue?, merged: PlistValue?) -> PlistValue? {
        let theirsChanged = theirs != base
        let oursChanged = ours != base
        if theirsChanged, oursChanged, merged == ours { return ours }
        return theirsChanged ? theirs : ours
    }
}

/// Neutralisation (merge design D6): unit paths leave a version through
/// `remove`'s planner, so the text merge never sees membership lines.
public enum Neutralise {
    /// Removes every path of `paths` that `project` holds a managed
    /// reference for — never a path only a synchronized folder covers. With
    /// `presenceFilter` off (the `skipPresenceFilter` fault) every path is
    /// removed, and the planner refuses the first one that is absent.
    /// Groups in `keeping` stay however empty the removals leave them.
    public static func run(_ project: Project, paths: [String], presenceFilter: Bool = true, keeping: Set<ObjectID> = []) throws -> Project {
        let snapshot = MembershipSnapshot(project)
        let held = presenceFilter ? paths.filter { snapshot.references[$0] != nil } : paths
        guard !held.isEmpty else { return project }
        return try RemovePlanner.plan(held, in: project, all: true, keeping: keeping).apply(to: project)
    }

    /// The groups neutralising base or theirs would prune that theirs holds
    /// and changed apart from `children` (or added). Pruned, theirs' change
    /// to them would reach the text merge from neither side and be lost;
    /// kept in both copies, it is merged as text like any other. A group
    /// theirs deleted is not kept: its absence then matches base's pruning.
    public static func keptGroups(base: Project, theirs: Project, paths: [String]) -> Set<ObjectID> {
        let pruned = [base, theirs].reduce(into: Set<ObjectID>()) { pruned, project in
            guard let neutral = try? run(project, paths: paths) else { return }
            for group in project.groups where neutral.group(group.id) == nil { pruned.insert(group.id) }
        }
        func withoutChildren(_ object: Object?) -> PlistValue? {
            guard let object, case .dictionary(let entries) = PlistValue(object.value) else { return nil }
            return .dictionary(entries.filter { !$0.key.utf8.elementsEqual("children".utf8) })
        }
        return pruned.filter { id in
            guard let theirsGroup = theirs.object(id) else { return false }
            return withoutChildren(theirsGroup) != withoutChildren(base.object(id))
        }
    }
}
