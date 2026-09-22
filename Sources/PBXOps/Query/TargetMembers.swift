import PBXModel

/// What `query --target` lists (design D2): every entry of the target's
/// build phases, ordered by phase name then path, absent paths last.
public struct TargetMembers: Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public let buildFile: ObjectID
        /// The build file's `fileRef`, resolved or not; `nil` when the entry
        /// is not a build file or has no `fileRef` (a package product).
        public let fileReference: ObjectID?
        /// The resolved path; `$(<sourceTree>)/<path>` for a reference that
        /// is not project-relative; `nil` when nothing resolves.
        public let path: String?
        public let phase: ObjectRef
        public let platformFilters: [String]

        public init(buildFile: ObjectID, fileReference: ObjectID?, path: String?, phase: ObjectRef, platformFilters: [String]) {
            self.buildFile = buildFile
            self.fileReference = fileReference
            self.path = path
            self.phase = phase
            self.platformFilters = platformFilters
        }
    }

    public let target: ObjectRef
    public let members: [Member]

    /// The listing for the target named exactly `name`, or `nil` when there
    /// is none. Names are matched byte for byte, like IDs.
    public init?(project: Project, target name: String) {
        guard let target = project.targets.first(where: { $0.name?.utf8.elementsEqual(name.utf8) == true }) else { return nil }
        self.init(project: project, target: target)
    }

    public init(project: Project, target: Target) {
        var members: [(order: Int, member: Member)] = []
        for phaseID in target.buildPhases {
            guard let phase = project.buildPhase(phaseID) else { continue }
            let ref = ObjectRef(phase)
            for entry in phase.files {
                let buildFile = project.buildFile(entry)
                let fileRef = buildFile?.fileRef
                let filters = buildFile?.platformFilters ?? buildFile?.platformFilter.map { [$0] } ?? []
                let path = fileRef.flatMap { TargetMembers.displayPath(of: $0, in: project) }
                members.append((members.count, Member(buildFile: entry, fileReference: fileRef, path: path, phase: ref, platformFilters: filters)))
            }
        }
        members.sort { lhs, rhs in
            if lhs.member.phase.name != rhs.member.phase.name { return (lhs.member.phase.name ?? "") < (rhs.member.phase.name ?? "") }
            switch (lhs.member.path, rhs.member.path) {
            case let (l?, r?) where l != r: return l.utf8.lexicographicallyPrecedes(r.utf8)
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.order < rhs.order
            }
        }
        self.target = ObjectRef(target)
        self.members = members.map(\.member)
    }

    /// Every target's name, sorted, for the unknown-target message.
    public static func targetNames(in project: Project) -> [String] {
        project.targets.compactMap(\.name).sorted()
    }

    /// A `fileRef` may name a file reference or a variant group; both resolve.
    /// A variant group has a `name` and no `path`, so it resolves to its
    /// directory; Xcode presents it as a file of that name there, and so
    /// does the listing.
    static func displayPath(of reference: ObjectID, in project: Project) -> String? {
        let object = project.object(reference)
        let variantName = object?.isa == Kind.variantGroup && object?.string("path") == nil ? object?.string("name") : nil
        switch project.resolvedPath(of: reference) {
        case .relative(let path)?, .absolute(let path)?:
            guard let variantName else { return path }
            return path.isEmpty ? variantName : path + "/" + variantName
        case .notProjectRelative(let sourceTree)?:
            return "$(\(sourceTree))/\(project.object(reference)?.string("path") ?? "")"
        case nil:
            return nil
        }
    }
}

extension TargetMembers.Member: Encodable {
    enum CodingKeys: String, CodingKey { case buildFile, fileReference, path, phase, platformFilters }

    // Absent values are `null`, never omitted (design D2).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(buildFile.rawValue, forKey: .buildFile)
        try container.encode(fileReference?.rawValue, forKey: .fileReference)
        try container.encode(path, forKey: .path)
        try container.encode(phase, forKey: .phase)
        try container.encode(platformFilters, forKey: .platformFilters)
    }
}

extension TargetMembers: Encodable {
    enum CodingKeys: String, CodingKey { case target, members }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(members, forKey: .members)
    }
}
