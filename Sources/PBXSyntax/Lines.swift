extension SyntaxTree {
    /// Every array reached from the root through dictionary keys alone, with
    /// the keys that reach it and the lines it spans: from the line of its
    /// `(` to the line of its `)`, counted from 0 as `\n` ends them. An array
    /// inside an array is not reached by keys and is not listed. A repeated
    /// key lists each of its arrays.
    public func arrayLines() -> [(keys: [String], lines: Range<Int>)] {
        var walk = LineWalk()
        walk.visit(root, keys: [])
        return walk.arrays
    }
}

/// The lines of `SyntaxTree.arrayLines()`, walked in source order as
/// `forEachToken` visits the tokens.
private struct LineWalk {
    var line = 0
    var arrays: [(keys: [String], lines: Range<Int>)] = []

    /// The line `token`'s text starts on; moves past its trivia and text.
    mutating func advance(_ token: Token) -> Int {
        line += LineWalk.newlines(token.leadingTrivia.text)
        let start = line
        line += LineWalk.newlines(token.text)
        return start
    }

    mutating func visit(_ node: Node, keys: [String]?) {
        switch node {
        case .string(let string):
            _ = advance(string.token)
        case .data(let data):
            _ = advance(data.token)
        case .dictionary(let dictionary):
            _ = advance(dictionary.leftBrace)
            for entry in dictionary.entries {
                _ = advance(entry.key.token)
                _ = advance(entry.equals)
                visit(entry.value, keys: keys.map { $0 + [entry.key.value] })
                _ = advance(entry.semicolon)
            }
            _ = advance(dictionary.rightBrace)
        case .array(let array):
            let start = advance(array.leftParen)
            for element in array.elements {
                visit(element.value, keys: nil)
                if let comma = element.comma { _ = advance(comma) }
            }
            let end = advance(array.rightParen)
            if let keys { arrays.append((keys, start..<(end + 1))) }
        }
    }

    static func newlines(_ text: String) -> Int {
        text.utf8.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
    }
}
