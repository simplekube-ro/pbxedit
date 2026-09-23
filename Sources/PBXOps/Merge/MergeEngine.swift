import PBXSyntax
import PBXModel

/// What a merge came to (merge design D11): everything the report prints.
/// The engine never touches the disk; the command writes `result`.
public struct MergeReport {
    public enum Status: String, Equatable, Sendable {
        /// Merged and verified, or nothing to merge.
        case merged
        /// Some unit or hunk needs a decision that was not supplied (exit `3`).
        case decisionsNeeded
        /// A check failed or a step was refused (exit `1`).
        case failed
        /// Input the merge does not support (exit `2`).
        case unsupported
    }

    /// A unit, and what was decided and done.
    public struct UnitEntry: Equatable, Sendable {
        public let classified: ClassifiedUnit
        /// The supplied choice; `nil` when none was needed or given.
        public let decision: UnitChoice?
        /// What the replay did, with object IDs; empty when nothing was replayed.
        public internal(set) var changes: [Change]

        public var key: String { classified.unit.key }
        public var isOpen: Bool { classified.outcome == .decision && decision == nil }
    }

    /// A hunk, and what was decided.
    public struct HunkEntry: Equatable, Sendable {
        public let analysed: AnalysedHunk
        public let decision: HunkChoice?

        public var key: String { analysed.key }
    }

    public internal(set) var status: Status
    /// Ours equals theirs: there was nothing to merge.
    public internal(set) var nothingToMerge = false
    public let inputs: MergeDecisions.Inputs
    public internal(set) var units: [UnitEntry] = []
    public internal(set) var hunks: [HunkEntry] = []
    /// Every check that ran, in the order it ran.
    public internal(set) var checks: [CheckResult] = []
    /// Residuals of units decided `theirs-membership`.
    public internal(set) var owed: [Residual] = []
    /// Check A's new findings.
    public internal(set) var findings: [Finding] = []
    /// The decisions template, when decisions are needed.
    public internal(set) var template: MergeDecisions?
    /// The merged bytes, when `status` is `merged`.
    public internal(set) var result: [UInt8]?
    /// Why the merge failed or is unsupported.
    public internal(set) var error: String?
    /// Every path the replay took to theirs' membership, for the re-check.
    var replayedPaths: [String] = []

    init(status: Status, inputs: MergeDecisions.Inputs) {
        self.status = status
        self.inputs = inputs
    }
}

/// The pipeline of merge design D11, as a pure function of three inputs.
public struct MergeEngine {
    /// `lint.exempt` of the configuration, honoured by check A and by the
    /// replay's `add` (an M3-exempt path gets no group child).
    public var exemptions: Exemptions?
    public var decisions: MergeDecisions?
    var faults: MergeFaults = []
    var minter = IDMinter()

    public init(exemptions: Exemptions? = nil, decisions: MergeDecisions? = nil) {
        self.exemptions = exemptions
        self.decisions = decisions
    }

    public func run(base baseBytes: [UInt8], ours oursBytes: [UInt8], theirs theirsBytes: [UInt8]) -> MergeReport {
        let inputs = MergeDecisions.Inputs(base: baseBytes, ours: oursBytes, theirs: theirsBytes)
        var report = MergeReport(status: .merged, inputs: inputs)
        func stop(_ status: MergeReport.Status, _ error: String) -> MergeReport {
            report.status = status
            report.error = error
            return report
        }
        if let decisions, decisions.inputs != inputs { return stop(.unsupported, MergeDecisionsError.otherInputs.description) }

        // Inputs that do not load, and targets that appear or vanish.
        var loaded: [Project] = []
        for (name, bytes) in [("base", baseBytes), ("ours", oursBytes), ("theirs", theirsBytes)] {
            do {
                loaded.append(try Project.load(bytes))
            } catch {
                return stop(.unsupported, "\(name): \(error)")
            }
        }
        let (base, ours, theirs) = (loaded[0], loaded[1], loaded[2])
        // Identical sides merge to ours whatever they did to the targets.
        if oursBytes == theirsBytes {
            report.nothingToMerge = true
            report.result = oursBytes
            return report
        }
        if let problem = MergeEngine.targetProblem(base: base, ours: ours, theirs: theirs) { return stop(.unsupported, problem) }

        // Units and classification.
        let (baseSnapshot, oursSnapshot, theirsSnapshot) = (MembershipSnapshot(base), MembershipSnapshot(ours), MembershipSnapshot(theirs))
        let units = MergeUnit.discover(base: baseSnapshot, ours: oursSnapshot, theirs: theirsSnapshot,
                                       rowsOnly: faults.contains(.skipStructuralDiscovery))
        let collisions = baseSnapshot.collisions.union(oursSnapshot.collisions).union(theirsSnapshot.collisions)
        if let path = units.flatMap(\.paths).first(where: collisions.contains) {
            return stop(.unsupported, "\(path): two file references resolve there in one version (M4); the merge cannot say which one it means")
        }
        let classified = ClassifiedUnit.classify(units, base: baseSnapshot, ours: ours, oursSnapshot: oursSnapshot, theirs: theirsSnapshot,
                                                 exemptions: exemptions, minter: minter)

        // Neutralisation and the line merge.
        let unitPaths = units.flatMap(\.paths)
        let neutralBase: Project
        let neutralTheirs: Project
        let kept = Neutralise.keptGroups(base: base, theirs: theirs, paths: unitPaths)
        do {
            let presence = !faults.contains(.skipPresenceFilter)
            neutralBase = try Neutralise.run(base, paths: unitPaths, presenceFilter: presence, keeping: kept)
            neutralTheirs = try Neutralise.run(theirs, paths: unitPaths, presenceFilter: presence, keeping: kept)
        } catch {
            return stop(.failed, "neutralisation failed, which is a defect: \(error)")
        }
        let merge = ThreeWay.merge(base: TextLines.split(neutralBase.serialize()), ours: TextLines.split(oursBytes),
                                   theirs: TextLines.split(neutralTheirs.serialize()))
        let analysed: [AnalysedHunk]
        do {
            analysed = try AnalysedHunk.analyse(merge)
        } catch {
            return stop(.unsupported, "\(error)")
        }

        // Decisions: validate, then report whatever is still open.
        var unitChoices: [String: UnitChoice] = [:]
        var hunkChoices: [String: HunkChoice] = [:]
        if let decisions {
            let openUnits = Dictionary(uniqueKeysWithValues: classified.filter { $0.outcome == .decision }.map { ($0.unit.key, $0) })
            for (key, choice) in decisions.units.sorted(by: { $0.key < $1.key }) {
                guard let unit = openUnits[key] else { return stop(.unsupported, MergeDecisionsError.unknownKey(key).description) }
                guard let choice else { continue }
                guard let parsed = UnitChoice(rawValue: choice), unit.choices.contains(parsed) else {
                    return stop(.unsupported, MergeDecisionsError.refusedChoice(key: key, choice: choice, offered: unit.choices.map(\.rawValue)).description)
                }
                unitChoices[key] = parsed
            }
            let openHunks = Dictionary(uniqueKeysWithValues: analysed.map { ($0.key, $0) })
            for (key, choice) in decisions.hunks.sorted(by: { $0.key < $1.key }) {
                guard let hunk = openHunks[key] else { return stop(.unsupported, MergeDecisionsError.unknownKey(key).description) }
                guard let choice else { continue }
                guard let parsed = HunkChoice(rawValue: choice), hunk.choices.contains(parsed) else {
                    return stop(.unsupported, MergeDecisionsError.refusedChoice(key: key, choice: choice, offered: hunk.choices.map(\.rawValue)).description)
                }
                hunkChoices[key] = parsed
            }
        }
        report.units = classified.map { MergeReport.UnitEntry(classified: $0, decision: unitChoices[$0.unit.key], changes: []) }
        report.hunks = analysed.map { MergeReport.HunkEntry(analysed: $0, decision: hunkChoices[$0.key]) }
        if report.units.contains(where: \.isOpen) || report.hunks.contains(where: { $0.decision == nil }) {
            var template = MergeDecisions(inputs: inputs)
            for unit in report.units where unit.classified.outcome == .decision { template.units[unit.key] = .some(unit.decision?.rawValue) }
            for hunk in report.hunks { template.hunks[hunk.key] = .some(hunk.decision?.rawValue) }
            report.template = template
            report.status = .decisionsNeeded
            return report
        }

        // The text-merged project, and the checks on it.
        let decided = report.hunks.compactMap { entry in entry.decision.map { DecidedHunk(hunk: entry.analysed, choice: $0) } }
        let preBytes = faults.contains(.skipTextMerge)
            ? oursBytes : merge.text { index, _ in decided[index].hunk.resolution(decided[index].choice) }
        let pre: Project
        do {
            pre = try Project.load(preBytes)
        } catch {
            return stop(.failed, "the merged text is not a project: \(error)")
        }
        func run(_ check: CheckResult) -> Bool {
            report.checks.append(check)
            if !check.passed { report.status = .failed }
            return check.passed
        }
        guard run(MergeChecks.accounting(base: neutralBase, ours: ours, theirs: neutralTheirs, result: pre, hunks: decided, faults: faults)),
              run(MergeChecks.noMembershipAsBytes(ours: oursSnapshot, result: MembershipSnapshot(pre)))
        else { return report }

        // The replay, unit by unit.
        var result = pre
        var replayed: [String] = []
        for index in report.units.indices {
            let entry = report.units[index]
            let replay = entry.classified.outcome == .replayed || entry.decision == .theirs || entry.decision == .theirsMembership
            guard replay else { continue }
            if entry.decision == .theirsMembership { report.owed += entry.classified.residuals }
            do {
                let outcome = try Replay.run(paths: entry.classified.unit.paths, current: result, theirs: theirsSnapshot, exemptions: exemptions,
                                             minter: minter, removeAll: faults.contains(.replayRemoveAll), keeping: kept)
                result = outcome.project
                report.units[index].changes = outcome.changes
            } catch {
                return stop(.failed, "unit \(entry.key) (\(entry.classified.unit.paths.joined(separator: ", "))): the replay was refused: \(error)")
            }
            replayed += entry.classified.unit.paths
        }

        report.replayedPaths = replayed

        // The checks on the result.
        let resultSnapshot = MembershipSnapshot(result)
        guard run(MergeChecks.isolation(pre: pre, result: result, replayedPaths: replayed, keeping: kept)),
              run(MergeChecks.perPath(paths: replayed, base: baseSnapshot, ours: oursSnapshot, theirs: theirsSnapshot, result: resultSnapshot,
                                      owed: report.owed)),
              run(MergeChecks.membership(ours: oursSnapshot, theirs: theirsSnapshot, result: resultSnapshot, theirsPaths: Set(replayed),
                                         owed: report.owed))
        else { return report }
        let findings = MergeChecks.findings(result: result, ours: ours, theirs: theirs, exemptions: exemptions)
        report.findings = findings.new
        guard run(findings.check) else { return report }
        report.result = result.serialize()
        return report
    }

    /// Design D11: the bytes read back after the write, re-parsed, with
    /// checks A and B run again. `nil` when they pass.
    public func recheck(written: [UInt8], ours oursBytes: [UInt8], theirs theirsBytes: [UInt8], report: MergeReport) -> CheckResult? {
        let failure = { (message: String) in CheckResult(check: .A, problems: [CheckProblem(object: nil, subject: "the written file", message: message)]) }
        guard written == report.result else { return failure("the bytes read back differ from the bytes written") }
        guard let result = try? Project.load(written), let ours = try? Project.load(oursBytes), let theirs = try? Project.load(theirsBytes) else {
            return failure("the bytes read back do not load as a project")
        }
        let findings = MergeChecks.findings(result: result, ours: ours, theirs: theirs, exemptions: exemptions).check
        if !findings.passed { return findings }
        let membership = MergeChecks.membership(ours: MembershipSnapshot(ours), theirs: MembershipSnapshot(theirs), result: MembershipSnapshot(result),
                                                theirsPaths: Set(report.replayedPaths), owed: report.owed)
        return membership.passed ? nil : membership
    }

    /// Spec: Unsupported inputs. Targets are matched by name; a target only
    /// ours added is supported.
    static func targetProblem(base: Project, ours: Project, theirs: Project) -> String? {
        let names = { (project: Project) in Set(project.targets.map { $0.name ?? $0.id.rawValue }) }
        let (b, o, t) = (names(base), names(ours), names(theirs))
        if let added = t.subtracting(b).sorted().first {
            return "theirs adds the target \(added); the merge never creates a target: add it on ours first"
        }
        if let removed = b.subtracting(t).sorted().first {
            return "theirs removes the target \(removed); the merge never deletes a target: remove it on ours first"
        }
        if let removed = b.subtracting(o).sorted().first {
            return "ours removes the target \(removed); the merge never deletes a target"
        }
        return nil
    }
}
