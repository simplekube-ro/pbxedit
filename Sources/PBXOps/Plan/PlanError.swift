import PBXModel

/// Why a planner refused (design, Non-Goals: where siblings disagree the
/// command stops and asks). Each case renders as the message the command
/// prints; all but the unknown-name cases are exit `1`.
public enum PlanError: Error, Equatable, Sendable, CustomStringConvertible {
    public struct TargetVariant: Equatable, Sendable {
        public let targets: [String]
        public let count: Int
        public init(targets: [String], count: Int) {
            self.targets = targets
            self.count = count
        }
    }

    public struct FilterVariant: Equatable, Sendable {
        public let filters: [String]
        public let count: Int
        public init(filters: [String], count: Int) {
            self.filters = filters
            self.count = count
        }
    }

    /// The extension is not in the file-type table and no `--phase` was given.
    case unknownFileType(path: String)
    /// No sibling of the same kind exists in the directory or any ancestor.
    case noSiblings(path: String)
    /// Siblings exist but no target is common to all of them.
    case noCommonTarget(path: String, directory: String, variants: [TargetVariant])
    /// Siblings in the target disagree about `platformFilters`.
    case ambiguousPlatformFilters(path: String, target: String, directory: String, variants: [FilterVariant])
    /// The target has no phase of the kind the file needs.
    case noSuchPhase(path: String, target: String, phase: String)
    /// The project's `mainGroup` is missing or is not a group; nothing can be added at the root.
    case noMainGroup
    /// `--target` named a target the project does not have (exit `2`).
    case unknownTarget(name: String, available: [String])
    /// `--platform` named a platform the rule set does not know (exit `2`).
    case unknownPlatform(name: String, known: [String])
    /// `remove`: no file reference resolves to the path (remove design D2).
    case notInProject(path: String)
    /// `remove`: the path lies in a synchronized folder and has no reference of its own (remove design D7).
    case synchronizedMembership(path: String, group: ObjectID, folder: String)
    /// `remove`: the reference is a child of a variant or version group (remove design D7).
    case unsupportedContainer(path: String, group: ObjectID, isa: String)
    /// `remove`: several targets build the file and neither `--target` nor `--all` was given (remove design D3).
    case sharedFile(path: String, targets: [String])
    /// `remove --target`: the file is not a member of that target (remove design D4).
    case notMemberOfTarget(path: String, target: String, targets: [String])

    public var description: String {
        switch self {
        case .notInProject(let path):
            return "\(path): not in the project; no file reference resolves to it"
        case .synchronizedMembership(let path, let group, let folder):
            return "\(path): its membership comes from the synchronized folder \(folder) (\(group)), which pbxedit does not edit; no file reference to remove"
        case .unsupportedContainer(let path, let group, let isa):
            let what = isa == Kind.variantGroup ? "a localized variant in variant group" : "a child of \(isa)"
            return "\(path): is \(what) \(group); removing such files is not supported"
        case .sharedFile(let path, let targets):
            return "\(path) belongs to \(PlanError.list(targets)); pass --target <name> to detach it from one, or --all to remove it from the project"
        case .notMemberOfTarget(let path, let target, let targets):
            let belongs = targets.isEmpty ? "it is built by no target" : "it belongs to \(PlanError.list(targets))"
            return "\(path) is not a member of \(target); \(belongs)"
        case .unknownFileType(let path):
            return "\(path): unknown file type; pass --phase sources|resources|headers|none to say where it goes"
        case .noSiblings(let path):
            return "\(path): no file of the same kind in its directory or any ancestor to infer targets from; pass --target"
        case .noCommonTarget(let path, let directory, let variants):
            let listed = variants.map { "\($0.targets.joined(separator: "+")) (\($0.count))" }.joined(separator: ", ")
            return "\(path): the siblings in \(directory) have no target in common: \(listed); pass --target"
        case .ambiguousPlatformFilters(let path, let target, let directory, let variants):
            let listed = variants.map { "\($0.filters.isEmpty ? "none" : $0.filters.joined(separator: ",")) (\($0.count))" }.joined(separator: ", ")
            return "\(path): the siblings in \(directory) built by \(target) disagree about platformFilters: \(listed); pass --platform"
        case .noSuchPhase(let path, let target, let phase):
            return "\(path): target \(target) has no \(phase) phase"
        case .noMainGroup:
            return "the project's mainGroup does not resolve to a group; nothing can be added at the source root"
        case .unknownTarget(let name, let available):
            return "no target named \(name); the project's targets are: \(available.joined(separator: ", "))"
        case .unknownPlatform(let name, let known):
            return "unknown platform \(name); known platform names: \(known.joined(separator: ", ")), or none"
        }
    }

    /// `A`, `A and B`, `A, B and C`.
    static func list(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.joined() }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
