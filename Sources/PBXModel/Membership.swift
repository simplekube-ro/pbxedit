import PBXSyntax

/// Everything the model knows about how one file reference is built: its
/// build files, the phase each is listed in (none, one or several), the
/// targets owning those phases, and the groups listing the reference.
public struct Membership: Equatable {
    public struct PhaseEntry: Equatable {
        public let phase: BuildPhase
        /// The targets whose `buildPhases` list the phase, in object order.
        public let targets: [Target]
    }

    public struct BuildFileEntry: Equatable {
        public let buildFile: BuildFile
        /// One entry per listing, so a phase that lists the build file twice
        /// appears twice (rule S3's input).
        public let phases: [PhaseEntry]
        public var platformFilters: [String]? { buildFile.platformFilters }
        public var platformFilter: String? { buildFile.platformFilter }
    }

    public let fileReference: ObjectID
    public let buildFiles: [BuildFileEntry]
    /// The groups listing the reference as a child (rule M3's input).
    public let parents: [Group]

    /// Every target that builds the reference, each once, in object order.
    public var targets: [Target] {
        var seen: Set<ObjectID> = []
        var result: [Target] = []
        for entry in buildFiles {
            for phase in entry.phases {
                for target in phase.targets where !seen.contains(target.id) {
                    seen.insert(target.id)
                    result.append(target)
                }
            }
        }
        return result
    }
}

extension Project {
    /// The build files whose `fileRef` is `fileReference`, in object order.
    public func buildFiles(for fileReference: ObjectID) -> [BuildFile] {
        (membershipIndex.buildFilesByFileRef[fileReference] ?? []).compactMap(buildFile)
    }

    /// The phases whose `files` list `buildFile`, one per listing, in object order.
    public func phases(of buildFile: ObjectID) -> [BuildPhase] {
        (membershipIndex.phasesByBuildFile[buildFile] ?? []).compactMap(buildPhase)
    }

    /// The targets whose `buildPhases` list `phase`, in object order.
    public func targets(owning phase: ObjectID) -> [Target] {
        (membershipIndex.targetsByPhase[phase] ?? []).compactMap(target)
    }

    /// The targets whose `fileSystemSynchronizedGroups` list `group`.
    public func targets(synchronizing group: ObjectID) -> [Target] {
        (membershipIndex.targetsBySynchronizedGroup[group] ?? []).compactMap(target)
    }

    public func membership(of fileReference: ObjectID) -> Membership {
        Membership(
            fileReference: fileReference,
            buildFiles: buildFiles(for: fileReference).map { buildFile in
                Membership.BuildFileEntry(
                    buildFile: buildFile,
                    phases: phases(of: buildFile.id).map { phase in
                        Membership.PhaseEntry(phase: phase, targets: targets(owning: phase.id))
                    })
            },
            parents: parents(of: fileReference))
    }

    /// The synchronized root group whose folder contains `path`, when one
    /// does. Membership exception sets are not consulted (out of scope for v1).
    public func synchronizedRootGroup(covering path: String) -> SynchronizedRootGroup? {
        let normalized = PathNormalizer.normalize(path)
        var candidate = normalized
        while let slash = candidate.lastIndex(of: "/") {
            candidate = String(candidate[..<slash])
            if let id = pathIndex.synchronizedGroupsByPath[candidate]?.first, let group = synchronizedRootGroup(id) {
                return group
            }
        }
        return nil
    }
}
