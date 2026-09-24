/// Lines as the line merge sees them (merge design D6): byte runs ending in
/// `\n`, the last one possibly without.
public enum TextLines {
    public static func split(_ bytes: [UInt8]) -> [[UInt8]] {
        var lines: [[UInt8]] = []
        var start = 0
        for (index, byte) in bytes.enumerated() where byte == 0x0A {
            lines.append(Array(bytes[start...index]))
            start = index + 1
        }
        if start < bytes.count { lines.append(Array(bytes[start...])) }
        return lines
    }

    public static func join(_ lines: [[UInt8]]) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(lines.reduce(0) { $0 + $1.count })
        for line in lines { bytes.append(contentsOf: line) }
        return bytes
    }
}

/// Myers' O((N+M)·D) greedy line diff (merge design D6).
public enum LineDiff {
    /// A maximal run of base lines replaced by a run of the other side's
    /// lines; either may be empty, not both.
    public struct Change: Equatable, Sendable {
        public let base: Range<Int>
        public let other: Range<Int>

        public init(base: Range<Int>, other: Range<Int>) {
            self.base = base
            self.other = other
        }
    }

    /// Past this many differences the script is not refined further: the
    /// rest of the middle becomes one change. Correct, not minimal; it
    /// bounds the trace kept for backtracking to D² entries.
    static let maximumDifferences = 4_000

    public static func changes(from base: [[UInt8]], to other: [[UInt8]]) -> [Change] {
        var interner = Interner()
        return changes(interner.intern(base), interner.intern(other))
    }

    static func changes(_ a: [Int], _ b: [Int]) -> [Change] {
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        var endA = a.count
        var endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] {
            endA -= 1
            endB -= 1
        }
        let n = endA - start
        let m = endB - start
        if n == 0, m == 0 { return [] }
        if n == 0 || m == 0 { return [Change(base: start..<endA, other: start..<endB)] }

        // The forward pass, keeping each round's frontier for the way back.
        let limit = min(n + m, maximumDifferences)
        let offset = limit + 1
        var v = [Int32](repeating: 0, count: 2 * limit + 3)
        var trace: [[Int32]] = []
        var final: Int?
        search: for d in 0...limit {
            trace.append(Array(v[(offset - d - 1)...(offset + d + 1)]))
            for k in stride(from: -d, through: d, by: 2) {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                    x = Int(v[offset + k + 1])
                } else {
                    x = Int(v[offset + k - 1]) + 1
                }
                var y = x - k
                while x < n, y < m, a[start + x] == b[start + y] {
                    x += 1
                    y += 1
                }
                v[offset + k] = Int32(x)
                if x >= n, y >= m {
                    final = d
                    break search
                }
            }
        }
        guard let final else { return [Change(base: start..<endA, other: start..<endB)] }

        // Backtrack, collecting the matched lines.
        var matches: [(Int, Int)] = []
        var x = n
        var y = m
        for d in stride(from: final, through: 0, by: -1) {
            let frontier = trace[d]
            func at(_ k: Int) -> Int { Int(frontier[k + d + 1]) }
            let k = x - y
            let previousK = (k == -d || (k != d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1
            let previousX = d == 0 ? 0 : at(previousK)
            let previousY = d == 0 ? 0 : previousX - previousK
            while x > previousX, y > previousY {
                x -= 1
                y -= 1
                matches.append((x, y))
            }
            x = previousX
            y = previousY
        }
        matches.reverse()

        var result: [Change] = []
        var nextA = 0
        var nextB = 0
        for (i, j) in matches {
            if i > nextA || j > nextB {
                result.append(Change(base: (start + nextA)..<(start + i), other: (start + nextB)..<(start + j)))
            }
            nextA = i + 1
            nextB = j + 1
        }
        if nextA < n || nextB < m {
            result.append(Change(base: (start + nextA)..<endA, other: (start + nextB)..<endB))
        }
        return result
    }

    /// Lines to integers, shared across the versions being compared.
    struct Interner {
        private var ids: [[UInt8]: Int] = [:]

        mutating func intern(_ lines: [[UInt8]]) -> [Int] {
            lines.map { line in
                if let id = ids[line] { return id }
                let id = ids.count
                ids[line] = id
                return id
            }
        }
    }
}

/// The three-way merge of design D6: both sides diffed against the base, the
/// base walked once, each stretch emitted as stable text or a hunk.
public enum ThreeWay {
    /// Both sides changed the same stretch differently. `base` is what the
    /// stretch was; `ours` and `theirs` what each side made of it.
    public struct Hunk: Equatable, Sendable {
        public let base: [[UInt8]]
        public let ours: [[UInt8]]
        public let theirs: [[UInt8]]
        /// The lines zealous trimming moved out of the hunk into the stable
        /// region before it (change `merge-both-multiline-objects`, design
        /// D1): `before + ours + after` is ours' untrimmed text for the
        /// stretch, `before + theirs + after` theirs'.
        public let before: [[UInt8]]
        /// The lines trimming moved into the stable region after the hunk.
        public let after: [[UInt8]]
        /// The base's own lines for the whole stretch `before` and `after`
        /// frame, which is what `trim` was given. Trimming shortens `base`
        /// by them only where the base has them in the same place, so this
        /// is `base` again for a hunk it did not cut, and never more than
        /// `before + base + after`.
        public let stretchBase: [[UInt8]]

        public init(base: [[UInt8]], ours: [[UInt8]], theirs: [[UInt8]], before: [[UInt8]] = [], after: [[UInt8]] = [],
                    stretchBase: [[UInt8]]? = nil) {
            self.base = base
            self.ours = ours
            self.theirs = theirs
            self.before = before
            self.after = after
            self.stretchBase = stretchBase ?? base
        }
    }

    public enum Region: Equatable, Sendable {
        case stable([[UInt8]])
        case hunk(Hunk)
    }

    public struct Merge: Equatable, Sendable {
        /// Stable regions are maximal: two are never adjacent.
        public let regions: [Region]

        public var hunks: [Hunk] {
            regions.compactMap { if case .hunk(let hunk) = $0 { return hunk } else { return nil } }
        }

        /// The merged text with hunk `index` (in file order) resolved to the
        /// lines `resolve` returns for it.
        public func text(resolving resolve: (_ index: Int, _ hunk: Hunk) -> [[UInt8]]) -> [UInt8] {
            var lines: [[UInt8]] = []
            var index = 0
            for region in regions {
                switch region {
                case .stable(let stable):
                    lines += stable
                case .hunk(let hunk):
                    lines += resolve(index, hunk)
                    index += 1
                }
            }
            return TextLines.join(lines)
        }

        /// The merged text with the whole stretch of hunk `index` replaced by
        /// `lines` and every other hunk resolved `ours` (change
        /// `merge-both-multiline-objects`, design D2). The stretch is the
        /// hunk together with the `before` and `after` that zealous trimming
        /// moved into the stable regions on either side, so that a base that
        /// never held those lines is not handed them twice.
        public func text(replacingStretchOf index: Int, with lines: [[UInt8]]) -> [UInt8] {
            var result: [[UInt8]] = []
            var number = 0
            var skip = 0
            for region in regions {
                switch region {
                case .stable(let stable):
                    result += stable.dropFirst(skip)
                    skip = 0
                case .hunk(let hunk):
                    if number == index {
                        result.removeLast(min(hunk.before.count, result.count))
                        result += lines
                        skip = hunk.after.count
                    } else {
                        result += hunk.ours
                    }
                    number += 1
                }
            }
            return TextLines.join(result)
        }
    }

    /// `wholeSpans` are base line ranges each kept in one piece (change
    /// `merge-reorder-whole-array`, design D1): every change inside one joins
    /// a single cluster, so a stretch both sides changed there is one hunk
    /// whose `ours` and `theirs` are each side's whole text for it.
    public static func merge(base: [[UInt8]], ours: [[UInt8]], theirs: [[UInt8]], wholeSpans: [Range<Int>] = []) -> Merge {
        var interner = LineDiff.Interner()
        let (b, o, t) = (interner.intern(base), interner.intern(ours), interner.intern(theirs))
        let changes = LineDiff.changes(b, o).map { Side(change: $0, ours: true) }
            + LineDiff.changes(b, t).map { Side(change: $0, ours: false) }
        let sorted = changes.sorted {
            ($0.change.base.lowerBound, $0.change.base.upperBound, $0.ours ? 0 : 1)
                < ($1.change.base.lowerBound, $1.change.base.upperBound, $1.ours ? 0 : 1)
        }

        // Clusters: changes linked by a conflict with the stretch so far.
        var clusters: [(range: Range<Int>, changes: [Side])] = []
        for side in sorted {
            if let last = clusters.last, conflicts(last.range, side.change.base) {
                let range = last.range.lowerBound..<max(last.range.upperBound, side.change.base.upperBound)
                clusters[clusters.count - 1] = (range, last.changes + [side])
            } else {
                clusters.append((side.change.base, [side]))
            }
        }

        for span in wholeSpans {
            let inside = clusters.indices.filter { within(clusters[$0].range, span) }
            guard let first = inside.first, let last = inside.last, first < last,
                  let end = clusters[first...last].map(\.range.upperBound).max()
            else { continue }
            let joined = (range: clusters[first].range.lowerBound..<end, changes: clusters[first...last].flatMap(\.changes))
            clusters.replaceSubrange(first...last, with: [joined])
        }

        var builder = RegionBuilder()
        var position = 0
        for cluster in clusters {
            builder.stable(Array(base[position..<cluster.range.lowerBound]))
            let oursChanges = cluster.changes.filter(\.ours).map(\.change)
            let theirsChanges = cluster.changes.filter { !$0.ours }.map(\.change)
            let oursText = apply(oursChanges, over: cluster.range, base: base, side: ours)
            let theirsText = apply(theirsChanges, over: cluster.range, base: base, side: theirs)
            if theirsChanges.isEmpty || oursText == theirsText {
                builder.stable(oursText)
            } else if oursChanges.isEmpty {
                builder.stable(theirsText)
            } else {
                let trimmed = trim(Hunk(base: Array(base[cluster.range]), ours: oursText, theirs: theirsText))
                builder.stable(trimmed.before)
                builder.hunk(trimmed.hunk)
                builder.stable(trimmed.after)
            }
            position = cluster.range.upperBound
        }
        builder.stable(Array(base[position...]))
        return Merge(regions: builder.regions)
    }

    private struct Side {
        let change: LineDiff.Change
        let ours: Bool
    }

    /// Design D6: overlapping base ranges conflict, and so do two insertions
    /// at one position; a change that ends where another starts does not,
    /// nor does an insertion at either end of a replaced range.
    static func conflicts(_ stretch: Range<Int>, _ next: Range<Int>) -> Bool {
        switch (stretch.isEmpty, next.isEmpty) {
        case (false, false): return next.lowerBound < stretch.upperBound
        case (true, true): return next.lowerBound == stretch.lowerBound
        case (true, false): return next.lowerBound < stretch.lowerBound && stretch.lowerBound < next.upperBound
        case (false, true): return stretch.lowerBound < next.lowerBound && next.lowerBound < stretch.upperBound
        }
    }

    /// A cluster lies within a whole span when it overlaps it; an insertion,
    /// when it falls strictly between the span's first and last line — after
    /// the line that opens it and before the line that closes it.
    static func within(_ range: Range<Int>, _ span: Range<Int>) -> Bool {
        range.isEmpty
            ? span.lowerBound < range.lowerBound && range.lowerBound < span.upperBound
            : range.lowerBound < span.upperBound && span.lowerBound < range.upperBound
    }

    /// One side's text for `range` of the base: its changes there applied.
    private static func apply(_ changes: [LineDiff.Change], over range: Range<Int>, base: [[UInt8]], side: [[UInt8]]) -> [[UInt8]] {
        var result: [[UInt8]] = []
        var position = range.lowerBound
        for change in changes {
            result += base[position..<change.base.lowerBound]
            result += side[change.other]
            position = change.base.upperBound
        }
        result += base[position..<range.upperBound]
        return result
    }

    /// Zealous trimming (`--zdiff3`): lines common to the start and to the
    /// end of both sides' text become stable context, and leave the base
    /// too where it has them in the same place.
    static func trim(_ hunk: Hunk) -> (before: [[UInt8]], hunk: Hunk, after: [[UInt8]]) {
        var (base, ours, theirs) = (hunk.base, hunk.ours, hunk.theirs)
        var prefix = 0
        while prefix < ours.count, prefix < theirs.count, ours[prefix] == theirs[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < ours.count - prefix, suffix < theirs.count - prefix,
              ours[ours.count - 1 - suffix] == theirs[theirs.count - 1 - suffix] { suffix += 1 }
        let before = Array(ours[..<prefix])
        let after = Array(ours[(ours.count - suffix)...])
        ours = Array(ours[prefix..<(ours.count - suffix)])
        theirs = Array(theirs[prefix..<(theirs.count - suffix)])
        if base.starts(with: before) { base.removeFirst(before.count) }
        if base.count >= after.count, Array(base.suffix(after.count)) == after { base.removeLast(after.count) }
        return (before, Hunk(base: base, ours: ours, theirs: theirs, before: before, after: after, stretchBase: hunk.base), after)
    }

    /// Coalesces stable text so two stable regions are never adjacent.
    private struct RegionBuilder {
        private(set) var finished: [Region] = []
        private var pending: [[UInt8]] = []

        var regions: [Region] {
            pending.isEmpty ? finished : finished + [.stable(pending)]
        }

        mutating func stable(_ lines: [[UInt8]]) { pending += lines }

        mutating func hunk(_ hunk: Hunk) {
            if !pending.isEmpty { finished.append(.stable(pending)) }
            pending = []
            finished.append(.hunk(hunk))
        }
    }
}
