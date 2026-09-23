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
    /// The lines `both` resolves to — the first form that qualified (change
    /// `merge-both-multiline-objects`, design D3, D4) — and `nil` when
    /// neither did, in which case `choices` holds no `both`.
    public let bothLines: [[UInt8]]?
    /// The merge the hunk belongs to, for its counterfactual texts.
    let merge: ThreeWay.Merge

    /// The lines a choice puts in place of the hunk.
    public func resolution(_ choice: HunkChoice) -> [[UInt8]] {
        switch choice {
        case .ours: return hunk.ours
        case .theirs: return hunk.theirs
        case .both: return bothLines ?? hunk.ours + hunk.theirs
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
        var theirsVersion: PlistValue??
        /// The text with every hunk `theirs`, loaded once when needed; `nil` when it does not load.
        func allTheirs() -> PlistValue? {
            if theirsVersion == nil {
                theirsVersion = .some((try? Project.load(merge.text { $1.theirs })).map { PlistValue($0.tree.root) })
            }
            return theirsVersion ?? nil
        }
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
            // The base's counterfactual replaces the hunk's whole stretch, so that a base
            // the trimming's frame is no part of still loads (design D2).
            let baseTree = try? Project.load(merge.text(replacingStretchOf: index, with: hunk.stretchBase)).tree
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
            var bothLines: [[UInt8]]?
            let shared = oursTouched.intersection(theirsTouched)
            if let baseLeaves, let baseTree,
               shared.isEmpty || UnorderedInsertions.admits(shared, base: PlistValue(baseTree.root), ours: PlistValue(ours.root),
                                                            theirs: PlistValue(theirs.root), theirsVersion: allTheirs) {
                // Leaves one side changes take its value; a shared array passes check C's array rule.
                var expected = baseLeaves.values
                for path in oursTouched { expected[path] = oursLeaves[path] }
                for path in theirsTouched { expected[path] = theirsLeaves[path] }
                for path in shared { expected[path] = nil }
                for lines in bothCandidates(hunk) {
                    guard let both = try? load(lines, .both) else { continue }
                    var actual = PlistLeaves(both).values
                    let arraysMerge = shared.allSatisfy { path in
                        guard case .array(let was)? = baseLeaves[path], case .array(let mine)? = oursLeaves[path],
                              case .array(let yours)? = theirsLeaves[path], case .array(let got)? = actual.removeValue(forKey: path)
                        else { return false }
                        return MergeChecks.arrayProblem(base: was, ours: mine, theirs: yours, result: got, unordered: false) == nil
                    }
                    if arraysMerge, actual == expected,
                       PlistValue.duplicateKeyCount(in: both.root) <= PlistValue.duplicateKeyCount(in: baseTree.root) {
                        choices.append(.both)
                        bothLines = lines
                        break
                    }
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
                                       theirsTouched: theirsTouched, values: values, choices: choices, bothLines: bothLines,
                                       merge: merge))
        }
        return result
    }

    /// Design D3: the forms `both` may take, in the order they are tried.
    /// The trimmed `ours + theirs` first, so a `both` that qualified before
    /// this change keeps its lines; then ours' untrimmed text followed by
    /// theirs', which inside the trimmed frame is `ours + after + before +
    /// theirs` — the context trimming lifted out, written once between the
    /// two sides. A hunk trimming did not cut has the one form.
    static func bothCandidates(_ hunk: ThreeWay.Hunk) -> [[[UInt8]]] {
        let trimmed = hunk.ours + hunk.theirs
        let untrimmed = hunk.ours + hunk.after + hunk.before + hunk.theirs
        return untrimmed == trimmed ? [trimmed] : [trimmed, untrimmed]
    }

    /// The leaves whose value differs, or that only one side has.
    static func difference(_ lhs: PlistLeaves, _ rhs: PlistLeaves) -> Set<LeafPath> {
        var result: Set<LeafPath> = []
        for (path, value) in lhs.values where rhs.values[path] != value { result.insert(path) }
        for path in rhs.values.keys where lhs.values[path] == nil { result.insert(path) }
        return result
    }
}
