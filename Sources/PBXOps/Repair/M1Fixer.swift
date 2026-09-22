import PBXModel

/// M1: a build file in no phase joins the phase for its file's kind in the
/// one target its siblings belong to, as `add` would place it (design D3);
/// one whose file does not resolve is deleted. Anything else is a human
/// decision, reported with the reason.
struct M1Fixer: Fixer {
    let rule = RuleID.M1

    func plan(_ finding: Finding, conventions: Conventions, builder: inout PlanBuilder) -> FixOutcome {
        let project = builder.project
        let key = RepairPlan.key(for: finding)
        guard let object = finding.object, let buildFile = project.buildFile(object) else {
            return .notFixable(reason: "\(finding.object?.rawValue ?? "") is not a build file")
        }
        let phases = project.distinctPhases(of: object)
        guard phases.isEmpty else {
            return .notFixable(reason: "listed in \(phases.count) build phases; which one is right is a human decision")
        }

        // The file. A build file that points at nothing carries no
        // recoverable information except its ID: deleted, as M2 deletes one
        // in a phase.
        let fileRef: ObjectID
        if let reference = buildFile.fileRef {
            guard project.contains(reference) else { return delete(object, key: key, builder: &builder) }
            guard project.fileReference(reference) != nil else {
                return .notFixable(reason: "its fileRef \(reference) is not a file reference")
            }
            fileRef = reference
        } else if let productRef = buildFile.productRef {
            guard project.contains(productRef) else { return delete(object, key: key, builder: &builder) }
            return .notFixable(reason: "a package product (productRef \(productRef)); the phase of a product dependency is not inferred")
        } else {
            return delete(object, key: key, builder: &builder)
        }
        guard case .relative(let path)? = project.resolvedPath(of: fileRef) else {
            return .notFixable(reason: "its file \(project.displayPath(of: fileRef)) is not project-relative; there are no siblings to infer a target from")
        }
        guard let type = FileTypes.type(of: path) else {
            return .notFixable(reason: "unknown file type; the build phase cannot be inferred for \(path)")
        }
        guard let phaseIsa = PhaseChoice(kind: type.kind).isa else {
            return .notFixable(reason: "\(path) is a project-only file type that is never built; delete the build file")
        }

        // The target, as add decides it, with the flags empty.
        let choice: Conventions.TargetChoice
        do {
            choice = try conventions.targets(for: path, kind: type.kind, in: project)
        } catch let error as PlanError {
            return .notFixable(reason: M1Fixer.reason(for: error))
        } catch {
            return .notFixable(reason: "\(error)")
        }
        let names = choice.targets.map { $0.name ?? $0.id.rawValue }
        guard choice.targets.count == 1, let target = choice.targets.first else {
            let listed = PlanError.list(names)
            switch choice.source {
            case .config(let rule, let glob):
                return .notFixable(reason: "the configuration (rule \(rule) \"\(glob)\") names \(names.count) targets, \(listed); one orphaned build file can belong to only one of them")
            default:
                return .notFixable(reason: "the siblings in \(directory(of: choice.source, path: path)) all belong to \(names.count) targets, \(listed); one orphaned build file can belong to only one of them")
            }
        }
        let targetName = target.name ?? target.id.rawValue
        guard let targetPhase = target.buildPhases.compactMap(project.buildPhase).first(where: { $0.isa == phaseIsa }) else {
            return .notFixable(reason: "target \(targetName) has no \(PhaseChoice(kind: type.kind).displayName) phase")
        }
        let membership = project.membership(of: fileRef)
        if let existing = membership.buildFiles.first(where: { entry in
            entry.buildFile.id != object && entry.phases.contains { $0.targets.contains { $0.id == target.id } }
        }) {
            let how = choice.source.kind == "config" ? "configured" : "inferred"
            return .notFixable(reason: "the \(how) target \(targetName) already builds the file (build file \(existing.buildFile.id)); a second listing would be an M5")
        }

        builder.decide(Decision(path: key, attribute: "targets", value: targetName, source: choice.source))
        for extra in choice.extras {
            let name = extra.target.name ?? extra.target.id.rawValue
            let verb = extra.count == 1 ? "is also a member" : "are also members"
            builder.note("\(key): \(extra.count) of \(extra.of) siblings in \(directory(of: choice.source, path: path)) \(verb) of \(name); pbxedit add \(path) --target \(name) adds it there too")
        }
        builder.add(.addPhaseEntry(object, to: targetPhase.id, position: .last), touching: [object, targetPhase.id])
        builder.record(Change(path: key, action: .addedPhaseEntry, object: targetPhase.id, detail: "entry in \(project.describePhase(targetPhase))"))
        return .planned
    }

    private func delete(_ buildFile: ObjectID, key: String, builder: inout PlanBuilder) -> FixOutcome {
        builder.add(.deleteObject(buildFile), touching: [buildFile])
        builder.record(Change(path: key, action: .deletedObject, object: buildFile, detail: "build file in no phase whose file does not resolve"))
        return .planned
    }

    private func directory(of source: Decision.Source, path: String) -> String {
        if case .inferred(_, let directory) = source { return directory }
        return SiblingInference.directory(of: path)
    }

    /// `PlanError`'s message without the flag it would suggest to `add`.
    static func reason(for error: PlanError) -> String {
        switch error {
        case .noSiblings:
            return "no file of the same kind in its directory or any ancestor to infer a target from"
        case .noCommonTarget(_, let directory, let variants):
            let listed = variants.map { "\($0.targets.joined(separator: "+")) (\($0.count))" }.joined(separator: ", ")
            return "the siblings in \(directory) have no target in common: \(listed)"
        default:
            return error.description
        }
    }
}
