/// The unified diff `--dry-run` prints: Myers' O(ND) algorithm over lines,
/// which is linear in the size of the file for the handful of lines a plan
/// changes, with three lines of context and GNU's hunk headers.
public enum UnifiedDiff {
    struct Line: Equatable {
        let text: String
        let hasNewline: Bool
    }

    enum Edit {
        case equal(Int, Int)
        case delete(Int)
        case insert(Int)
    }

    /// The diff of `before` against `after`, labelled `a/<name>` and
    /// `b/<name>`; empty when the bytes are equal.
    public static func make(from before: [UInt8], to after: [UInt8], name: String, context: Int = 3) -> String {
        if before == after { return "" }
        let a = lines(before)
        let b = lines(after)
        let edits = diff(a, b)
        var records: [(edit: Edit, oldPos: Int, newPos: Int)] = []
        var oldPos = 0
        var newPos = 0
        for edit in edits {
            records.append((edit, oldPos, newPos))
            switch edit {
            case .equal: oldPos += 1; newPos += 1
            case .delete: oldPos += 1
            case .insert: newPos += 1
            }
        }
        let changes = records.indices.filter { if case .equal = records[$0].edit { return false } else { return true } }
        guard !changes.isEmpty else { return "" }
        var output = "--- a/\(name)\n+++ b/\(name)\n"
        var index = 0
        while index < changes.count {
            var last = index
            while last + 1 < changes.count, changes[last + 1] - changes[last] <= 2 * context { last += 1 }
            let start = max(0, changes[index] - context)
            let end = min(records.count - 1, changes[last] + context)
            var oldCount = 0
            var newCount = 0
            var body = ""
            for record in records[start...end] {
                switch record.edit {
                case .equal(let i, _):
                    oldCount += 1; newCount += 1
                    body += " " + a[i].text + "\n" + (a[i].hasNewline ? "" : noNewline)
                case .delete(let i):
                    oldCount += 1
                    body += "-" + a[i].text + "\n" + (a[i].hasNewline ? "" : noNewline)
                case .insert(let j):
                    newCount += 1
                    body += "+" + b[j].text + "\n" + (b[j].hasNewline ? "" : noNewline)
                }
            }
            let first = records[start]
            let oldStart = oldCount == 0 ? first.oldPos : first.oldPos + 1
            let newStart = newCount == 0 ? first.newPos : first.newPos + 1
            output += "@@ -\(range(oldStart, oldCount)) +\(range(newStart, newCount)) @@\n" + body
            index = last + 1
        }
        return output
    }

    private static let noNewline = "\\ No newline at end of file\n"

    private static func range(_ start: Int, _ count: Int) -> String {
        count == 1 ? "\(start)" : "\(start),\(count)"
    }

    static func lines(_ bytes: [UInt8]) -> [Line] {
        var result: [Line] = []
        var current: [UInt8] = []
        for byte in bytes {
            if byte == 0x0A {
                result.append(Line(text: String(decoding: current, as: UTF8.self), hasNewline: true))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
        }
        if !current.isEmpty { result.append(Line(text: String(decoding: current, as: UTF8.self), hasNewline: false)) }
        return result
    }

    /// Myers' algorithm with a per-step trace of only the diagonals in play.
    static func diff(_ a: [Line], _ b: [Line]) -> [Edit] {
        // Common prefix and suffix cost nothing to peel off.
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            suffix += 1
        }
        let x = Array(a[prefix..<(a.count - suffix)])
        let y = Array(b[prefix..<(b.count - suffix)])
        var edits: [Edit] = (0..<prefix).map { .equal($0, $0) }
        edits += middle(x, y).map { edit in
            switch edit {
            case .equal(let i, let j): return .equal(i + prefix, j + prefix)
            case .delete(let i): return .delete(i + prefix)
            case .insert(let j): return .insert(j + prefix)
            }
        }
        for offset in 0..<suffix {
            edits.append(.equal(a.count - suffix + offset, b.count - suffix + offset))
        }
        return edits
    }

    private static func middle(_ a: [Line], _ b: [Line]) -> [Edit] {
        let n = a.count
        let m = b.count
        if n == 0 { return (0..<m).map { .insert($0) } }
        if m == 0 { return (0..<n).map { .delete($0) } }
        let limit = n + m
        var v = [Int](repeating: 0, count: 2 * limit + 2)
        let offset = limit
        var trace: [[Int]] = []
        var found = false
        search: for d in 0...limit {
            trace.append(Array(v[(offset - d)...(offset + d)]))
            for k in stride(from: -d, through: d, by: 2) {
                var x: Int
                if k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]) {
                    x = v[offset + k + 1]
                } else {
                    x = v[offset + k - 1] + 1
                }
                var y = x - k
                while x < n, y < m, a[x] == b[y] {
                    x += 1
                    y += 1
                }
                v[offset + k] = x
                if x >= n, y >= m {
                    found = true
                    break search
                }
            }
        }
        precondition(found)
        var edits: [Edit] = []
        var x = n
        var y = m
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let slice = trace[d]
            let k = x - y
            let at = { (kk: Int) -> Int in slice[kk + d] }
            let previousK: Int
            if k == -d || (k != d && at(k - 1) < at(k + 1)) {
                previousK = k + 1
            } else {
                previousK = k - 1
            }
            let previousX = d == 0 ? 0 : at(previousK)
            let previousY = previousX - previousK
            while x > previousX, y > previousY {
                edits.append(.equal(x - 1, y - 1))
                x -= 1
                y -= 1
            }
            if d > 0 {
                if x == previousX {
                    edits.append(.insert(y - 1))
                } else {
                    edits.append(.delete(x - 1))
                }
            }
            x = previousX
            y = previousY
        }
        return edits.reversed()
    }
}
