import PBXModel

/// M2: a phase entry that names nothing is removed; a build file whose file
/// does not resolve is removed from every phase listing it and deleted
/// (spec: Dangling phase entries are removed).
struct M2Fixer: Fixer {
    let rule = RuleID.M2

    func plan(_ finding: Finding, conventions: Conventions, builder: inout PlanBuilder) -> FixOutcome {
        let project = builder.project
        let key = RepairPlan.key(for: finding)
        guard let object = finding.object else { return .notFixable(reason: "the finding names no object") }
        if let phase = project.buildPhase(object) {
            // The entry that is not a build file: every listing of it goes.
            guard let entry = finding.related.first else { return .notFixable(reason: "the finding names no entry") }
            let listings = phase.files.filter { $0 == entry }.count
            guard listings > 0 else { return .notFixable(reason: "\(entry) is no longer listed in \(project.describePhase(phase))") }
            for _ in 0..<listings {
                builder.add(.removePhaseEntry(entry, from: phase.id), touching: [phase.id])
                builder.record(Change(path: key, action: .removedPhaseEntry, object: phase.id, detail: "entry \(entry) in \(project.describePhase(phase))"))
            }
            return .planned
        }
        guard project.buildFile(object) != nil else {
            return .notFixable(reason: "\(object) is neither a build phase nor a build file")
        }
        // A build file whose fileRef or productRef does not resolve: each
        // listing goes, then the object.
        for phase in project.phases(of: object) {
            builder.add(.removePhaseEntry(object, from: phase.id), touching: [object, phase.id])
            builder.record(Change(path: key, action: .removedPhaseEntry, object: phase.id, detail: "entry in \(project.describePhase(phase))"))
        }
        builder.add(.deleteObject(object), touching: [object])
        builder.record(Change(path: key, action: .deletedObject, object: object, detail: "build file whose file does not resolve"))
        return .planned
    }
}
