import PBXSyntax
import PBXModel

/// `pbxedit add`: the ensure semantics of design D3. For each path it asks
/// four questions and plans a step only for each "no": is there a reference
/// resolving here; is it a child of some group; does each chosen target have
/// a build file for it; is that build file in a phase. It only reads the
/// project; the runner applies the plan.
public enum AddPlanner {
    /// `paths` are source-root-relative and normalized (see `PathArgument`).
    /// Throws `PlanError` when a decision cannot be made; then nothing is
    /// planned for any path. `exemptions` is `lint.exempt` of `.pbxedit.yml`:
    /// a path exempt from M3 gets no group child (conventions-config design
    /// D6); without a configuration it is `nil` and nothing changes.
    public static func plan(_ paths: [String], in project: Project, conventions: Conventions, exemptions: Exemptions? = nil,
                            minter: IDMinter = IDMinter()) throws -> Plan {
        try plan(paths, in: project, conventions: conventions, exemptions: exemptions, minter: minter, perPhase: false)
    }

    /// `perPhase` is the merge's replay only (merge design D5): a target is
    /// "already a member" only through a build file in a phase of the chosen
    /// kind, so a second row (Resources beside Sources) can be written.
    static func plan(_ paths: [String], in project: Project, conventions: Conventions, exemptions: Exemptions? = nil,
                     minter: IDMinter = IDMinter(), perPhase: Bool) throws -> Plan {
        var builder = PlanBuilder(project: project, minter: minter)
        var claimedBuildFiles: Set<ObjectID> = []
        for path in paths {
            try plan(path, conventions: conventions, exemptions: exemptions, perPhase: perPhase, builder: &builder, claimed: &claimedBuildFiles)
        }
        return builder.build()
    }

    private static func plan(_ path: String, conventions: Conventions, exemptions: Exemptions?, perPhase: Bool, builder: inout PlanBuilder,
                             claimed: inout Set<ObjectID>) throws {
        let project = builder.project
        if let synchronized = project.synchronizedRootGroup(covering: path) {
            let folder = project.resolvedPath(of: synchronized.id)?.description ?? synchronized.path ?? ""
            builder.record(Change(path: path, action: .synchronized, object: synchronized.id,
                                  detail: "already a member via synchronized group \(folder) (\(synchronized.id))"))
            return
        }

        // What kind of file, and which phase.
        let fileType = FileTypes.type(of: path)
        guard fileType != nil || conventions.flags.phase != nil else { throw PlanError.unknownFileType(path: path) }
        let phase = conventions.phase(for: path, kind: fileType?.kind ?? .projectOnly)
        let kind = conventions.flags.phase?.kind ?? fileType?.kind ?? .projectOnly
        builder.decide(Decision(path: path, attribute: "phase", value: phase.value.displayName, source: phase.source))

        // The reference and its group. An M3-exempt path gets no group
        // child (design D6): the reference is spelled against SOURCE_ROOT.
        let ungrouped = exemptions?.match(.M3, path: path)
        let reference: ObjectID
        if let existing = project.fileReferences(at: path).first {
            reference = existing.id
            builder.record(Change(path: path, action: .reusedFileReference, object: existing.id, detail: "file reference \(path)"))
            let parents = project.parents(of: existing.id)
            if parents.isEmpty, let glob = ungrouped {
                builder.decide(Decision(path: path, attribute: "location", value: "in no group", source: .exemption(rule: .M3, glob: glob.pattern)))
            } else if parents.isEmpty {
                let location = try builder.group(forDirectory: SiblingInference.directory(of: path), path: path)
                builder.addChild(existing.id, named: existing.name ?? existing.path ?? path, to: location.group)
                builder.record(Change(path: path, action: .addedChild, object: location.group, detail: "child of group \(builder.describe(location.group))"))
            } else {
                for parent in parents { builder.touch(parent.id) }
            }
        } else if let glob = ungrouped {
            let id = builder.mint()
            builder.add(.createFileReference(
                id: id, path: path, name: PlanBuilder.basename(of: path), sourceTree: Kind.sourceRootSourceTree,
                lastKnownFileType: fileType?.lastKnownFileType ?? FileTypes.unknownLastKnownFileType))
            builder.record(Change(path: path, action: .createdFileReference, object: id,
                                  detail: "file reference for \(path) (path = \(path); sourceTree = \(Kind.sourceRootSourceTree))"))
            builder.decide(Decision(
                path: path, attribute: "location",
                value: "path = \(path); sourceTree = \(Kind.sourceRootSourceTree); in no group",
                source: .exemption(rule: .M3, glob: glob.pattern)))
            reference = id
        } else {
            let location = try builder.group(forDirectory: SiblingInference.directory(of: path), path: path)
            let spelling = builder.reference(for: path, in: location)
            let id = builder.mint()
            builder.add(.createFileReference(
                id: id, path: spelling.path, name: spelling.name, sourceTree: spelling.sourceTree,
                lastKnownFileType: fileType?.lastKnownFileType ?? FileTypes.unknownLastKnownFileType))
            builder.record(Change(path: path, action: .createdFileReference, object: id,
                                  detail: "file reference for \(path) (path = \(spelling.path); sourceTree = \(spelling.sourceTree))"))
            builder.decide(Decision(
                path: path, attribute: "location",
                value: "path = \(spelling.path); sourceTree = \(spelling.sourceTree); in group \(builder.describe(location.group))",
                source: .structure))
            builder.addChild(id, named: spelling.name ?? spelling.path, to: location.group)
            builder.record(Change(path: path, action: .addedChild, object: location.group, detail: "child of group \(builder.describe(location.group))"))
            reference = id
        }

        guard let phaseIsa = phase.value.isa else { return }

        // The targets, and a build file in the right phase for each.
        let choice = try conventions.targets(for: path, kind: kind, in: project)
        builder.decide(Decision(
            path: path, attribute: "targets", value: choice.targets.map { $0.name ?? $0.id.rawValue }.joined(separator: ", "),
            source: choice.source))
        for extra in choice.extras {
            let name = extra.target.name ?? extra.target.id.rawValue
            let all = (choice.targets + [extra.target]).map { "--target \($0.name ?? $0.id.rawValue)" }.joined(separator: " ")
            let directory: String
            if case .inferred(_, let inferredFrom) = choice.source { directory = inferredFrom } else { directory = SiblingInference.directory(of: path) }
            let verb = extra.count == 1 ? "is also a member" : "are also members"
            builder.note("\(path): \(extra.count) of \(extra.of) siblings in \(directory) \(verb) of \(name); pass \(all) to join it too")
        }
        let membership = project.membership(of: reference)
        for target in choice.targets {
            let targetName = target.name ?? target.id.rawValue
            guard let targetPhase = target.buildPhases.compactMap(project.buildPhase).first(where: { $0.isa == phaseIsa }) else {
                throw PlanError.noSuchPhase(path: path, target: targetName, phase: phase.value.displayName)
            }
            let inTarget = membership.buildFiles.filter { entry in
                entry.phases.contains { $0.targets.contains { $0.id == target.id } && (!perPhase || $0.phase.isa == phaseIsa) }
            }
            if !inTarget.isEmpty {
                for entry in inTarget {
                    builder.record(Change(path: path, action: .reusedBuildFile, object: entry.buildFile.id, detail: "build file in \(targetName)"))
                }
                continue
            }
            let buildFile: ObjectID
            if let unphased = membership.buildFiles.first(where: { $0.phases.isEmpty && !claimed.contains($0.buildFile.id) }) {
                buildFile = unphased.buildFile.id
                claimed.insert(buildFile)
                builder.record(Change(path: path, action: .reusedBuildFile, object: buildFile, detail: "build file that was in no phase"))
            } else {
                let filters = try conventions.platformFilters(for: path, kind: kind, target: target, in: project)
                builder.decide(Decision(
                    path: path, attribute: "platformFilters",
                    value: "\(targetName): \(filters.value.isEmpty ? "none" : filters.value.joined(separator: ", "))", source: filters.source))
                buildFile = builder.mint()
                builder.add(.createBuildFile(id: buildFile, fileRef: reference, platformFilters: filters.value), touching: [buildFile])
                builder.record(Change(path: path, action: .createdBuildFile, object: buildFile, detail: "build file for \(targetName)"))
            }
            builder.add(.addPhaseEntry(buildFile, to: targetPhase.id, position: .last), touching: [buildFile, targetPhase.id])
            builder.record(Change(path: path, action: .addedPhaseEntry, object: targetPhase.id,
                                  detail: "entry in \(targetPhase.displayName) of \(targetName) (\(targetPhase.id))"))
        }
    }
}
