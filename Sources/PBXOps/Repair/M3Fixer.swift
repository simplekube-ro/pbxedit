import PBXModel

/// M3: a file reference in no group becomes a child of the group for its
/// resolved directory — add's resolution, groups created as needed — and
/// nothing about the reference itself changes (design D4). A reference that
/// would resolve elsewhere once grouped, one that is not project-relative,
/// and one with several parents are reported with the reason.
struct M3Fixer: Fixer {
    let rule = RuleID.M3

    func plan(_ finding: Finding, conventions: Conventions, builder: inout PlanBuilder) -> FixOutcome {
        let project = builder.project
        let key = RepairPlan.key(for: finding)
        guard let object = finding.object, let reference = project.fileReference(object) else {
            return .notFixable(reason: "\(finding.object?.rawValue ?? "") is not a file reference")
        }
        var parents: [ObjectID] = []
        for parent in project.parents(of: object) where !parents.contains(parent.id) { parents.append(parent.id) }
        guard parents.isEmpty else {
            return .notFixable(reason: "a child of \(parents.count) groups, \(PlanError.list(parents.map(\.rawValue))); which one is right is a human decision")
        }
        let path: String
        switch project.resolvedPath(of: object) {
        case .relative(let resolved)?:
            path = resolved
        case .absolute(let resolved)?:
            return .notFixable(reason: "an absolute path (\(resolved)); no group stands for its directory")
        case .notProjectRelative(let sourceTree)?:
            return .notFixable(reason: "not project-relative (sourceTree = \(sourceTree)); no group stands for its directory")
        case nil:
            return .notFixable(reason: "its path does not resolve")
        }

        // Resolve the destination on a copy of the builder, so a refused
        // orphan leaves no planned group behind.
        var probe = builder
        let location: GroupLocation
        do {
            location = try probe.group(forDirectory: SiblingInference.directory(of: path), path: key)
        } catch let error as PlanError {
            return .notFixable(reason: error.description)
        } catch {
            return .notFixable(reason: "\(error)")
        }

        // Design D4: the reference is not re-spelled, so a `<group>`-relative
        // path must resolve the same under its new parent.
        if reference.sourceTree == Kind.groupSourceTree {
            let own = reference.path ?? ""
            let destination = probe.resolvedDirectory(of: location.group)
            let after = PathNormalizer.normalize(destination.isEmpty ? own : destination + "/" + own)
            guard after == path else {
                return .notFixable(reason: "its <group>-relative path \(own) would resolve to \(after) under the group for \(SiblingInference.directory(of: path)); "
                    + "pbxedit remove \(path), then pbxedit add \(path), re-spells it")
            }
        }

        builder = probe
        let name = project.annotation(for: object) ?? PlanBuilder.basename(of: path)
        builder.addChild(object, named: name, to: location.group)
        builder.record(Change(path: key, action: .addedChild, object: location.group, detail: "child of group \(builder.describe(location.group))"))
        return .planned
    }
}

extension PlanBuilder {
    /// The directory a group — existing, or planned by this builder — will
    /// resolve to once the plan is applied; `""` for the source root.
    func resolvedDirectory(of group: ObjectID) -> String {
        if let planned = plannedGroups.first(where: { $0.value.id == group }) { return planned.key }
        if case .relative(let directory)? = project.resolvedPath(of: group) { return directory }
        return ""
    }
}
