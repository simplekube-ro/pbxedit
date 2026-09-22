/// Trivia-only accessors: read and replace the whitespace and comments around
/// an item without touching any value's bytes. The model layer uses them for
/// section markers and for the `/* name */` annotations Xcode writes.
extension SyntaxTree {
    // MARK: Leading trivia

    /// The leading trivia of the item at `path`: a dictionary entry's key, an
    /// array element's value, or the root. `nil` when the path does not resolve.
    public func leadingTrivia(at path: SyntaxPath) -> Trivia? {
        guard let last = path.last else { return root.leadingTrivia }
        guard let parent = node(at: Array(path.dropLast())) else { return nil }
        switch (parent, last) {
        case (.dictionary(let dictionary), .key(let key)):
            return dictionary.firstIndex(ofKey: key).map { dictionary.entries[$0].key.token.leadingTrivia }
        case (.array(let array), .index(let index)):
            return array.elements.indices.contains(index) ? array.elements[index].value.leadingTrivia : nil
        default:
            return nil
        }
    }

    /// Replaces the leading trivia of the item at `path`.
    public mutating func setLeadingTrivia(_ trivia: Trivia, at path: SyntaxPath) throws {
        guard let last = path.last else {
            root.leadingTrivia = trivia
            return
        }
        try mutate(at: Array(path.dropLast())) { node in
            switch (node, last) {
            case (.dictionary(var dictionary), .key(let key)):
                guard let index = dictionary.firstIndex(ofKey: key) else { throw EditError.pathNotFound(path) }
                node = SyntaxTree.placeholder
                dictionary.setItemLeading(index, trivia)
                node = .dictionary(dictionary)
            case (.array(var array), .index(let index)):
                guard array.elements.indices.contains(index) else { throw EditError.pathNotFound(path) }
                node = SyntaxTree.placeholder
                array.setItemLeading(index, trivia)
                node = .array(array)
            default:
                throw EditError.pathNotFound(path)
            }
        }
    }

    /// The leading trivia of the closing `}` or `)` of the container at `path`.
    public func closingTrivia(at path: SyntaxPath) -> Trivia? {
        switch node(at: path) {
        case .dictionary(let dictionary)?: return dictionary.rightBrace.leadingTrivia
        case .array(let array)?: return array.rightParen.leadingTrivia
        default: return nil
        }
    }

    /// Replaces the leading trivia of the closing delimiter of the container at `path`.
    public mutating func setClosingTrivia(_ trivia: Trivia, at path: SyntaxPath) throws {
        try mutate(at: path) { node in
            switch node {
            case .dictionary(var dictionary):
                node = SyntaxTree.placeholder
                dictionary.rightBrace.leadingTrivia = trivia
                node = .dictionary(dictionary)
            case .array(var array):
                node = SyntaxTree.placeholder
                array.rightParen.leadingTrivia = trivia
                node = .array(array)
            case .string, .data:
                throw EditError.pathNotFound(path)
            }
        }
    }

    // MARK: Annotations

    /// The body of the annotation after the value at `path`, as in
    /// `fileRef = B2 /* Foo.swift */;` or `B2 /* Foo.swift */,`: the first
    /// block comment on the value's own line. `nil` when there is none.
    public func annotation(at path: SyntaxPath) -> String? {
        guard let last = path.last, let parent = node(at: Array(path.dropLast())) else { return nil }
        switch (parent, last) {
        case (.dictionary(let dictionary), .key(let key)):
            return dictionary.firstIndex(ofKey: key).flatMap { dictionary.entries[$0].semicolon.leadingTrivia.annotationBody }
        case (.array(let array), .index(let index)):
            guard array.elements.indices.contains(index) else { return nil }
            return (array.elements[index].comma?.leadingTrivia ?? array.rightParen.leadingTrivia).annotationBody
        default:
            return nil
        }
    }

    /// Replaces the annotation after the value at `path`, or adds one. Only
    /// trivia changes: the value keeps its bytes and its quoting.
    public mutating func setAnnotation(_ body: String, at path: SyntaxPath) throws {
        guard let last = path.last else { throw EditError.pathNotFound(path) }
        try mutate(at: Array(path.dropLast())) { node in
            switch (node, last) {
            case (.dictionary(var dictionary), .key(let key)):
                guard let index = dictionary.firstIndex(ofKey: key) else { throw EditError.pathNotFound(path) }
                let trivia = try dictionary.entries[index].semicolon.leadingTrivia.replacingSameLineAnnotation(with: body)
                node = SyntaxTree.placeholder
                dictionary.entries[index].semicolon.leadingTrivia = trivia
                node = .dictionary(dictionary)
            case (.array(var array), .index(let index)):
                guard array.elements.indices.contains(index) else { throw EditError.pathNotFound(path) }
                if var comma = array.elements[index].comma {
                    comma.leadingTrivia = try comma.leadingTrivia.replacingSameLineAnnotation(with: body)
                    node = SyntaxTree.placeholder
                    array.elements[index].comma = comma
                } else {
                    let trivia = try array.rightParen.leadingTrivia.replacingSameLineAnnotation(with: body)
                    node = SyntaxTree.placeholder
                    array.rightParen.leadingTrivia = trivia
                }
                node = .array(array)
            default:
                throw EditError.pathNotFound(path)
            }
        }
    }

    /// The body of the annotation after the key of the entry at `path`, as in
    /// `A1 /* Foo.swift */ = {`. `nil` when there is none or `path` is not an entry.
    public func keyAnnotation(at path: SyntaxPath) -> String? {
        guard case .key(let key)? = path.last, let dictionary = node(at: Array(path.dropLast()))?.dictionary,
              let index = dictionary.firstIndex(ofKey: key)
        else { return nil }
        return dictionary.entries[index].equals.leadingTrivia.annotationBody
    }

    /// Replaces the annotation after the key of the entry at `path`, or adds one.
    public mutating func setKeyAnnotation(_ body: String, at path: SyntaxPath) throws {
        guard case .key(let key)? = path.last else { throw EditError.pathNotFound(path) }
        try mutate(at: Array(path.dropLast())) { node in
            guard case .dictionary(var dictionary) = node else { throw EditError.pathNotFound(path) }
            guard let index = dictionary.firstIndex(ofKey: key) else { throw EditError.pathNotFound(path) }
            let trivia = try dictionary.entries[index].equals.leadingTrivia.replacingSameLineAnnotation(with: body)
            node = SyntaxTree.placeholder
            dictionary.entries[index].equals.leadingTrivia = trivia
            node = .dictionary(dictionary)
        }
    }
}

extension Trivia {
    /// The body of the first block comment before the first line break, with
    /// the delimiters and one space of padding on each side removed.
    var annotationBody: String? {
        let sameLine = splitFirstLine()?.sameLine ?? self
        for piece in sameLine.pieces {
            if case .blockComment(let text) = piece { return Trivia.body(ofBlockComment: text) }
        }
        return nil
    }

    static func body(ofBlockComment text: String) -> String {
        var bytes = Array(text.utf8)
        if bytes.count >= 4 { bytes = Array(bytes[2..<(bytes.count - 2)]) } else { return "" }
        if bytes.first == 0x20 { bytes.removeFirst() }
        if bytes.last == 0x20 { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// `replacingAnnotation(with:)` confined to the part of the trivia that
    /// shares a line with the preceding token, so that comments on later
    /// lines — section markers, for instance — are never mistaken for the
    /// annotation.
    func replacingSameLineAnnotation(with body: String) throws -> Trivia {
        guard let (sameLine, rest) = splitFirstLine() else { return try replacingAnnotation(with: body) }
        return try sameLine.replacingAnnotation(with: body) + rest
    }
}
