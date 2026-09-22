/// Serialization is the concatenation of every token's trivia and text in
/// order (design D1), so a tree that was parsed and not edited reproduces its
/// input by construction.
extension SyntaxTree: CustomStringConvertible {
    public func serialize() -> [UInt8] {
        var output: [UInt8] = []
        forEachToken { token in
            output.append(contentsOf: token.leadingTrivia.text.utf8)
            output.append(contentsOf: token.text.utf8)
        }
        return output
    }

    public var description: String {
        String(decoding: serialize(), as: UTF8.self)
    }

    /// Visits every token in source order.
    func forEachToken(_ body: (Token) -> Void) {
        root.forEachToken(body)
        body(endOfFile)
    }
}

extension Node {
    /// Visits every token in source order. Recursion is bounded by
    /// `SyntaxTree.maximumNestingDepth` for parsed and for edited trees.
    func forEachToken(_ body: (Token) -> Void) {
        switch self {
        case .string(let node):
            body(node.token)
        case .data(let node):
            body(node.token)
        case .dictionary(let node):
            body(node.leftBrace)
            for entry in node.entries {
                body(entry.key.token)
                body(entry.equals)
                entry.value.forEachToken(body)
                body(entry.semicolon)
            }
            body(node.rightBrace)
        case .array(let node):
            body(node.leftParen)
            for element in node.elements {
                element.value.forEachToken(body)
                if let comma = element.comma { body(comma) }
            }
            body(node.rightParen)
        }
    }

    /// The node's first token.
    var firstToken: Token {
        switch self {
        case .string(let node): return node.token
        case .data(let node): return node.token
        case .dictionary(let node): return node.leftBrace
        case .array(let node): return node.leftParen
        }
    }
}
