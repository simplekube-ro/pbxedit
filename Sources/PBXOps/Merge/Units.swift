import CryptoKit
import PBXModel

/// Paths whose membership theirs changed, linked by object identity (merge
/// design D3): both ends of a rename are one unit.
public struct MergeUnit: Equatable, Sendable {
    /// `u` + 12 hex characters, from the paths and the three versions' masked state.
    public let key: String
    /// Sorted.
    public let paths: [String]

    public init(key: String, paths: [String]) {
        self.key = key
        self.paths = paths
    }

    /// Design D3. With `rowsOnly` (the `skipStructuralDiscovery` fault) a
    /// path counts as changed only when its rows or build files do.
    public static func discover(base: MembershipSnapshot, ours: MembershipSnapshot, theirs: MembershipSnapshot,
                                rowsOnly: Bool = false) -> [MergeUnit] {
        let candidates = Set(base.references.keys).union(theirs.references.keys)
        let changed = candidates.filter { path in
            let (before, after) = (base.references[path], theirs.references[path])
            let buildFilesDiffer = Set(before?.buildFiles ?? []) != Set(after?.buildFiles ?? [])
            if rowsOnly {
                return (before?.masked.rows ?? []) != (after?.masked.rows ?? []) || buildFilesDiffer
            }
            // A second reference at the path (M4) is a change too: the merge then refuses the unit.
            return before?.masked != after?.masked || before?.id != after?.id || buildFilesDiffer
                || base.idsByPath[path] != theirs.idsByPath[path]
        }
        guard !changed.isEmpty else { return [] }

        // Union–find over every path of every version, joined by shared IDs.
        var sets = DisjointSets()
        for snapshot in [base, ours, theirs] {
            for reference in snapshot.byID.values {
                sets.union(id: reference.id, path: reference.resolvedPath)
                for buildFile in reference.buildFiles { sets.union(id: buildFile, path: reference.resolvedPath) }
            }
        }
        var components: [String: Set<String>] = [:]
        for path in sets.paths {
            components[sets.root(of: path), default: []].insert(path)
        }
        var units: [MergeUnit] = []
        var claimed: Set<String> = []
        for path in changed.sorted(by: MergeUnit.precedes) where !claimed.contains(path) {
            let members = sets.contains(path) ? components[sets.root(of: path)] ?? [path] : [path]
            let sorted = members.sorted(by: MergeUnit.precedes)
            claimed.formUnion(sorted)
            units.append(MergeUnit(key: key(for: sorted, base: base, ours: ours, theirs: theirs), paths: sorted))
        }
        return units.sorted { MergeUnit.precedes($0.paths[0], $1.paths[0]) }
    }

    static func precedes(_ lhs: String, _ rhs: String) -> Bool { lhs.utf8.lexicographicallyPrecedes(rhs.utf8) }

    /// Design D3: SHA-256 over the sorted paths and each version's masked
    /// state there, canonically encoded; IDs never enter it.
    static func key(for paths: [String], base: MembershipSnapshot, ours: MembershipSnapshot, theirs: MembershipSnapshot) -> String {
        var text = ""
        for path in paths {
            text += "path\u{1}\(path)\u{2}"
            for snapshot in [base, ours, theirs] { text += encode(snapshot.masked(at: path)) + "\u{2}" }
        }
        return "u" + MergeHash.prefix(of: text)
    }

    static func encode(_ state: MembershipSnapshot.MaskedState?) -> String {
        guard let state else { return "-" }
        let rows = state.rows.map { row in
            [row.target, row.phase.rawValue, row.filters.joined(separator: ","), row.settings?.description ?? "-"].joined(separator: "\u{3}")
        }
        return [state.path ?? "-", state.name ?? "-", state.sourceTree, state.groupPaths.joined(separator: "\u{3}"),
                rows.joined(separator: "\u{4}")].joined(separator: "\u{5}")
    }
}

/// The hashes keys are made of.
enum MergeHash {
    /// Lower-case hex of SHA-256.
    static func hex(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: bytes).map { byte in
            let digits = Array("0123456789abcdef")
            return String([digits[Int(byte >> 4)], digits[Int(byte & 0xF)]])
        }.joined()
    }

    /// The first 12 hex characters of SHA-256 over the UTF-8 of `text`.
    static func prefix(of text: String) -> String { String(hex(Array(text.utf8)).prefix(12)) }
}

/// Paths joined whenever one ID is seen at both.
private struct DisjointSets {
    private var parent: [String: String] = [:]
    private var pathOfID: [ObjectID: String] = [:]

    var paths: Dictionary<String, String>.Keys { parent.keys }

    func contains(_ path: String) -> Bool { parent[path] != nil }

    mutating func union(id: ObjectID, path: String) {
        if parent[path] == nil { parent[path] = path }
        if let other = pathOfID[id] {
            let (a, b) = (root(of: path), root(of: other))
            if a != b { parent[a] = b }
        } else {
            pathOfID[id] = path
        }
    }

    func root(of path: String) -> String {
        var current = path
        while let next = parent[current], next != current { current = next }
        return current
    }
}

/// A choice for a unit (spec: Each unit is replayed, skipped or decided).
public enum UnitChoice: String, Equatable, Sendable, CaseIterable {
    case ours
    case theirs
    case theirsMembership = "theirs-membership"
}

/// A unit and what the merge does with it (merge design D4).
public struct ClassifiedUnit: Equatable, Sendable {
    public enum Outcome: String, Equatable, Sendable {
        /// Only theirs changed it; the replay reproduces theirs.
        case replayed
        /// Ours already holds theirs' membership.
        case skipped
        /// Needs a choice.
        case decision
    }

    /// One path of the unit in the three versions; `nil` where no managed reference resolves there.
    public struct PathStates: Equatable, Sendable {
        public let path: String
        public let base: MembershipSnapshot.MaskedState?
        public let ours: MembershipSnapshot.MaskedState?
        public let theirs: MembershipSnapshot.MaskedState?
    }

    public let unit: MergeUnit
    public let outcome: Outcome
    /// Empty unless `outcome` is `decision`; `ours` always first.
    public let choices: [UnitChoice]
    /// What the trial replay could not reproduce of theirs.
    public let residuals: [Residual]
    /// Why the replay cannot run at all, when it cannot.
    public let reason: String?
    public let states: [PathStates]

    /// Design D4: compare masked membership; for a replay candidate and a
    /// decision, run the trial against ours to find residuals.
    /// `ignoringConflicts` is the fault seam of design D4 (issue #20): the
    /// classification of 1.1.2, which does not see a conflicting attribute.
    public static func classify(_ units: [MergeUnit], base: MembershipSnapshot, ours: Project, oursSnapshot: MembershipSnapshot,
                                theirs: MembershipSnapshot, exemptions: Exemptions? = nil, minter: IDMinter = IDMinter(),
                                removeAll: Bool = false, ignoringConflicts: Bool = false) -> [ClassifiedUnit] {
        units.map { unit in
            let states = unit.paths.map {
                PathStates(path: $0, base: base.masked(at: $0), ours: oursSnapshot.masked(at: $0), theirs: theirs.masked(at: $0))
            }
            let owing = { (residuals: [Residual]) in
                ClassifiedUnit(unit: unit, outcome: .decision, choices: [.ours, .theirsMembership], residuals: residuals, reason: nil,
                               states: states)
            }
            // Issue #20: a conflicting attribute is asked about even where
            // ours already holds theirs' membership, which the skip below
            // compares without attributes.
            if states.allSatisfy({ $0.ours == $0.theirs }) {
                let conflicts = ignoringConflicts ? []
                    : PathComparison.conflicts(paths: unit.paths, base: base, ours: oursSnapshot, theirs: theirs)
                return conflicts.isEmpty
                    ? ClassifiedUnit(unit: unit, outcome: .skipped, choices: [], residuals: [], reason: nil, states: states)
                    : owing(conflicts)
            }
            let candidate = states.allSatisfy { $0.ours == $0.base }
            let trial = Trial.run(paths: unit.paths, base: base, ours: ours, oursSnapshot: oursSnapshot, theirs: theirs,
                                  exemptions: exemptions, minter: minter, removeAll: removeAll)
            switch trial {
            case .failed(let reason):
                return ClassifiedUnit(unit: unit, outcome: .decision, choices: [.ours], residuals: [], reason: reason, states: states)
            case .replayed(let found):
                let residuals = ignoringConflicts ? found.filter { !$0.conflicting } : found
                guard residuals.isEmpty else { return owing(residuals) }
                return candidate
                    ? ClassifiedUnit(unit: unit, outcome: .replayed, choices: [], residuals: [], reason: nil, states: states)
                    : ClassifiedUnit(unit: unit, outcome: .decision, choices: [.ours, .theirs], residuals: [], reason: nil, states: states)
            }
        }
    }
}
