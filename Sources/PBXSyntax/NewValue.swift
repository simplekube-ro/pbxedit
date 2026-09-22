/// Content to be written into a tree. It carries no layout: the edit that
/// writes it formats it like its neighbours (design D6) and quotes its strings
/// canonically (design D5).
public struct NewValue: Sendable, Equatable {
    enum Content: Sendable, Equatable {
        case string(String)
        case array([NewValue])
        case dictionary([NewEntry])
    }

    let content: Content

    /// The annotation written after the value and before its separator, as in
    /// `B2 /* Foo.swift */;`. Comments are never copied from siblings.
    public var comment: String?

    public static func string(_ value: String, comment: String? = nil) -> NewValue {
        NewValue(content: .string(value), comment: comment)
    }

    public static func array(_ elements: [NewValue], comment: String? = nil) -> NewValue {
        NewValue(content: .array(elements), comment: comment)
    }

    public static func dictionary(_ entries: [NewEntry], comment: String? = nil) -> NewValue {
        NewValue(content: .dictionary(entries), comment: comment)
    }

    /// How many containers deep the value goes; a string is 0.
    var containerDepth: Int {
        switch content {
        case .string: return 0
        case .array(let elements): return 1 + (elements.map(\.containerDepth).max() ?? 0)
        case .dictionary(let entries): return 1 + (entries.map(\.value.containerDepth).max() ?? 0)
        }
    }
}

/// A dictionary entry to be written.
public struct NewEntry: Sendable, Equatable {
    public var key: String
    /// The annotation written after the key, as in `A1 /* Foo.swift */ = {`.
    public var keyComment: String?
    public var value: NewValue

    public init(_ key: String, comment keyComment: String? = nil, _ value: NewValue) {
        self.key = key
        self.keyComment = keyComment
        self.value = value
    }
}

/// Where an insertion goes.
public enum InsertPosition: Sendable, Equatable {
    case first
    case last
    /// At this index; `count` means last.
    case at(Int)
    /// Directly above the sibling with this key (dictionary) or string value
    /// (array), below any comments that precede it.
    case before(String)
    /// Directly below the sibling with this key or string value.
    case after(String)
}

/// Whether a new container value is written on one line or across lines.
public enum NewValueLayout: Sendable, Equatable {
    /// As the template sibling's value is laid out. With no container to copy
    /// from: across lines when the new item starts a line, otherwise on one line.
    case likeSibling
    case singleLine
    case multiLine
}

public enum EditError: Error, Sendable, Equatable {
    case pathNotFound(SyntaxPath)
    case notADictionary(SyntaxPath)
    case notAnArray(SyntaxPath)
    /// No sibling with this key or string value.
    case siblingNotFound(String)
    case indexOutOfRange(Int)
    case duplicateKey(String)
    /// A comment containing `*/` cannot be written.
    case invalidComment(String)
    /// The edit would nest containers deeper than `SyntaxTree.maximumNestingDepth`.
    case nestingTooDeep
}
