import PBXModel

/// What a fixer did with one finding (integrity-repair design D1).
enum FixOutcome: Equatable {
    /// Steps were added to the builder; the finding will be gone.
    case planned
    /// Nothing was planned; `reason` is what the report prints.
    case notFixable(reason: String)
}

/// A repair for one rule: a function from a finding to steps, or to the
/// reason there are none. Fixers only read the project; the runner applies
/// the plan and the whole-project check judges it (design D5).
protocol Fixer: Sendable {
    var rule: RuleID { get }
    func plan(_ finding: Finding, conventions: Conventions, builder: inout PlanBuilder) -> FixOutcome
}

/// A finding of a fixable rule that was left alone, and why.
public struct Unrepaired: Equatable, Sendable {
    public let finding: Finding
    public let reason: String

    public init(finding: Finding, reason: String) {
        self.finding = finding
        self.reason = reason
    }
}

/// The plan of `lint --fix`: the steps, the findings they repair, in the
/// order they were planned, and the fixable-rule findings they do not.
public struct RepairPlan: Equatable, Sendable {
    public let plan: Plan
    public let repaired: [Finding]
    public let notFixable: [Unrepaired]

    public init(plan: Plan, repaired: [Finding], notFixable: [Unrepaired]) {
        self.plan = plan
        self.repaired = repaired
        self.notFixable = notFixable
    }

    /// The `path` the plan's changes, decisions and notes are keyed by for a
    /// finding — `M3 AB12` — the way `add` keys them by path argument.
    public static func key(for finding: Finding) -> String {
        "\(finding.rule.rawValue) \(finding.object?.rawValue ?? finding.path ?? "")"
    }

    public func changes(for finding: Finding) -> [Change] {
        let key = RepairPlan.key(for: finding)
        return plan.changes.filter { $0.path == key }
    }

    public func decisions(for finding: Finding) -> [Decision] {
        let key = RepairPlan.key(for: finding)
        return plan.decisions.filter { $0.path == key }
    }

    public func notes(for finding: Finding) -> [String] {
        let prefix = RepairPlan.key(for: finding) + ": "
        return plan.notes.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
}

/// `pbxedit lint --fix`: one plan over every fixable finding (design D1),
/// M2 first, then M1, then M3, each rule's findings in `RuleSet.ordered`
/// order so that two runs plan identical steps (design D2). It only reads
/// the project; `OperationRunner` applies and verifies the plan.
public enum RepairPlanner {
    /// The rules with a fixer, in the order their findings are processed.
    public static let fixableRules: [RuleID] = [.M2, .M1, .M3]

    private static let fixers: [any Fixer] = [M2Fixer(), M1Fixer(), M3Fixer()]

    /// `findings` are what `lint` reports for `project`; a finding
    /// `exemptions` covers is dropped here too, so an exempt path is never
    /// repaired whatever the caller passed (spec: Exemptions and baselines).
    public static func plan(_ findings: [Finding], in project: Project, conventions: Conventions = Conventions(),
                            exemptions: Exemptions? = nil, minter: IDMinter = IDMinter()) -> RepairPlan {
        var builder = PlanBuilder(project: project, minter: minter)
        var repaired: [Finding] = []
        var notFixable: [Unrepaired] = []
        let candidates = exemptions.map { $0.apply(to: findings).kept } ?? findings
        for fixer in fixers {
            for finding in RuleSet.ordered(candidates.filter { $0.rule == fixer.rule }) {
                switch fixer.plan(finding, conventions: conventions, builder: &builder) {
                case .planned:
                    repaired.append(finding)
                case .notFixable(let reason):
                    notFixable.append(Unrepaired(finding: finding, reason: reason))
                }
            }
        }
        return RepairPlan(plan: builder.build(), repaired: repaired, notFixable: notFixable)
    }
}

extension Project {
    /// `Sources of App (CC…)`, or `Sources (CC…)` for a phase no target owns.
    func describePhase(_ phase: BuildPhase) -> String {
        let owners = targets(owning: phase.id).map { $0.name ?? $0.id.rawValue }
        return owners.isEmpty ? "\(phase.displayName) (\(phase.id))" : "\(phase.displayName) of \(owners.joined(separator: ", ")) (\(phase.id))"
    }
}
