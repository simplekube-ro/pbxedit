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

    public mutating func planGroup(_ group: PlannedGroup, for directory: String) {
        plannedGroups[directory] = group
    }

    public func build() -> Plan { plan }
}
