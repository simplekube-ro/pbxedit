import PBXModel

/// What a planner asks about a file's membership (design D4). Each answer is
/// `flags ?? config ?? infer`: the configuration layer (`conventions-config`
/// design D1) sits between the two, and no planner can tell.
public struct Conventions {
    public struct Flags: Equatable, Sendable {
        /// `--target`, by name.
        public var targets: [String]?
        /// `--platform`; empty means "none", explicitly.
        public var platformFilters: [String]?
        /// `--phase`.
        public var phase: PhaseChoice?

        public init(targets: [String]? = nil, platformFilters: [String]? = nil, phase: PhaseChoice? = nil) {
            self.targets = targets
            self.platformFilters = platformFilters
            self.phase = phase
        }
    }

    /// A target some but not all siblings belong to.
    public struct Extra: Equatable {
        public let target: Target
        public let count: Int
        public let of: Int
    }

    public struct TargetChoice: Equatable {
        public let targets: [Target]
        public let source: Decision.Source
        public let extras: [Extra]
    }

    public var flags: Flags
    /// The `rules` of `.pbxedit.yml`, re-based to the source root; `nil`
    /// without a configuration.
    public var config: ConfigConventions?

    public init(flags: Flags = Flags(), config: ConfigConventions? = nil) {
        self.flags = flags
        self.config = config
    }

    /// The targets a file at `path` joins, sorted by name.
    public func targets(for path: String, kind: FileKind, in project: Project) throws -> TargetChoice {
        if let names = flags.targets {
            return TargetChoice(targets: try Conventions.resolve(names, in: project), source: .flag, extras: [])
        }
        if let configured = config?.targets(for: path) {
            return TargetChoice(targets: try Conventions.resolve(configured.value, in: project), source: configured.source, extras: [])
        }
        guard let siblings = SiblingInference.siblings(of: path, kind: kind, in: project) else {
            throw PlanError.noSiblings(path: path)
        }
        var counts: [ObjectID: Int] = [:]
        var targetsByID: [ObjectID: Target] = [:]
        for member in siblings.members {
            for target in member.targets {
                counts[target.id, default: 0] += 1
                targetsByID[target.id] = target
            }
        }
        let total = siblings.members.count
        let common = Conventions.byName(counts.filter { $0.value == total }.compactMap { targetsByID[$0.key] })
        guard !common.isEmpty else {
            var variants: [String: (targets: [String], count: Int)] = [:]
            for member in siblings.members {
                let names = Conventions.byName(member.targets).map { $0.name ?? $0.id.rawValue }
                let key = names.joined(separator: "\u{0}")
                variants[key, default: (names, 0)].count += 1
            }
            let listed = variants.values.sorted { $0.targets.joined(separator: "/") < $1.targets.joined(separator: "/") }
                .map { PlanError.TargetVariant(targets: $0.targets, count: $0.count) }
            throw PlanError.noCommonTarget(path: path, directory: siblings.directory, variants: listed)
        }
        let extras = Conventions.byName(counts.filter { $0.value < total }.compactMap { targetsByID[$0.key] })
            .map { Extra(target: $0, count: counts[$0.id] ?? 0, of: total) }
        return TargetChoice(targets: common, source: .inferred(siblings: total, directory: siblings.directory), extras: extras)
    }

    /// The `platformFilters` of the build file that joins `target`.
    public func platformFilters(for path: String, kind: FileKind, target: Target, in project: Project) throws -> Decided<[String]> {
        if let filters = flags.platformFilters { return Decided(filters, source: .flag) }
        if let configured = config?.platformFilters(for: path) { return configured }
        guard let siblings = SiblingInference.siblings(of: path, kind: kind, in: project) else {
            return Decided([], source: .inferred(siblings: 0, directory: SiblingInference.directory(of: path)))
        }
        var variants: [[String]: Int] = [:]
        var considered = 0
        for member in siblings.members {
            let inTarget = member.buildFiles.filter { entry in entry.phases.contains { $0.targets.contains { $0.id == target.id } } }
            guard !inTarget.isEmpty else { continue }
            considered += 1
            for entry in inTarget {
                variants[PlatformFilters.read(from: entry.buildFile), default: 0] += 1
            }
        }
        let source = Decision.Source.inferred(siblings: considered, directory: siblings.directory)
        switch variants.count {
        case 0: return Decided([], source: source)
        case 1: return Decided(variants.keys.first ?? [], source: source)
        default:
            let listed = variants.map { PlanError.FilterVariant(filters: $0.key, count: $0.value) }
                .sorted { $0.filters.joined(separator: ",") < $1.filters.joined(separator: ",") }
            throw PlanError.ambiguousPlatformFilters(path: path, target: target.name ?? target.id.rawValue, directory: siblings.directory, variants: listed)
        }
    }

    /// The phase the file goes to: `--phase`, else the file type's.
    public func phase(for path: String, kind: FileKind) -> Decided<PhaseChoice> {
        if let phase = flags.phase { return Decided(phase, source: .flag) }
        return Decided(PhaseChoice(kind: kind), source: .fileType)
    }

    static func byName(_ targets: [Target]) -> [Target] {
        targets.sorted { ($0.name ?? "", $0.id) < ($1.name ?? "", $1.id) }
    }

    /// Names (from a flag or a rule) to targets, each once, sorted by name;
    /// an unknown name is `PlanError.unknownTarget`.
    static func resolve(_ names: [String], in project: Project) throws -> [Target] {
        let available = project.targets.compactMap(\.name).sorted()
        var targets: [Target] = []
        for name in names {
            guard let target = project.targets.first(where: { $0.name?.utf8.elementsEqual(name.utf8) == true }) else {
                throw PlanError.unknownTarget(name: name, available: available)
            }
            if !targets.contains(where: { $0.id == target.id }) { targets.append(target) }
        }
        return byName(targets)
    }
}

/// Step 1 of design D4: the files of the same kind in the same directory,
/// or in the nearest ancestor directory that has any.
enum SiblingInference {
    struct Member {
        let reference: FileReference
        let targets: [Target]
        let buildFiles: [Membership.BuildFileEntry]
    }

    struct Siblings {
        let directory: String
        let members: [Member]
    }

    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// `nil` when no directory up to the source root holds a sibling that
    /// some target builds.
    static func siblings(of path: String, kind: FileKind, in project: Project) -> Siblings? {
        var byDirectory: [String: [Member]] = [:]
        for reference in project.fileReferences {
            guard case .relative(let resolved)? = project.resolvedPath(of: reference.id), resolved != path,
                  FileTypes.type(of: resolved)?.kind == kind
            else { continue }
            let membership = project.membership(of: reference.id)
            let targets = membership.targets
            guard !targets.isEmpty else { continue }
            byDirectory[directory(of: resolved), default: []].append(Member(reference: reference, targets: targets, buildFiles: membership.buildFiles))
        }
        var current = directory(of: path)
        while true {
            if let members = byDirectory[current], !members.isEmpty { return Siblings(directory: current, members: members) }
            if current.isEmpty { return nil }
            current = directory(of: current)
        }
    }
}
