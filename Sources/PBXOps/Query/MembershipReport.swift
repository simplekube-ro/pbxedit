import PBXModel

/// An object named by ID and, when it has one, by name: a target or a build
/// phase in a report. Encoded as `{"id": …, "name": …}`.
public struct ObjectRef: Equatable, Sendable {
    public let id: ObjectID
    public let name: String?

    public init(id: ObjectID, name: String?) {
        self.id = id
        self.name = name
    }

    init(_ target: Target) { self.init(id: target.id, name: target.name) }
    init(_ phase: BuildPhase) { self.init(id: phase.id, name: phase.displayName) }
}

extension ObjectRef: Encodable {
    enum CodingKeys: String, CodingKey { case id, name }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.rawValue, forKey: .id)
        try container.encode(name, forKey: .name)
    }
}

/// Everything `query` says about one path (design D2), built from a loaded
/// project and a source-root-relative path. Facts as found, no judgements: a
/// reference in no group, or a build file in no phase, is reported as such.
/// Later commands embed the same value as "membership after the operation".
public struct MembershipReport: Equatable, Sendable {
    /// One build file × one phase listing × one owning target. A build file
    /// in no phase yields one entry with `phase` and `target` absent; a phase
    /// no target lists yields entries with `target` absent.
    public struct Entry: Equatable, Sendable {
        public let target: ObjectRef?
        public let phase: ObjectRef?
        public let buildFile: ObjectID
        /// `platformFilters`, else the single `platformFilter`, else empty.
        public let platformFilters: [String]

        public init(target: ObjectRef?, phase: ObjectRef?, buildFile: ObjectID, platformFilters: [String]) {
            self.target = target
            self.phase = phase
            self.buildFile = buildFile
            self.platformFilters = platformFilters
        }
    }

    /// The synchronized root group whose folder contains the path.
    public struct SynchronizedCoverage: Equatable, Sendable {
        public let group: ObjectID
        public let path: String
        public let targets: [ObjectRef]

        public init(group: ObjectID, path: String, targets: [ObjectRef]) {
            self.group = group
            self.path = path
            self.targets = targets
        }
    }

    /// Source-root-relative, normalized.
    public let path: String
    /// Whether a file reference resolves to `path`.
    public let member: Bool
    /// The first reference resolving to `path` in object order.
    public let fileReference: ObjectID?
    /// The `name ?? path` of each group from the main group's child down to
    /// the reference's first parent, joined by `/`; `""` directly under the
    /// main group; `nil` when the reference has no parent.
    public let groupPath: String?
    /// Every group listing the reference (rule M3's input).
    public let groups: [ObjectID]
    /// Ordered by target name, phase name, build file ID.
    public let memberships: [Entry]
    public let synchronized: SynchronizedCoverage?

    public init(path: String, member: Bool, fileReference: ObjectID?, groupPath: String?, groups: [ObjectID],
                memberships: [Entry], synchronized: SynchronizedCoverage?) {
        self.path = path
        self.member = member
        self.fileReference = fileReference
        self.groupPath = groupPath
        self.groups = groups
        self.memberships = memberships
        self.synchronized = synchronized
    }

    /// The report for `path`, which must already be source-root-relative
    /// (see `PathArgument`). Reads the model only.
    public init(project: Project, path: String) {
        let normalized = PathNormalizer.normalize(path)
        guard let reference = project.fileReferences(at: normalized).first else {
            let coverage = project.synchronizedRootGroup(covering: normalized).map { group in
                SynchronizedCoverage(
                    group: group.id,
                    path: project.resolvedPath(of: group.id)?.description ?? group.path ?? "",
                    targets: project.targets(synchronizing: group.id).map(ObjectRef.init))
            }
            self.init(path: normalized, member: false, fileReference: nil, groupPath: nil, groups: [], memberships: [], synchronized: coverage)
            return
        }
        let membership = project.membership(of: reference.id)
        var entries: [Entry] = []
        for buildFile in membership.buildFiles {
            let filters = buildFile.platformFilters ?? buildFile.platformFilter.map { [$0] } ?? []
            if buildFile.phases.isEmpty {
                entries.append(Entry(target: nil, phase: nil, buildFile: buildFile.buildFile.id, platformFilters: filters))
                continue
            }
            for phase in buildFile.phases {
                if phase.targets.isEmpty {
                    entries.append(Entry(target: nil, phase: ObjectRef(phase.phase), buildFile: buildFile.buildFile.id, platformFilters: filters))
                }
                for target in phase.targets {
                    entries.append(Entry(target: ObjectRef(target), phase: ObjectRef(phase.phase), buildFile: buildFile.buildFile.id, platformFilters: filters))
                }
            }
        }
        entries.sort { lhs, rhs in
            let l = (lhs.target?.name ?? "", lhs.phase?.name ?? "")
            let r = (rhs.target?.name ?? "", rhs.phase?.name ?? "")
            if l != r { return l < r }
            return lhs.buildFile < rhs.buildFile
        }
        self.init(
            path: normalized,
            member: true,
            fileReference: reference.id,
            groupPath: MembershipReport.groupPath(of: reference.id, in: project),
            groups: membership.parents.map(\.id),
            memberships: entries,
            synchronized: nil)
    }

    /// Group names from the top down to the first parent of `id`, stopping
    /// at a group with no parent or at a revisit.
    static func groupPath(of id: ObjectID, in project: Project) -> String? {
        guard var current = project.parents(of: id).first else { return nil }
        var names: [String] = []
        var seen: Set<ObjectID> = []
        while seen.insert(current.id).inserted {
            if let name = current.name ?? current.path { names.append(name) }
            guard let parent = project.parents(of: current.id).first else { break }
            current = parent
        }
        return names.reversed().joined(separator: "/")
    }
}

// Absent values are `null`, never omitted (design D2): consumers rely on
// every key being present.
extension MembershipReport.Entry: Encodable {
    enum CodingKeys: String, CodingKey { case target, phase, buildFile, platformFilters }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(phase, forKey: .phase)
        try container.encode(buildFile.rawValue, forKey: .buildFile)
        try container.encode(platformFilters, forKey: .platformFilters)
    }
}

extension MembershipReport.SynchronizedCoverage: Encodable {
    enum CodingKeys: String, CodingKey { case group, path, targets }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(group.rawValue, forKey: .group)
        try container.encode(path, forKey: .path)
        try container.encode(targets, forKey: .targets)
    }
}

extension MembershipReport: Encodable {
    enum CodingKeys: String, CodingKey { case path, member, fileReference, groupPath, groups, memberships, synchronized }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(member, forKey: .member)
        try container.encode(fileReference?.rawValue, forKey: .fileReference)
        try container.encode(groupPath, forKey: .groupPath)
        try container.encode(groups.map(\.rawValue), forKey: .groups)
        try container.encode(memberships, forKey: .memberships)
        try container.encode(synchronized, forKey: .synchronized)
    }
}
