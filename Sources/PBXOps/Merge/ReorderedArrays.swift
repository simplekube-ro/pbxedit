import PBXModel

/// Issue #32 (change `merge-reorder-whole-array`, design D2): the arrays the
/// line merge keeps in one hunk. Where ours and theirs both change an array
/// and order the elements they both hold differently, no result honours both
/// orders (check C's array rule), and a line merge that splits the array lets
/// a hunk's `theirs` keep half of ours' move — a clean deletion — and drop an
/// element every side holds. Kept whole, the hunk's `ours` and `theirs` are
/// each side's whole array.
enum ReorderedArrays {
    /// The base lines of every array reached by keys that ours and theirs
    /// both change and whose shared elements they order differently. The
    /// three projects are the ones the line merge reads.
    static func spans(base: Project, ours: Project, theirs: Project) -> [Range<Int>] {
        let arrays = base.tree.arrayLines()
        guard !arrays.isEmpty else { return [] }
        let (b, o, t) = (PlistLeaves(base), PlistLeaves(ours), PlistLeaves(theirs))
        var seen: Set<LeafPath> = []
        var spans: [Range<Int>] = []
        for (keys, lines) in arrays {
            // A repeated key: the leaves, like every lookup, read the first.
            let path = LeafPath(keys)
            guard seen.insert(path).inserted, case .array(let was)? = b[path], case .array(let mine)? = o[path],
                  case .array(let yours)? = t[path], mine != was, yours != was,
                  !UnorderedInsertions.ordersAgree(mine, yours)
            else { continue }
            spans.append(lines)
        }
        return spans
    }
}
