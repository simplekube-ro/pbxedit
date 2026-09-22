/// Reading layout out of trivia (design D6): where a line starts, and which
/// part of an item's leading trivia is "its own line".
struct LineStart: Equatable {
    /// `"\n"`, `"\r\n"` or `"\r"`, as found.
    var newline: String
    var indent: String

    var trivia: Trivia { Trivia(unchecked: newline + indent) }
}

extension Trivia {
    /// The whitespace after the last comment, or all of it when there is no comment.
    var trailingWhitespace: String {
        if case .whitespace(let text)? = pieces.last { return text }
        return ""
    }

    /// The last line break in the trailing whitespace and the indentation
    /// after it; `nil` when the token is on the same line as what precedes it.
    var lineStart: LineStart? {
        let bytes = Array(trailingWhitespace.utf8)
        guard let last = bytes.lastIndex(where: { $0 == 0x0A || $0 == 0x0D }) else { return nil }
        var first = last
        if bytes[last] == 0x0A, last > 0, bytes[last - 1] == 0x0D { first = last - 1 }
        return LineStart(
            newline: String(decoding: bytes[first...last], as: UTF8.self),
            indent: String(decoding: bytes[(last + 1)...], as: UTF8.self))
    }

    var isWhitespaceOnly: Bool {
        pieces.allSatisfy { if case .whitespace = $0 { return true } else { return false } }
    }

    /// Splits into what precedes the token's own line (comments, blank lines)
    /// and the token's own line break and indentation. For a token that does
    /// not start a line, `own` is its trailing whitespace.
    func splitOwnLine() -> (prefix: Trivia, own: Trivia) {
        let own = lineStart.map { $0.newline + $0.indent } ?? trailingWhitespace
        let bytes = Array(text.utf8)
        let cut = bytes.count - own.utf8.count
        guard cut >= 0 else { return (.empty, self) }
        return (
            Trivia(unchecked: String(decoding: bytes[..<cut], as: UTF8.self)),
            Trivia(unchecked: own)
        )
    }

    /// Splits at the first line break outside a comment: what shares a line
    /// with the preceding token, and the rest. `nil` when there is no break.
    func splitFirstLine() -> (sameLine: Trivia, rest: Trivia)? {
        var offset = 0
        for piece in pieces {
            let pieceBytes = Array(piece.text.utf8)
            if case .whitespace = piece, let lineBreak = pieceBytes.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let bytes = Array(text.utf8)
                let cut = offset + lineBreak
                guard cut <= bytes.count else { return nil }
                return (
                    Trivia(unchecked: String(decoding: bytes[..<cut], as: UTF8.self)),
                    Trivia(unchecked: String(decoding: bytes[cut...], as: UTF8.self))
                )
            }
            offset += pieceBytes.count
        }
        return nil
    }

    /// The comments, without the trailing whitespace.
    var withoutTrailingWhitespace: Trivia {
        let bytes = Array(text.utf8)
        let cut = bytes.count - trailingWhitespace.utf8.count
        guard cut >= 0 else { return .empty }
        return Trivia(unchecked: String(decoding: bytes[..<cut], as: UTF8.self))
    }

    /// An annotation comment as Xcode writes one: a space, then `/* body */`.
    static func annotation(_ body: String) throws -> Trivia {
        guard let comment = Trivia.blockComment(body) else { throw EditError.invalidComment(body) }
        return Trivia(unchecked: " " + comment.text)
    }

    /// This trivia with its first block comment replaced, or with an
    /// annotation put in front when it has none.
    func replacingAnnotation(with body: String) throws -> Trivia {
        guard let comment = Trivia.blockComment(body) else { throw EditError.invalidComment(body) }
        var result = ""
        var replaced = false
        for piece in pieces {
            if case .blockComment = piece, !replaced {
                result += comment.text
                replaced = true
            } else {
                result += piece.text
            }
        }
        return replaced ? Trivia(unchecked: result) : Trivia(unchecked: " " + comment.text) + self
    }
}

/// The view of a container that layout needs: the leading trivia of each
/// item's first token, and of the closing delimiter.
protocol ItemContainer {
    var itemCount: Int { get }
    func itemLeading(_ index: Int) -> Trivia
    mutating func setItemLeading(_ index: Int, _ trivia: Trivia)
    func itemValue(_ index: Int) -> Node
    var closeLeading: Trivia { get set }
}

extension DictionaryNode: ItemContainer {
    var itemCount: Int { entries.count }
    func itemLeading(_ index: Int) -> Trivia { entries[index].key.token.leadingTrivia }
    mutating func setItemLeading(_ index: Int, _ trivia: Trivia) { entries[index].key.token.leadingTrivia = trivia }
    func itemValue(_ index: Int) -> Node { entries[index].value }
    var closeLeading: Trivia {
        get { rightBrace.leadingTrivia }
        set { rightBrace.leadingTrivia = newValue }
    }
}

extension ArrayNode: ItemContainer {
    var itemCount: Int { elements.count }
    func itemLeading(_ index: Int) -> Trivia { elements[index].value.leadingTrivia }
    mutating func setItemLeading(_ index: Int, _ trivia: Trivia) { elements[index].value.leadingTrivia = trivia }
    func itemValue(_ index: Int) -> Node { elements[index].value }
    var closeLeading: Trivia {
        get { rightParen.leadingTrivia }
        set { rightParen.leadingTrivia = newValue }
    }
}

extension Node {
    /// The leading trivia of the node's first token.
    var leadingTrivia: Trivia {
        get { firstToken.leadingTrivia }
        set {
            switch self {
            case .string(var node):
                node.token.leadingTrivia = newValue
                self = .string(node)
            case .data(var node):
                node.token.leadingTrivia = newValue
                self = .data(node)
            case .dictionary(var node):
                node.leftBrace.leadingTrivia = newValue
                self = .dictionary(node)
            case .array(var node):
                node.leftParen.leadingTrivia = newValue
                self = .array(node)
            }
        }
    }

    private var container: (any ItemContainer)? {
        switch self {
        case .dictionary(let node): return node
        case .array(let node): return node
        case .string, .data: return nil
        }
    }

    var isContainer: Bool { container != nil }

    /// Whether a container spreads over lines: its closing delimiter or any
    /// of its items starts a line.
    var isMultiLine: Bool {
        guard let container else { return false }
        if container.closeLeading.lineStart != nil { return true }
        return (0..<container.itemCount).contains { container.itemLeading($0).lineStart != nil }
    }

    /// The indentation of the container's first item that starts a line.
    var firstItemIndent: String? {
        guard let container else { return nil }
        for index in 0..<container.itemCount {
            if let lineStart = container.itemLeading(index).lineStart { return lineStart.indent }
        }
        return nil
    }
}

/// Where a new item goes and what trivia surrounds it.
struct Placement {
    var newLeading: Trivia
    /// New leading trivia for the item the insertion pushes down, if it changes.
    var displacedLeading: Trivia?
    var closeLeading: Trivia?
    /// The sibling whose value the new value's layout is copied from.
    var templateIndex: Int?

    /// - Parameter aboveNext: `true` to put the item directly above the item
    ///   now at `index`, taking over the comments before it; `false` to put
    ///   it directly below the item at `index - 1`.
    static func make(in container: some ItemContainer, at index: Int, aboveNext: Bool) -> Placement {
        let count = container.itemCount
        guard count > 0 else {
            let close = container.closeLeading
            if let lineStart = close.lineStart {
                // Design D6: the closing delimiter's indentation plus one tab.
                return Placement(newLeading: Trivia(unchecked: lineStart.newline + lineStart.indent + "\t"))
            }
            return Placement(newLeading: .empty, closeLeading: close.isEmpty ? Trivia(unchecked: " ") : nil)
        }
        if aboveNext || index == 0 {
            let target = min(index, count - 1)
            let leading = container.itemLeading(target)
            let displaced: Trivia
            if let lineStart = leading.lineStart {
                displaced = lineStart.trivia
            } else if target == 0 {
                displaced = Trivia(unchecked: sameLineSeparator(in: container))
            } else {
                displaced = Trivia(unchecked: nonEmpty(leading.trailingWhitespace))
            }
            return Placement(newLeading: leading, displacedLeading: displaced, templateIndex: target)
        }
        let template = index - 1
        let leading = container.itemLeading(template)
        let newLeading: Trivia
        if let lineStart = leading.lineStart {
            newLeading = lineStart.trivia
        } else if template == 0 {
            newLeading = Trivia(unchecked: sameLineSeparator(in: container))
        } else {
            newLeading = Trivia(unchecked: nonEmpty(leading.trailingWhitespace))
        }
        return Placement(newLeading: newLeading, templateIndex: template)
    }

    private static func nonEmpty(_ whitespace: String) -> String {
        whitespace.isEmpty ? " " : whitespace
    }

    /// The whitespace between items that share a line. The first item cannot
    /// say, because it follows the opening delimiter.
    private static func sameLineSeparator(in container: some ItemContainer) -> String {
        if container.itemCount > 1, container.itemLeading(1).lineStart == nil {
            let whitespace = container.itemLeading(1).trailingWhitespace
            if !whitespace.isEmpty { return whitespace }
        }
        if container.closeLeading.lineStart == nil {
            let whitespace = container.closeLeading.trailingWhitespace
            if !whitespace.isEmpty { return whitespace }
        }
        return " "
    }
}

/// Turns layout-free `NewValue`s into tokens.
struct NodeBuilder {
    var newline: String
    var unit: String

    /// - Parameter lineIndent: the indentation of the line the value's item
    ///   starts on when the value is written across lines; `nil` for one line.
    func node(_ value: NewValue, leading: Trivia, lineIndent: String?) throws -> Node {
        switch value.content {
        case .string(let string):
            return .string(StringNode(token: StringCoding.token(for: string, leadingTrivia: leading)))
        case .array(let elements):
            let inner = itemLeadings(count: elements.count, lineIndent: lineIndent)
            var built: [ArrayNode.Element] = []
            for (element, itemLeading) in zip(elements, inner.items) {
                built.append(try self.element(element, leading: itemLeading, lineIndent: lineIndent.map { $0 + unit }, comma: true))
            }
            return .array(ArrayNode(
                leftParen: .punctuation(.leftParen, leadingTrivia: leading), elements: built,
                rightParen: .punctuation(.rightParen, leadingTrivia: inner.close)))
        case .dictionary(let entries):
            let inner = itemLeadings(count: entries.count, lineIndent: lineIndent)
            var built: [DictionaryNode.Entry] = []
            for (entry, itemLeading) in zip(entries, inner.items) {
                built.append(try self.entry(entry, leading: itemLeading, lineIndent: lineIndent.map { $0 + unit }))
            }
            return .dictionary(DictionaryNode(
                leftBrace: .punctuation(.leftBrace, leadingTrivia: leading), entries: built,
                rightBrace: .punctuation(.rightBrace, leadingTrivia: inner.close)))
        }
    }

    func entry(_ entry: NewEntry, leading: Trivia, lineIndent: String?) throws -> DictionaryNode.Entry {
        let equalsLeading = try entry.keyComment.map { try Trivia.annotation($0) + Trivia(unchecked: " ") }
            ?? Trivia(unchecked: " ")
        return DictionaryNode.Entry(
            key: StringNode(token: StringCoding.token(for: entry.key, leadingTrivia: leading)),
            equals: .punctuation(.equals, leadingTrivia: equalsLeading),
            value: try node(entry.value, leading: Trivia(unchecked: " "), lineIndent: lineIndent),
            semicolon: .punctuation(.semicolon, leadingTrivia: try entry.value.comment.map(Trivia.annotation) ?? .empty))
    }

    func element(_ value: NewValue, leading: Trivia, lineIndent: String?, comma: Bool) throws -> ArrayNode.Element {
        ArrayNode.Element(
            value: try node(value, leading: leading, lineIndent: lineIndent),
            comma: comma
                ? .punctuation(.comma, leadingTrivia: try value.comment.map(Trivia.annotation) ?? .empty) : nil)
    }

    /// Xcode's two layouts. One line: `(a, b, )` and `{k = v; }`. Across
    /// lines: each item one unit deeper, the closing delimiter at `lineIndent`.
    private func itemLeadings(count: Int, lineIndent: String?) -> (items: [Trivia], close: Trivia) {
        if let lineIndent {
            let item = Trivia(unchecked: newline + lineIndent + unit)
            return ([Trivia](repeating: item, count: count), Trivia(unchecked: newline + lineIndent))
        }
        guard count > 0 else { return ([], .empty) }
        let space = Trivia(unchecked: " ")
        return ([.empty] + [Trivia](repeating: space, count: count - 1), space)
    }
}
