/// Edit primitives: insert, remove and replace, in dictionaries and arrays.
///
/// An edit changes the tokens of the item it names, that item's separators
/// and trivia, and nothing else, so every other byte serializes as it was
/// read. A failed edit leaves the tree unchanged.
extension SyntaxTree {
    /// Inserts an element into the array at `path`.
    public mutating func insert(
        _ element: NewValue, intoArrayAt path: SyntaxPath, position: InsertPosition = .last,
        layout: NewValueLayout = .likeSibling
    ) throws {
        try checkDepth(path.count + 1 + element.containerDepth)
        try mutate(at: path) { node in
            guard case .array(var array) = node else { throw EditError.notAnArray(path) }
            let (index, aboveNext) = try SyntaxTree.resolve(position, count: array.elements.count) {
                array.firstIndex(ofString: $0)
            }
            let placement = Placement.make(in: array, at: index, aboveNext: aboveNext)
            let style = SyntaxTree.style(for: element, placement: placement, in: array, layout: layout)
            let isLast = index == array.elements.count
            let lastHasComma = array.elements.last.map { $0.comma != nil } ?? true
            var built = try style.builder.element(
                element, leading: placement.newLeading, lineIndent: style.lineIndent, comma: !isLast || lastHasComma)
            var closeLeading = placement.closeLeading ?? array.rightParen.leadingTrivia
            var previousComma: Token?
            if isLast, !lastHasComma {
                // The array has no trailing comma; keep it that way. The old
                // last element gains a comma, which takes over whatever shared
                // that element's line, and the new element's annotation goes
                // where the old one's was: before the closing delimiter.
                let parts = closeLeading.splitFirstLine() ?? (closeLeading.withoutTrailingWhitespace, Trivia(unchecked: closeLeading.trailingWhitespace))
                previousComma = .punctuation(.comma, leadingTrivia: parts.sameLine)
                closeLeading = try element.comment.map { try Trivia.annotation($0) + parts.rest } ?? parts.rest
                built.comma = nil
            }
            // Nothing below throws: the node is only released once the edit is certain.
            node = SyntaxTree.placeholder
            if let previousComma, let last = array.elements.indices.last { array.elements[last].comma = previousComma }
            if let displaced = placement.displacedLeading, array.elements.indices.contains(index) {
                array.setItemLeading(index, displaced)
            }
            array.rightParen.leadingTrivia = closeLeading
            array.elements.insert(built, at: index)
            node = .array(array)
        }
    }

    /// Inserts an entry into the dictionary at `path`. A key that is already
    /// present is an error, never a second entry.
    public mutating func insert(
        _ entry: NewEntry, intoDictionaryAt path: SyntaxPath, position: InsertPosition = .last,
        layout: NewValueLayout = .likeSibling
    ) throws {
        try checkDepth(path.count + 1 + entry.value.containerDepth)
        try mutate(at: path) { node in
            guard case .dictionary(var dictionary) = node else { throw EditError.notADictionary(path) }
            guard dictionary.firstIndex(ofKey: entry.key) == nil else { throw EditError.duplicateKey(entry.key) }
            let (index, aboveNext) = try SyntaxTree.resolve(position, count: dictionary.entries.count) {
                dictionary.firstIndex(ofKey: $0)
            }
            let placement = Placement.make(in: dictionary, at: index, aboveNext: aboveNext)
            let style = SyntaxTree.style(for: entry.value, placement: placement, in: dictionary, layout: layout)
            let built = try style.builder.entry(entry, leading: placement.newLeading, lineIndent: style.lineIndent)
            node = SyntaxTree.placeholder
            if let displaced = placement.displacedLeading, dictionary.entries.indices.contains(index) {
                dictionary.setItemLeading(index, displaced)
            }
            if let closeLeading = placement.closeLeading { dictionary.rightBrace.leadingTrivia = closeLeading }
            dictionary.entries.insert(built, at: index)
            node = .dictionary(dictionary)
        }
    }

    /// Removes the first entry whose key is byte-for-byte `key`, with its
    /// separators, its annotation comments and its own line. Comments and
    /// blank lines above the entry stay.
    public mutating func removeEntry(forKey key: String, fromDictionaryAt path: SyntaxPath) throws {
        try mutate(at: path) { node in
            guard case .dictionary(var dictionary) = node else { throw EditError.notADictionary(path) }
            guard let index = dictionary.firstIndex(ofKey: key) else { throw EditError.pathNotFound(path + [.key(key)]) }
            node = SyntaxTree.placeholder
            let removed = dictionary.entries.remove(at: index)
            SyntaxTree.closeGap(leftBy: removed.key.token.leadingTrivia, at: index, in: &dictionary)
            node = .dictionary(dictionary)
        }
    }

    /// Removes the element at `index`; see `removeEntry(forKey:fromDictionaryAt:)`.
    public mutating func removeElement(at index: Int, fromArrayAt path: SyntaxPath) throws {
        try mutate(at: path) { node in
            guard case .array(var array) = node else { throw EditError.notAnArray(path) }
            guard array.elements.indices.contains(index) else { throw EditError.indexOutOfRange(index) }
            node = SyntaxTree.placeholder
            SyntaxTree.remove(at: index, from: &array)
            node = .array(array)
        }
    }

    /// Removes the first element that is a string equal, byte for byte, to `value`.
    public mutating func removeElement(equalTo value: String, fromArrayAt path: SyntaxPath) throws {
        guard case .array(let array)? = node(at: path) else {
            throw node(at: path) == nil ? EditError.pathNotFound(path) : EditError.notAnArray(path)
        }
        guard let index = array.firstIndex(ofString: value) else { throw EditError.siblingNotFound(value) }
        try removeElement(at: index, fromArrayAt: path)
    }

    /// Replaces the value at `path`. Only the value's bytes change: the key,
    /// the separators and the surrounding trivia stay. When `newValue` has a
    /// comment, the value's annotation comment is replaced or added too; the
    /// root has no separator, so a comment on a new root is not written.
    public mutating func replaceValue(
        at path: SyntaxPath, with newValue: NewValue, layout: NewValueLayout = .likeSibling
    ) throws {
        try checkDepth(path.count + newValue.containerDepth)
        guard let last = path.last else {
            root = try SyntaxTree.replacement(for: root, itemLeading: root.leadingTrivia, with: newValue, layout: layout)
            return
        }
        let parent = Array(path.dropLast())
        try mutate(at: parent) { node in
            switch (node, last) {
            case (.dictionary(var dictionary), .key(let key)):
                guard let index = dictionary.firstIndex(ofKey: key) else { throw EditError.pathNotFound(path) }
                var entry = dictionary.entries[index]
                entry.value = try SyntaxTree.replacement(
                    for: entry.value, itemLeading: entry.key.token.leadingTrivia, with: newValue, layout: layout)
                if let comment = newValue.comment {
                    entry.semicolon.leadingTrivia = try entry.semicolon.leadingTrivia.replacingAnnotation(with: comment)
                }
                node = SyntaxTree.placeholder
                dictionary.entries[index] = entry
                node = .dictionary(dictionary)
            case (.array(var array), .index(let index)):
                guard array.elements.indices.contains(index) else { throw EditError.pathNotFound(path) }
                var element = array.elements[index]
                element.value = try SyntaxTree.replacement(
                    for: element.value, itemLeading: element.value.leadingTrivia, with: newValue, layout: layout)
                var closeLeading = array.rightParen.leadingTrivia
                if let comment = newValue.comment {
                    if var comma = element.comma {
                        comma.leadingTrivia = try comma.leadingTrivia.replacingAnnotation(with: comment)
                        element.comma = comma
                    } else {
                        closeLeading = try closeLeading.replacingAnnotation(with: comment)
                    }
                }
                node = SyntaxTree.placeholder
                array.elements[index] = element
                array.rightParen.leadingTrivia = closeLeading
                node = .array(array)
            default:
                throw EditError.pathNotFound(path)
            }
        }
    }
}

// MARK: - Addressing

extension SyntaxTree {
    /// Stands in for a node while its payload is edited, so that the payload
    /// is uniquely referenced and an edit copies one entry array at most.
    fileprivate static let placeholder = Node.data(DataNode(token: Token(kind: .data, text: "<>")))

    private func checkDepth(_ depth: Int) throws {
        if depth > SyntaxTree.maximumNestingDepth { throw EditError.nestingTooDeep }
    }

    /// Runs `body` on the node at `path`, in place.
    private mutating func mutate(at path: SyntaxPath, _ body: (inout Node) throws -> Void) throws {
        try SyntaxTree.mutate(&root, path[...], fullPath: path, body)
    }

    private static func mutate(
        _ node: inout Node, _ path: ArraySlice<PathComponent>, fullPath: SyntaxPath,
        _ body: (inout Node) throws -> Void
    ) throws {
        guard let component = path.first else { return try body(&node) }
        switch (node, component) {
        case (.dictionary(var dictionary), .key(let key)):
            guard let index = dictionary.firstIndex(ofKey: key) else { throw EditError.pathNotFound(fullPath) }
            node = placeholder
            defer { node = .dictionary(dictionary) }
            try mutate(&dictionary.entries[index].value, path.dropFirst(), fullPath: fullPath, body)
        case (.array(var array), .index(let index)):
            guard array.elements.indices.contains(index) else { throw EditError.pathNotFound(fullPath) }
            node = placeholder
            defer { node = .array(array) }
            try mutate(&array.elements[index].value, path.dropFirst(), fullPath: fullPath, body)
        default:
            throw EditError.pathNotFound(fullPath)
        }
    }

    /// The insertion index, and whether the new item goes directly above the
    /// item now at that index rather than directly below the one before.
    private static func resolve(
        _ position: InsertPosition, count: Int, indexOf: (String) -> Int?
    ) throws -> (index: Int, aboveNext: Bool) {
        switch position {
        case .first:
            return (0, true)
        case .last:
            return (count, false)
        case .at(let index):
            guard index >= 0, index <= count else { throw EditError.indexOutOfRange(index) }
            return (index, index == 0)
        case .before(let sibling):
            guard let index = indexOf(sibling) else { throw EditError.siblingNotFound(sibling) }
            return (index, true)
        case .after(let sibling):
            guard let index = indexOf(sibling) else { throw EditError.siblingNotFound(sibling) }
            return (index + 1, false)
        }
    }
}

// MARK: - Layout of new values

extension SyntaxTree {
    fileprivate struct Style {
        var builder: NodeBuilder
        /// Non-nil when the new value is written across lines.
        var lineIndent: String?
    }

    /// Design D6: the layout of a new item's value, taken from the template sibling.
    fileprivate static func style(
        for value: NewValue, placement: Placement, in container: some ItemContainer, layout: NewValueLayout
    ) -> Style {
        let lineStart = placement.newLeading.lineStart
        let template = placement.templateIndex.map { (leading: container.itemLeading($0), value: container.itemValue($0)) }
        let multiLine: Bool
        switch layout {
        case .singleLine: multiLine = false
        case .multiLine: multiLine = true
        case .likeSibling:
            if lineStart == nil {
                multiLine = false
            } else if let template, template.value.isContainer {
                multiLine = template.value.isMultiLine
            } else {
                multiLine = true
            }
        }
        var unit = "\t"
        if let template, template.value.isMultiLine,
           let outer = template.leading.lineStart?.indent, let inner = template.value.firstItemIndent,
           inner.utf8.count > outer.utf8.count, inner.hasPrefix(outer) {
            unit = String(inner.dropFirst(outer.count))
        } else if let inner = lineStart?.indent, let outer = container.closeLeading.lineStart?.indent,
                  inner.utf8.count > outer.utf8.count, inner.hasPrefix(outer) {
            unit = String(inner.dropFirst(outer.count))
        }
        return Style(
            builder: NodeBuilder(newline: lineStart?.newline ?? "\n", unit: unit),
            lineIndent: multiLine ? (lineStart?.indent ?? "") : nil)
    }

    /// The node that replaces `old`, keeping `old`'s leading trivia and, for a
    /// container, its layout.
    fileprivate static func replacement(
        for old: Node, itemLeading: Trivia, with newValue: NewValue, layout: NewValueLayout
    ) throws -> Node {
        let lineStart = itemLeading.lineStart
        let multiLine: Bool
        switch layout {
        case .singleLine: multiLine = false
        case .multiLine: multiLine = true
        case .likeSibling: multiLine = old.isMultiLine
        }
        var unit = "\t"
        if let outer = lineStart?.indent, let inner = old.firstItemIndent, inner.utf8.count > outer.utf8.count,
           inner.hasPrefix(outer) {
            unit = String(inner.dropFirst(outer.count))
        }
        let builder = NodeBuilder(newline: lineStart?.newline ?? "\n", unit: unit)
        return try builder.node(newValue, leading: old.leadingTrivia, lineIndent: multiLine ? (lineStart?.indent ?? "") : nil)
    }
}

// MARK: - Removal

extension SyntaxTree {
    /// After the item at `index` was removed: hands the comments and blank
    /// lines that preceded the item's own line to the token that now follows.
    fileprivate static func closeGap(leftBy leading: Trivia, at index: Int, in container: inout some ItemContainer) {
        let nextIsItem = index < container.itemCount
        let next = nextIsItem ? container.itemLeading(index) : container.closeLeading
        let (prefix, own) = leading.splitOwnLine()
        let merged: Trivia
        if index == 0, leading.lineStart == nil, next.lineStart == nil, next.isWhitespaceOnly {
            // The first item of a one-line container: what follows moves up
            // against the opening delimiter, as the removed item was.
            merged = prefix + own
        } else {
            merged = prefix + next
        }
        if nextIsItem {
            container.setItemLeading(index, merged)
        } else {
            container.closeLeading = merged
        }
    }

    fileprivate static func remove(at index: Int, from array: inout ArrayNode) {
        let removed = array.elements.remove(at: index)
        if removed.comma == nil {
            // The last element of an array without a trailing comma. Its
            // annotation, if any, shares its line but belongs to the closing
            // delimiter's trivia; it goes with the element. The element before
            // becomes the last and gives up its comma, keeping the style.
            let close = array.rightParen.leadingTrivia
            array.rightParen.leadingTrivia = close.splitFirstLine()?.rest ?? Trivia(unchecked: close.trailingWhitespace)
            if let previous = array.elements.indices.last, let comma = array.elements[previous].comma {
                array.elements[previous].comma = nil
                array.rightParen.leadingTrivia = comma.leadingTrivia + array.rightParen.leadingTrivia
            }
        }
        closeGap(leftBy: removed.value.leadingTrivia, at: index, in: &array)
    }
}
