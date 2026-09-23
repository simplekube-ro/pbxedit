import PBXModel

/// Accumulates a plan while a planner decides (design D1): steps with their
/// change lines, decisions, notes, the touched set, and the groups the plan
/// will create by directory, so that a later question "is there a group for
/// this directory" sees them too.
public struct PlanBuilder {
    /// A group the plan creates, before it exists in any model.
    public struct PlannedGroup: Equatable {
        public let id: ObjectID
        /// Whether a `<group>`-relative child resolves through it to the
        /// directory it stands for (design D5).
        public let resolvesToDirectory: Bool
    }

    public let project: Project
    private var minter: IDMinter
    public private(set) var plan = Plan()
    public private(set) var plannedGroups: [String: PlannedGroup] = [:]
    /// Every child this plan adds to a group, by group, so that pruning can
    /// tell a group emptied by the plan from one the plan refills.
    public internal(set) var addedChildren: [ObjectID: [ObjectID]] = [:]
    /// The children of every group this plan has looked at or added to,
    /// existing and planned, in the order they will have after the plan.
    var knownChildren: [ObjectID: [(id: ObjectID, name: String)]] = [:]

    public init(project: Project, minter: IDMinter = IDMinter()) {
        self.project = project
        self.minter = minter
    }

    /// A fresh ID: in neither the project nor this plan.
    public mutating func mint() -> ObjectID { minter.mint(for: project) }

    public mutating func add(_ step: Step, touching ids: [ObjectID] = []) {
        plan.steps.append(step)
        for id in ids { plan.touched.insert(id) }
    }

    public mutating func record(_ change: Change) {
        plan.changes.append(change)
        plan.touched.insert(change.object)
    }

    public mutating func touch(_ id: ObjectID) { plan.touched.insert(id) }

    public mutating func decide(_ decision: Decision) { plan.decisions.append(decision) }

    public mutating func note(_ text: String) { plan.notes.append(text) }

    public mutating func move(_ move: Plan.Move) { plan.moves.append(move) }

    public mutating func planGroup(_ group: PlannedGroup, for directory: String) {
        plannedGroups[directory] = group
    }

    public func build() -> Plan { plan }
}

extension PlanBuilder {
    /// Rewrites a kept build file's filters in place, in the spelling Xcode
    /// writes (platform-filters design D2): set the new value's key, then
    /// clear whichever of the two keys the build file carries but should
    /// not. Returns whether anything changed. Shared by `move` (a kept
    /// target) and the merge's replay (merge design D5).
    @discardableResult
    public mutating func rewriteFilters(of buildFile: BuildFile, to filters: [String], path: String) -> Bool {
        let existing = PlatformFilters.read(from: buildFile)
        guard existing != filters else { return false }
        let spelling = PlatformFilters.spelling(of: filters)
        if let key = spelling.key, let value = spelling.value {
            add(.setAttribute(key: key, of: buildFile.id, to: value), touching: [buildFile.id])
        }
        for other in [PlatformFilters.singularKey, PlatformFilters.pluralKey]
        where other != spelling.key && buildFile.object.attributes?[other] != nil {
            add(.setAttribute(key: other, of: buildFile.id, to: nil), touching: [buildFile.id])
        }
        let detail = filters.isEmpty ? "platformFilters removed (was \(PlatformFilters.describe(existing)))"
            : "platformFilters = \(PlatformFilters.describe(filters)) (was \(PlatformFilters.describe(existing)))"
        record(Change(path: path, action: .setAttribute, object: buildFile.id, detail: detail))
        return true
    }
}
