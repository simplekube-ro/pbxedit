import PBXSyntax
import PBXModel

/// A pure function from a loaded project to findings (design D1). Rules hold
/// no state and do not see each other or the file system.
public protocol Rule: Sendable {
    var id: RuleID { get }
    func evaluate(_ project: Project) -> [Finding]
}

/// A rule that reads the file system through a `DiskReader` (design D5).
/// Only D1 and D2 conform, so no other rule can touch the disk.
public protocol DiskRule: Sendable {
    var id: RuleID { get }
    func evaluate(_ project: Project, disk: any DiskReader) -> [Finding]
}

/// The one rule set that serves `lint` and the pre-write check of every
/// mutating command (`docs/design.md` § Rules).
public struct RuleSet: Sendable {
    public let rules: [any Rule]
    public let diskRules: [any DiskRule]

    public init(rules: [any Rule], diskRules: [any DiskRule]) {
        self.rules = rules
        self.diskRules = diskRules
    }

    /// S2–S5, M1–M6 and, behind a reader, D1–D2. S1 is the loading step of
    /// `evaluate(bytes:)`.
    public static let standard = RuleSet(
        rules: [S2Rule(), S3Rule(), S4Rule(), S5Rule(), M1Rule(), M2Rule(), M3Rule(), M4Rule(), M5Rule(), M6Rule()],
        diskRules: [D1Rule(), D2Rule()]
    )

    /// Parses, checks the round trip, loads, and evaluates. A failure of any
    /// of the three is the single S1 finding (design D1).
    public func evaluate(bytes: [UInt8], scope: Set<ObjectID>? = nil, disk: (any DiskReader)? = nil) -> [Finding] {
        let tree: SyntaxTree
        switch SyntaxTree.parse(bytes) {
        case .success(let parsed):
            tree = parsed
        case .failure(let error):
            return [Finding(rule: .S1, object: nil, message: "the project file does not parse: \(error)")]
        }
        guard tree.serialize() == bytes else {
            return [Finding(rule: .S1, object: nil, message: "the project file does not round-trip byte for byte")]
        }
        let project: Project
        do {
            project = try Project(tree: tree)
        } catch {
            return [Finding(rule: .S1, object: nil, message: "the project file does not load as a project: \(error)")]
        }
        return evaluate(project, scope: scope, disk: disk)
    }

    /// Runs every rule, then the disk rules when `disk` is given, and keeps
    /// the findings whose object or related objects intersect `scope` when
    /// one is given (design D2). Ordered for output.
    public func evaluate(_ project: Project, scope: Set<ObjectID>? = nil, disk: (any DiskReader)? = nil) -> [Finding] {
        var findings: [Finding] = []
        for rule in rules { findings += rule.evaluate(project) }
        if let disk {
            for rule in diskRules { findings += rule.evaluate(project, disk: disk) }
        }
        if let scope {
            findings = findings.filter { finding in
                if let object = finding.object, scope.contains(object) { return true }
                return finding.related.contains { scope.contains($0) }
            }
        }
        return RuleSet.ordered(findings)
    }

    /// Errors before warnings, then rule, object (byte order, `nil` last),
    /// path, message — the same order for the same file every time.
    public static func ordered(_ findings: [Finding]) -> [Finding] {
        findings.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            if lhs.rule != rhs.rule { return lhs.rule < rhs.rule }
            switch (lhs.object, rhs.object) {
            case let (a?, b?) where a != b: return a < b
            case (nil, .some): return false
            case (.some, nil): return true
            default: break
            }
            let (lp, rp) = (lhs.path ?? "", rhs.path ?? "")
            if lp != rp { return lp.utf8.lexicographicallyPrecedes(rp.utf8) }
            return lhs.message.utf8.lexicographicallyPrecedes(rhs.message.utf8)
        }
    }
}
