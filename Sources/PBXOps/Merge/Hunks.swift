import PBXSyntax
import PBXModel

/// A choice for a hunk (spec: Everything else is merged as text).
public enum HunkChoice: String, Equatable, Hashable, Sendable, CaseIterable {
    case ours, theirs, both
}

/// A hunk whose `ours` or `theirs` resolution does not make a project
/// (spec: Unsupported inputs). `hunk` counts from 1 in file order.
public enum HunkError: Error, Equatable, CustomStringConvertible {
    case unparseable(hunk: Int, side: HunkChoice, message: String)

    public var description: String {
        switch self {
        case .unparseable(let hunk, let side, let message):
            return "hunk \(hunk): the text with \(side.rawValue) does not load as a project: \(message)"
        }
    }
}

/// A conflicting hunk and what it governs (merge design D7).
public struct AnalysedHunk: Equatable, Sendable {
    /// One governed leaf in the three counterfactual texts; `nil` for absent.
    public struct Values: Equatable, Sendable {
        public let path: LeafPath
        public let base: PlistValue?
        public let ours: PlistValue?
        public let theirs: PlistValue?
    }

    /// 1-based, in file order.
    public let number: Int
    /// `h` + 12 hex, with `-2`, `-3` for a later hunk whose key would repeat.
    public let key: String
    public let hunk: ThreeWay.Hunk
    /// The `(object ID, key path)` pairs either side changes, sorted.
    public let governed: [LeafPath]
    public let oursTouched: Set<LeafPath>
    public let theirsTouched: Set<LeafPath>
    public let values: [Values]
    /// `ours`, `theirs`, and `both` when both may be taken.
    public let choices: [HunkChoice]
    /// The merge the hunk belongs to, for its counterfactual texts.
    let merge: ThreeWay.Merge

    /// The lines a choice puts in place of the hunk.
    public func resolution(_ choice: HunkChoice) -> [[UInt8]] {
        switch choice {
        case .ours: return hunk.ours
        case .theirs: return hunk.theirs
        case .both: return hunk.ours + hunk.theirs
        }
    }

    /// The whole text with every other hunk resolved `ours` and this one by `choice`.
    public func counterfactual(_ choice: HunkChoice) -> [UInt8] {
        AnalysedHunk.text(merge, index: number - 1, lines: resolution(choice))
    }

    static func text(_ merge: ThreeWay.Merge, index: Int, lines: [[UInt8]]) -> [UInt8] {
        merge.text { i, hunk in i == index ? lines : hunk.ours }
    }

    /// Design D7, for every hunk of `merge`. Throws `HunkError` when an
    /// `ours` or `theirs` counterfactual does not parse and load.
    public static func analyse(_ merge: ThreeWay.Merge) throws -> [AnalysedHunk] {
        var result: [AnalysedHunk] = []
        var keys: [String: Int] = [:]
        for (index, hunk) in merge.hunks.enumerated() {
            let number = index + 1
            func load(_ lines: [[UInt8]], _ side: HunkChoice) throws -> SyntaxTree {
                let bytes = text(merge, index: index, lines: lines)
                do {
                    let project = try Project.load(bytes)
                    return project.tree
                } catch {
                    throw HunkError.unparseable(hunk: number, side: side, message: "\(error)")
                }
            }
            let ours = try load(hunk.ours, .ours)
            let theirs = try load(hunk.theirs, .theirs)
            let (oursLeaves, theirsLeaves) = (PlistLeaves(ours), PlistLeaves(theirs))
            let baseTree = try? load(hunk.base, .ours)
            let baseLeaves = baseTree.map(PlistLeaves.init)

            let oursTouched: Set<LeafPath>
            let theirsTouched: Set<LeafPath>
            if let baseLeaves {
                oursTouched = difference(baseLeaves, oursLeaves)
                theirsTouched = difference(baseLeaves, theirsLeaves)
            } else {
                // No base to compare with: everything the sides disagree on, owned by both.
                oursTouched = difference(oursLeaves, theirsLeaves)
                theirsTouched = oursTouched
            }
            let governed = oursTouched.union(theirsTouched).sorted()
            let values = governed.map { Values(path: $0, base: baseLeaves?[$0], ours: oursLeaves[$0], theirs: theirsLeaves[$0]) }

            var choices: [HunkChoice] = [.ours, .theirs]
            if let baseLeaves, let baseTree, oursTouched.isDisjoint(with: theirsTouched),
               let both = try? load(hunk.ours + hunk.theirs, .both) {
                var expected = baseLeaves.values
                for path in oursTouched { expected[path] = oursLeaves[path] }
                for path in theirsTouched { expected[path] = theirsLeaves[path] }
                if PlistLeaves(both).values == expected,
                   PlistValue.duplicateKeyCount(in: both.root) <= PlistValue.duplicateKeyCount(in: baseTree.root) {
                    choices.append(.both)
                }
            }

            var keyText = ""
            for lines in [hunk.base, hunk.ours, hunk.theirs] {
                keyText += String(decoding: TextLines.join(lines), as: UTF8.self) + "\u{1}"
            }
            let objects = Set(governed.compactMap(\.objectID)).sorted()
            keyText += objects.map(\.rawValue).joined(separator: "\u{2}")
            var key = "h" + MergeHash.prefix(of: keyText)
            if let seen = keys[key] {
                keys[key] = seen + 1
                key += "-\(seen + 1)"
            } else {
                keys[key] = 1
            }
            result.append(AnalysedHunk(number: number, key: key, hunk: hunk, governed: governed, oursTouched: oursTouched,
                                       theirsTouched: theirsTouched, values: values, choices: choices, merge: merge))
        }
        return result
    }

    /// The leaves whose value differs, or that only one side has.
    static func difference(_ lhs: PlistLeaves, _ rhs: PlistLeaves) -> Set<LeafPath> {
        var result: Set<LeafPath> = []
        for (path, value) in lhs.values where rhs.values[path] != value { result.insert(path) }
        for path in rhs.values.keys where lhs.values[path] == nil { result.insert(path) }
        return result
    }
}
