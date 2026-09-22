public enum TokenKind: Sendable, Equatable {
    case leftBrace
    case rightBrace
    case leftParen
    case rightParen
    case equals
    case semicolon
    case comma
    /// An unquoted string.
    case bareString
    /// A string in double or single quotes. The token text includes the quotes.
    case quotedString
    /// A `<hex>` data literal. The token text includes the angle brackets.
    case data
    /// Zero-width. Owns the trivia that follows the last real token.
    case endOfFile
}

/// A token and the trivia before it (design D1). Serializing a token writes
/// its leading trivia and then its text.
public struct Token: Sendable, Equatable {
    public internal(set) var leadingTrivia: Trivia
    public let kind: TokenKind
    /// The exact source text: quotes, escapes and angle brackets included.
    public let text: String

    init(kind: TokenKind, text: String, leadingTrivia: Trivia = .empty) {
        self.kind = kind
        self.text = text
        self.leadingTrivia = leadingTrivia
    }

    /// Byte-exact comparison; see `Trivia.==`.
    public static func == (lhs: Token, rhs: Token) -> Bool {
        lhs.kind == rhs.kind && lhs.text.utf8.elementsEqual(rhs.text.utf8) && lhs.leadingTrivia == rhs.leadingTrivia
    }

    static func punctuation(_ kind: TokenKind, leadingTrivia: Trivia = .empty) -> Token {
        let text: String
        switch kind {
        case .leftBrace: text = "{"
        case .rightBrace: text = "}"
        case .leftParen: text = "("
        case .rightParen: text = ")"
        case .equals: text = "="
        case .semicolon: text = ";"
        case .comma: text = ","
        case .bareString, .quotedString, .data, .endOfFile: text = ""
        }
        return Token(kind: kind, text: text, leadingTrivia: leadingTrivia)
    }
}
