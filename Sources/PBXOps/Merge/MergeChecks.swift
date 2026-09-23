import PBXSyntax
import PBXModel

/// The checks of merge design D9. Each is a pure function over `Project`
/// values; the first that fails ends the run with exit `1`, naming every
/// failing object and key.
public enum MergeCheck: String, CaseIterable, Equatable, Sendable {
    case A, B, C, D, E, F

    public var title: String {
        switch self {
        case .A: return "no new finding"
        case .B: return "membership"
        case .C: return "accounting"
        case .D: return "replay isolation"
        case .E: return "per path"
        case .F: return "no membership as bytes"
        }
    }
}

/// One failing object and key of a check.
public struct CheckProblem: Equatable, Sendable, CustomStringConvertible {
    public let object: ObjectID?
    /// `<ID> buildSettings.SWIFT_VERSION`, a path, or a target.
    public let subject: String
    public let message: String

    public init(object: ObjectID?, subject: String, message: String) {
        self.object = object
        self.subject = subject
        self.message = message
    }

    public var description: String { "\(subject): \(message)" }
}

public struct CheckResult: Equatable, Sendable {
    public let check: MergeCheck
    public let problems: [CheckProblem]

    public var passed: Bool { problems.isEmpty }

    public init(check: MergeCheck, problems: [CheckProblem]) {
        self.check = check
        self.problems = problems
    }
}

/// The fault seam of design D9: each option disables the step a check
/// guards, so the check's Red test can prove it bites. Reachable only
/// through `@testable import`; not a flag, not an environment variable.
struct MergeFaults: OptionSet, Sendable {
    let rawValue: Int
    /// The text-merged project is ours.
    static let skipTextMerge = MergeFaults(rawValue: 1 << 0)
    /// Units from rows only: reference-only changes travel as text.
    static let skipStructuralDiscovery = MergeFaults(rawValue: 1 << 1)
    /// Every unit path is neutralised in both copies, held or not.
    static let skipPresenceFilter = MergeFaults(rawValue: 1 << 2)
    /// Check C stops at each object's attributes: a dictionary is one leaf.
    static let wholeDictionaryLeaves = MergeFaults(rawValue: 1 << 3)
    /// Check C compares arrays without their order.
    static let multisetArrays = MergeFaults(rawValue: 1 << 4)
    /// The replay removes every path and adds it back.
    static let replayRemoveAll = MergeFaults(rawValue: 1 << 5)
}

/// A hunk and the choice that resolved it.
public struct DecidedHunk: Equatable, Sendable {
    public let hunk: AnalysedHunk
    public let choice: HunkChoice

    public init(hunk: AnalysedHunk, choice: HunkChoice) {
        self.hunk = hunk
        self.choice = choice
    }
}

public enum MergeChecks {
    // MARK: C — accounting

    /// Design D9 C over the neutralised base, ours, the neutralised theirs
    /// and the text-merged result.
    public static func accounting(base: Project, ours: Project, theirs: Project, result: Project, hunks: [DecidedHunk]) -> CheckResult {
        accounting(base: base, ours: ours, theirs: theirs, result: result, hunks: hunks, faults: [])
    }

    static func accounting(base: Project, ours: Project, theirs: Project, result: Project, hunks: [DecidedHunk], faults: MergeFaults) -> CheckResult {
        let depth = faults.contains(.wholeDictionaryLeaves) ? 3 : nil
        let (b, o, t, r) = (PlistLeaves(base.tree, depth: depth), PlistLeaves(ours.tree, depth: depth),
                            PlistLeaves(theirs.tree, depth: depth), PlistLeaves(result.tree, depth: depth))
        let unordered = faults.contains(.multisetArrays)
        var decided: [LeafPath: PlistValue?] = [:]
        for decision in hunks where decision.choice != .both {
            for values in decision.hunk.values {
                decided.updateValue(decision.choice == .ours ? values.ours : values.theirs, forKey: values.path)
            }
        }
        var problems: [CheckProblem] = []
        var paths: [LeafPath] = []
        var seen: Set<LeafPath> = []
        for leaves in [o, t, b, r] {
            for path in leaves.paths where seen.insert(path).inserted { paths.append(path) }
        }
        for path in paths {
            let (was, mine, yours, got) = (b[path], o[path], t[path], r[path])
            func same(_ lhs: PlistValue?, _ rhs: PlistValue?) -> Bool {
                unordered ? multiset(lhs) == multiset(rhs) && kind(lhs) == kind(rhs) : lhs == rhs
            }
            let oursChanged = !same(mine, was)
            let theirsChanged = !same(yours, was)
            let problem: String?
            if let expected = decided[path] {
                // A decided hunk governs the leaf, whoever changed it.
                problem = same(got, expected) ? nil : "the decided hunk gives \(show(expected)); the merge has \(show(got))"
            } else if theirsChanged && !oursChanged {
                problem = same(got, yours) ? nil : "theirs changed it to \(show(yours)); the merge has \(show(got))"
            } else if !theirsChanged || same(mine, yours) {
                problem = same(got, mine) ? nil : "expected ours' \(show(mine)); the merge has \(show(got))"
            } else if case .array(let wasArray)? = was, case .array(let mineArray)? = mine, case .array(let yoursArray)? = yours,
                      case .array(let gotArray)? = got {
                problem = arrayProblem(base: wasArray, ours: mineArray, theirs: yoursArray, result: gotArray, unordered: unordered)
            } else {
                problem = "both sides changed it (ours \(show(mine)), theirs \(show(yours))) and no decided hunk governs it"
            }
            if let problem { problems.append(CheckProblem(object: path.objectID, subject: path.description, message: problem)) }
        }
        return CheckResult(check: .C, problems: problems)
    }

    // MARK: F — no membership as bytes

    /// Design D9 F: between ours and the text-merged result, the managed
    /// references by ID and their build files by ID are identical.
    public static func noMembershipAsBytes(ours: MembershipSnapshot, result: MembershipSnapshot) -> CheckResult {
        var problems: [CheckProblem] = []
        let ids = Set(ours.byID.keys).union(result.byID.keys).sorted()
        for id in ids {
            let (before, after) = (ours.byID[id], result.byID[id])
            guard let before, let after else {
                let path = (before ?? after)?.resolvedPath ?? ""
                let what = before == nil ? "appeared" : "disappeared"
                problems.append(CheckProblem(object: id, subject: "\(id) \(path)", message: "a managed file reference \(what) in the text merge"))
                continue
            }
            var changed: [String] = []
            if before.path != after.path { changed.append("path") }
            if before.name != after.name { changed.append("name") }
            if before.sourceTree != after.sourceTree { changed.append("sourceTree") }
            if before.resolvedPath != after.resolvedPath { changed.append("resolved path") }
            if before.parents != after.parents { changed.append("parents") }
            if before.buildFiles != after.buildFiles { changed.append("build files") }
            let rows = { (reference: MembershipSnapshot.Reference) in
                reference.rows.map { "\($0.buildFile) \($0.phaseID) \($0.filters)" }.sorted()
            }
            if rows(before) != rows(after) { changed.append("phases or platform filters") }
            if !changed.isEmpty {
                problems.append(CheckProblem(object: id, subject: "\(id) \(before.resolvedPath)",
                                             message: "the text merge changed its \(changed.joined(separator: ", "))"))
            }
        }
        return CheckResult(check: .F, problems: problems)
    }

    // MARK: D — replay isolation

    /// Design D9 D: removing every replayed path from the text-merged
    /// project and from the result gives the same project, by leaves.
    public static func isolation(pre: Project, result: Project, replayedPaths: [String], keeping: Set<ObjectID> = []) -> CheckResult {
        let problem = { (message: String) in CheckResult(check: .D, problems: [CheckProblem(object: nil, subject: "replayed paths", message: message)]) }
        let before: Project
        let after: Project
        do {
            before = try Neutralise.run(pre, paths: replayedPaths, keeping: keeping)
            after = try Neutralise.run(result, paths: replayedPaths, keeping: keeping)
        } catch {
            return problem("the replayed paths cannot be removed again: \(error)")
        }
        let (b, a) = (PlistLeaves(before), PlistLeaves(after))
        var problems: [CheckProblem] = []
        var seen: Set<LeafPath> = []
        for path in b.paths + a.paths where seen.insert(path).inserted && b[path] != a[path] {
            problems.append(CheckProblem(object: path.objectID, subject: path.description,
                                         message: "the replay changed it outside the replayed paths: \(show(b[path])) became \(show(a[path]))"))
        }
        return CheckResult(check: .D, problems: problems)
    }

    // MARK: E — per path

    /// Design D9 E: the trial's comparison on the result, for every replayed
    /// path; a difference other than an owed residual fails.
    public static func perPath(paths: [String], base: MembershipSnapshot, ours: MembershipSnapshot, theirs: MembershipSnapshot,
                               result: MembershipSnapshot, owed: [Residual]) -> CheckResult {
        let owedKeys = Set(owed.map { OwedKey(path: $0.path, kind: $0.kind) })
        let differences = PathComparison.compare(paths: paths, base: base, ours: ours, theirs: theirs, result: result)
        let problems = differences.filter { !owedKeys.contains(OwedKey(path: $0.path, kind: $0.kind)) }.map { residual in
            CheckProblem(object: residual.source ?? residual.object, subject: "\(residual.path) \(residual.kind)", message: residual.description)
        }
        return CheckResult(check: .E, problems: problems)
    }

    private struct OwedKey: Hashable {
        let path: String
        let kind: Residual.Kind
    }

    // MARK: B — membership

    /// Design D9 B: per target, the result's managed rows without IDs equal
    /// ours' with the rows at every path of `theirsPaths` taken from theirs.
    /// A path with owed settings compares its rows without settings; one
    /// whose rows or reference are owed is not compared.
    public static func membership(ours: MembershipSnapshot, theirs: MembershipSnapshot, result: MembershipSnapshot, theirsPaths: Set<String>,
                                  owed: [Residual]) -> CheckResult {
        var withoutSettings: Set<String> = []
        var skipped: Set<String> = []
        for residual in owed {
            switch residual.kind {
            case .settings: withoutSettings.insert(residual.path)
            case .rows, .presence: skipped.insert(residual.path)
            default: break
            }
        }
        func rows(_ snapshot: MembershipSnapshot, _ include: (String) -> Bool) -> [String: [String]] {
            var byTarget: [String: [String]] = [:]
            for (path, reference) in snapshot.references where include(path) && !skipped.contains(path) {
                for row in reference.rows {
                    let masked = withoutSettings.contains(path)
                        ? MembershipSnapshot.MaskedRow(target: row.target, phase: row.phase, filters: row.filters, settings: nil) : row.masked
                    byTarget[row.target, default: []].append("\(path): \(masked)")
                }
            }
            return byTarget.mapValues { $0.sorted() }
        }
        var expected = rows(ours) { !theirsPaths.contains($0) }
        for (target, list) in rows(theirs, { theirsPaths.contains($0) }) {
            expected[target] = ((expected[target] ?? []) + list).sorted()
        }
        let actual = rows(result) { _ in true }
        var problems: [CheckProblem] = []
        for target in Set(expected.keys).union(actual.keys).sorted() {
            let (want, have) = (expected[target] ?? [], actual[target] ?? [])
            guard want != have else { continue }
            let missing = want.filter { !have.contains($0) }
            let extra = have.filter { !want.contains($0) }
            var parts: [String] = []
            if !missing.isEmpty { parts.append("missing \(missing.joined(separator: "; "))") }
            if !extra.isEmpty { parts.append("unexpected \(extra.joined(separator: "; "))") }
            if parts.isEmpty { parts.append("rows differ in multiplicity") }
            problems.append(CheckProblem(object: nil, subject: "target \(target)", message: parts.joined(separator: "; ")))
        }
        return CheckResult(check: .B, problems: problems)
    }

    // MARK: A — no new finding

    /// Design D9 A: the whole rule set over the result, warnings included,
    /// no disk rules; a finding ours or theirs also has is tolerated,
    /// matched by rule and path when it has a path, else by identity.
    public static func findings(result: Project, ours: Project, theirs: Project, exemptions: Exemptions?) -> (check: CheckResult, new: [Finding]) {
        func key(_ finding: Finding) -> String {
            if let path = finding.path { return "\(finding.rule.rawValue) \(path)" }
            let identity = finding.identity
            return "\(identity.rule.rawValue) \(identity.object?.rawValue ?? "-") \(identity.related.map(\.rawValue).joined(separator: ","))"
        }
        let tolerated = Set((RuleSet.standard.evaluate(ours, exemptions: exemptions) + RuleSet.standard.evaluate(theirs, exemptions: exemptions)).map(key))
        let new = RuleSet.standard.evaluate(result, exemptions: exemptions).filter { !tolerated.contains(key($0)) }
        let problems = new.map { CheckProblem(object: $0.object, subject: "\($0.rule.rawValue) \($0.object?.rawValue ?? $0.path ?? "")", message: $0.description) }
        return (CheckResult(check: .A, problems: problems), new)
    }

    /// Design D9: ours + (theirs' additions − ours' additions) − (theirs'
    /// removals − ours' removals), each side's retained elements in its order.
    static func arrayProblem(base: [PlistValue], ours: [PlistValue], theirs: [PlistValue], result: [PlistValue], unordered: Bool) -> String? {
        let (b, o, t) = (Multiset(base), Multiset(ours), Multiset(theirs))
        let expected = o + ((t - b) - (o - b)) - ((b - t) - (b - o))
        guard Multiset(result) == expected else {
            return "both sides changed the array; expected the elements \(show(.array(expected.sorted()))), the merge has \(show(.array(result)))"
        }
        guard !unordered else { return nil }
        for (name, side) in [("ours", ours), ("theirs", theirs)] {
            var kept = Multiset(side).intersection(Multiset(result))
            let retained = side.filter { kept.remove($0) }
            guard isSubsequence(retained, of: result) else {
                return "\(name)' order of \(show(.array(retained))) is lost in \(show(.array(result)))"
            }
        }
        return nil
    }

    static func isSubsequence(_ needle: [PlistValue], of haystack: [PlistValue]) -> Bool {
        var index = needle.startIndex
        for element in haystack where index < needle.endIndex && needle[index] == element { index += 1 }
        return index == needle.endIndex
    }

    private static func multiset(_ value: PlistValue?) -> Multiset? {
        guard case .array(let elements)? = value else { return nil }
        return Multiset(elements)
    }

    /// The value itself when it is not an array: arrays compare as multisets under the fault.
    private static func kind(_ value: PlistValue?) -> PlistValue? {
        if case .array? = value { return .array([]) }
        return value
    }

    static func show(_ value: PlistValue?) -> String { value?.description ?? "nothing" }
}

/// Counted elements, for the array rule of check C.
struct Multiset: Equatable {
    private(set) var counts: [PlistValue: Int] = [:]

    init(_ elements: [PlistValue] = []) {
        for element in elements { counts[element, default: 0] += 1 }
    }

    /// Removes one occurrence; whether there was one.
    mutating func remove(_ element: PlistValue) -> Bool {
        guard let count = counts[element], count > 0 else { return false }
        counts[element] = count == 1 ? nil : count - 1
        return true
    }

    func sorted() -> [PlistValue] {
        counts.flatMap { Array(repeating: $0.key, count: $0.value) }.sorted { $0.description.utf8.lexicographicallyPrecedes($1.description.utf8) }
    }

    static func + (lhs: Multiset, rhs: Multiset) -> Multiset {
        var result = lhs
        for (element, count) in rhs.counts { result.counts[element, default: 0] += count }
        return result
    }

    /// Saturating difference.
    static func - (lhs: Multiset, rhs: Multiset) -> Multiset {
        var result = lhs
        for (element, count) in rhs.counts {
            let remaining = (result.counts[element] ?? 0) - count
            result.counts[element] = remaining > 0 ? remaining : nil
        }
        return result
    }

    func intersection(_ other: Multiset) -> Multiset {
        var result = Multiset()
        for (element, count) in counts {
            let shared = min(count, other.counts[element] ?? 0)
            if shared > 0 { result.counts[element] = shared }
        }
        return result
    }
}
