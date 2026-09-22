import PBXModel

/// The rules of `docs/design.md` § Rules, in the order findings are reported.
public enum RuleID: String, CaseIterable, Sendable, Hashable, Comparable {
    case S1, S2, S3, S4, S5
    case M1, M2, M3, M4, M5, M6
    case D1, D2

    /// Fixed per rule; there are no severity overrides (design, Non-Goals).
    public var severity: Severity {
        switch self {
        case .S5, .M6, .D1, .D2: return .warning
        default: return .error
        }
    }

    /// What the rule checks, for `--help` and messages.
    public var title: String {
        switch self {
        case .S1: return "the file parses, round-trips and loads"
        case .S2: return "every referenced ID exists"
        case .S3: return "no duplicate IDs or repeated entries"
        case .S4: return "platformFilters is an array of known platform names"
        case .S5: return "strings are quoted canonically"
        case .M1: return "every build file is in exactly one build phase"
        case .M2: return "every build-phase entry points to a build file whose file resolves"
        case .M3: return "every file reference has exactly one parent group"
        case .M4: return "no two file references resolve to the same path"
        case .M5: return "no two build files in one phase share a file"
        case .M6: return "a source is built by the target whose directory it lies in"
        case .D1: return "a file reference's resolved path exists on disk"
        case .D2: return "a source or resource on disk is referenced"
        }
    }

    private var ordinal: Int { RuleID.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: RuleID, rhs: RuleID) -> Bool { lhs.ordinal < rhs.ordinal }
}

public enum Severity: String, Sendable, Hashable, Comparable {
    case error, warning

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs == .error && rhs == .warning }
}

/// A finding's identity for before/after comparison: existing objects keep
/// their IDs through a repair, so the same damage has the same identity on
/// both sides, while messages may name a phase or path that a repair reworded.
public struct FindingIdentity: Hashable, Sendable {
    public let rule: RuleID
    public let object: ObjectID?
    public let related: [ObjectID]

    public init(rule: RuleID, object: ObjectID?, related: [ObjectID]) {
        self.rule = rule
        self.object = object
        self.related = related
    }
}

/// One violation of one rule (spec: Findings are identified and addressable).
public struct Finding: Hashable, Sendable, CustomStringConvertible {
    public let rule: RuleID
    public var severity: Severity { rule.severity }
    /// The offending object. `nil` only for a finding about something no
    /// object names: a D2 file on disk, or an S5 string outside `objects`.
    public let object: ObjectID?
    /// The object's resolved path, or the path the finding is about.
    public let path: String?
    /// The other objects the finding names, for scoped evaluation (design D2).
    public let related: [ObjectID]
    public let message: String

    public init(rule: RuleID, object: ObjectID?, path: String? = nil, related: [ObjectID] = [], message: String) {
        self.rule = rule
        self.object = object
        self.path = path
        self.related = related
        self.message = message
    }

    /// What makes two findings the same finding across an edit: rule, object
    /// and related objects, never the message (integrity-repair design D5).
    public var identity: FindingIdentity { FindingIdentity(rule: rule, object: object, related: related) }

    /// `<severity> <rule> <object or path>: <message>` — the human line.
    public var description: String {
        var subject = object?.rawValue ?? ""
        if let path { subject += subject.isEmpty ? path : " \(path)" }
        return "\(severity.rawValue) \(rule.rawValue) \(subject): \(message)"
    }
}
