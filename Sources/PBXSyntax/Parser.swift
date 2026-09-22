extension SyntaxTree {
    /// Parses old-style property-list text. Never traps: input that does not
    /// parse yields a located `ParseError`.
    public static func parse(_ bytes: [UInt8]) -> Result<SyntaxTree, ParseError> {
        bytes.withUnsafeBufferPointer { buffer in
            switch Lexer.lex(buffer) {
            case .failure(let error):
                return .failure(error)
            case .success(let lexed):
                var parser = Parser(buffer: buffer, tokens: lexed.tokens, offsets: lexed.offsets)
                return parser.parseFile()
            }
        }
    }

    /// Parses the UTF-8 bytes of `text`.
    public static func parse(_ text: String) -> Result<SyntaxTree, ParseError> {
        parse(Array(text.utf8))
    }
}

/// Recursive descent over the token list, with a nesting limit so that no
/// input can exhaust the stack.
struct Parser {
    private let buffer: UnsafeBufferPointer<UInt8>
    private let tokens: [Token]
    private let offsets: [Int]
    private var index = 0

    init(buffer: UnsafeBufferPointer<UInt8>, tokens: [Token], offsets: [Int]) {
        self.buffer = buffer
        self.tokens = tokens
        self.offsets = offsets
    }

    mutating func parseFile() -> Result<SyntaxTree, ParseError> {
        do {
            let root = try parseValue(depth: 0, expected: "a dictionary, array, string or data value")
            let endOfFile = try expect(.endOfFile, "end of input after the top-level value")
            return .success(SyntaxTree(root: root, endOfFile: endOfFile))
        } catch let error as ParseError {
            return .failure(error)
        } catch {
            // Unreachable: only `ParseError` is thrown in this file.
            return .failure(ParseError(kind: .unexpectedToken, at: 0, in: buffer, expected: "a property list"))
        }
    }

    private var current: Token? { index < tokens.count ? tokens[index] : nil }

    private func failure(_ expected: String, kind: ParseError.Kind? = nil) -> ParseError {
        let offset = index < offsets.count ? offsets[index] : buffer.count
        guard let token = current, token.kind != .endOfFile else {
            return ParseError(
                kind: kind ?? .unexpectedEndOfInput, at: buffer.count, in: buffer, expected: expected,
                found: "end of input")
        }
        return ParseError(kind: kind ?? .unexpectedToken, at: offset, in: buffer, expected: expected)
    }

    private mutating func expect(_ kind: TokenKind, _ expected: String) throws -> Token {
        guard let token = current, token.kind == kind else { throw failure(expected) }
        index += 1
        return token
    }

    private mutating func parseValue(depth: Int, expected: String) throws -> Node {
        guard let token = current else { throw failure(expected) }
        switch token.kind {
        case .bareString, .quotedString:
            index += 1
            return .string(StringNode(token: token))
        case .data:
            index += 1
            return .data(DataNode(token: token))
        case .leftBrace:
            return .dictionary(try parseDictionary(depth: depth + 1))
        case .leftParen:
            return .array(try parseArray(depth: depth + 1))
        case .rightBrace, .rightParen, .equals, .semicolon, .comma, .endOfFile:
            throw failure(expected)
        }
    }

    private func checkDepth(_ depth: Int) throws {
        if depth > SyntaxTree.maximumNestingDepth {
            throw failure(
                "at most \(SyntaxTree.maximumNestingDepth) levels of nesting", kind: .nestingTooDeep)
        }
    }

    private mutating func parseDictionary(depth: Int) throws -> DictionaryNode {
        try checkDepth(depth)
        let leftBrace = try expect(.leftBrace, "'{'")
        var entries: [DictionaryNode.Entry] = []
        while true {
            guard let token = current else { throw failure("a key or '}'") }
            if token.kind == .rightBrace {
                index += 1
                return DictionaryNode(leftBrace: leftBrace, entries: entries, rightBrace: token)
            }
            guard token.kind == .bareString || token.kind == .quotedString else {
                throw failure("a key or '}'")
            }
            index += 1
            let equals = try expect(.equals, "'=' after the key")
            let value = try parseValue(depth: depth, expected: "a value after '='")
            let semicolon = try expect(.semicolon, "';' after the value")
            entries.append(
                DictionaryNode.Entry(key: StringNode(token: token), equals: equals, value: value, semicolon: semicolon))
        }
    }

    private mutating func parseArray(depth: Int) throws -> ArrayNode {
        try checkDepth(depth)
        let leftParen = try expect(.leftParen, "'('")
        var elements: [ArrayNode.Element] = []
        while true {
            guard let token = current else { throw failure("a value or ')'") }
            if token.kind == .rightParen {
                index += 1
                return ArrayNode(leftParen: leftParen, elements: elements, rightParen: token)
            }
            if let last = elements.last, last.comma == nil { throw failure("',' or ')' after the value") }
            let value = try parseValue(depth: depth, expected: "a value or ')'")
            var comma: Token?
            if let next = current, next.kind == .comma {
                index += 1
                comma = next
            }
            elements.append(ArrayNode.Element(value: value, comma: comma))
        }
    }
}
