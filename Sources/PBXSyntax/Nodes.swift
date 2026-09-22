/// A value in the tree (design D1). Nodes are value types; serializing one is
/// the concatenation of its tokens in order.
public enum Node: Sendable, Equatable {
    case dictionary(DictionaryNode)
    case array(ArrayNode)
    case string(StringNode)
    case data(DataNode)

    public var dictionary: DictionaryNode? {
        if case .dictionary(let node) = self { return node }
        return nil
    }

    public var array: ArrayNode? {
        if case .array(let node) = self { return node }
        return nil
    }

    public var string: StringNode? {
        if case .string(let node) = self { return node }
        return nil
    }

    public var data: DataNode? {
        if case .data(let node) = self { return node }
        return nil
    }

    /// The decoded value when this node is a string.
    public var stringValue: String? { string?.value }
}

/// `{ key = value; … }`. Entries keep their source order, duplicates included.
public struct DictionaryNode: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public internal(set) var key: StringNode
        public internal(set) var equals: Token
        public internal(set) var value: Node
        public internal(set) var semicolon: Token
    }

    public internal(set) var leftBrace: Token
    public internal(set) var entries: [Entry]
    public internal(set) var rightBrace: Token

    /// The decoded keys, in source order.
    public var keys: [String] { entries.map(\.key.value) }

    /// The index of the first entry whose key is byte-for-byte `key`.
    public func firstIndex(ofKey key: String) -> Int? {
        entries.firstIndex { $0.key.matches(key) }
    }

    /// The value of the first entry whose key is byte-for-byte `key`.
    public subscript(key: String) -> Node? {
        firstIndex(ofKey: key).map { entries[$0].value }
    }
}

/// `( value, … )`. The last element's comma is optional in the grammar.
public struct ArrayNode: Sendable, Equatable {
    public struct Element: Sendable, Equatable {
        public internal(set) var value: Node
        public internal(set) var comma: Token?
    }

    public internal(set) var leftParen: Token
    public internal(set) var elements: [Element]
    public internal(set) var rightParen: Token

    /// The index of the first element that is a string equal, byte for byte, to `value`.
    public func firstIndex(ofString value: String) -> Int? {
        elements.firstIndex { $0.value.string?.matches(value) ?? false }
    }
}

/// A bare or quoted string. The token keeps the raw text; the decoded value
/// is computed on demand.
public struct StringNode: Sendable, Equatable {
    public internal(set) var token: Token

    /// The source text, quotes and escapes included.
    public var rawText: String { token.text }

    public var isQuoted: Bool { token.kind == .quotedString }

    /// The decoded value.
    public var value: String {
        guard isQuoted else { return token.text }
        if !hasEscapes { return String(decoding: token.text.utf8.dropFirst().dropLast(), as: UTF8.self) }
        return StringCoding.decodeQuoted(token.text)
    }

    /// Whether the decoded value is byte-for-byte `other`. `String ==` would
    /// also accept canonically equivalent text; identifiers must not.
    public func matches(_ other: String) -> Bool {
        if !isQuoted { return token.text.utf8.elementsEqual(other.utf8) }
        if !hasEscapes { return token.text.utf8.dropFirst().dropLast().elementsEqual(other.utf8) }
        return value.utf8.elementsEqual(other.utf8)
    }

    /// A quoted string without a backslash decodes to the bytes between its
    /// quotes; most quoted strings in a project file are of that kind.
    private var hasEscapes: Bool { token.text.utf8.contains(0x5C) }
}

/// A `<hex>` data literal, kept as one opaque token.
public struct DataNode: Sendable, Equatable {
    public internal(set) var token: Token

    public var rawText: String { token.text }

    /// The decoded bytes.
    public var bytes: [UInt8] {
        var result: [UInt8] = []
        var pending: UInt8?
        for byte in token.text.utf8 {
            guard let nibble = StringCoding.hexValue(byte) else { continue }
            if let high = pending {
                result.append(high << 4 | nibble)
                pending = nil
            } else {
                pending = nibble
            }
        }
        return result
    }
}

/// A parsed file: the root value, and the end-of-file token that owns whatever
/// follows it.
public struct SyntaxTree: Sendable, Equatable {
    /// Containers nested deeper than this are a parse error (design D7).
    public static let maximumNestingDepth = 64

    public internal(set) var root: Node
    public internal(set) var endOfFile: Token
}
