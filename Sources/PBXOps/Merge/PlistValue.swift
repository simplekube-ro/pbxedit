import PBXSyntax
import PBXModel

/// A value of the tree without its trivia (merge design D8): what two
/// versions of a project are compared by, wherever formatting must not count.
public indirect enum PlistValue: Hashable, Sendable, CustomStringConvertible {
    public struct Entry: Hashable, Sendable {
        public let key: String
        public let value: PlistValue

        public init(key: String, value: PlistValue) {
            self.key = key
            self.value = value
        }

        public static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.key.utf8.elementsEqual(rhs.key.utf8) && lhs.value == rhs.value
        }

        public func hash(into hasher: inout Hasher) {
            for byte in key.utf8 { hasher.combine(byte) }
            hasher.combine(value)
        }
    }

    case string(String)
    case data([UInt8])
    case array([PlistValue])
    /// Entries in source order, duplicates included.
    case dictionary([Entry])

    public init(_ node: Node) {
        switch node {
        case .string(let string): self = .string(string.value)
        case .data(let data): self = .data(data.bytes)
        case .array(let array): self = .array(array.elements.map { PlistValue($0.value) })
        case .dictionary(let dictionary): self = .dictionary(dictionary.entries.map { Entry(key: $0.key.value, value: PlistValue($0.value)) })
        }
    }

    /// Strings compare byte for byte; `String ==` would accept canonically
    /// equivalent text, which the file does not.
    public static func == (lhs: PlistValue, rhs: PlistValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a.utf8.elementsEqual(b.utf8)
        case (.data(let a), .data(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.dictionary(let a), .dictionary(let b)): return a == b
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .string(let value):
            hasher.combine(0)
            for byte in value.utf8 { hasher.combine(byte) }
        case .data(let bytes):
            hasher.combine(1)
            hasher.combine(bytes)
        case .array(let elements):
            hasher.combine(2)
            hasher.combine(elements)
        case .dictionary(let entries):
            hasher.combine(3)
            hasher.combine(entries)
        }
    }

    /// The value of the first entry with `key`, as every lookup reads it.
    public subscript(key: String) -> PlistValue? {
        guard case .dictionary(let entries) = self else { return nil }
        return entries.first { $0.key.utf8.elementsEqual(key.utf8) }?.value
    }

    /// Old-style plist text, on one line: for reports.
    public var description: String {
        switch self {
        case .string(let value): return StringNode.canonicalText(value)
        case .data(let bytes): return "<" + bytes.map { String($0, radix: 16).leftPadded(to: 2) }.joined() + ">"
        case .array(let elements): return "(" + elements.map { $0.description + ", " }.joined() + ")"
        case .dictionary(let entries):
            return "{" + entries.map { PlistValue.string($0.key).description + " = " + $0.value.description + "; " }.joined() + "}"
        }
    }

    /// Entries whose key repeats an earlier key of the same dictionary,
    /// anywhere in the tree (merge design D7): a leaf map, which keeps the
    /// first, cannot see them.
    public static func duplicateKeyCount(in node: Node) -> Int {
        switch node {
        case .string, .data: return 0
        case .array(let array): return array.elements.reduce(0) { $0 + duplicateKeyCount(in: $1.value) }
        case .dictionary(let dictionary):
            var seen: Set<[UInt8]> = []
            var count = 0
            for entry in dictionary.entries {
                if !seen.insert(Array(entry.key.value.utf8)).inserted { count += 1 }
                count += duplicateKeyCount(in: entry.value)
            }
            return count
        }
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}

/// Where a leaf sits: the keys from the root down (merge design D8). Under
/// `objects`, the second key is the object's ID.
public struct LeafPath: Hashable, Sendable, Comparable, CustomStringConvertible, ExpressibleByArrayLiteral {
    public let components: [String]

    public init(_ components: [String]) { self.components = components }

    public init(arrayLiteral elements: String...) { self.components = elements }

    public static func == (lhs: LeafPath, rhs: LeafPath) -> Bool {
        lhs.components.count == rhs.components.count
            && zip(lhs.components, rhs.components).allSatisfy { $0.utf8.elementsEqual($1.utf8) }
    }

    public func hash(into hasher: inout Hasher) {
        for component in components {
            for byte in component.utf8 { hasher.combine(byte) }
            hasher.combine(0xFF as UInt8)
        }
    }

    public static func < (lhs: LeafPath, rhs: LeafPath) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components) { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    /// The object the leaf belongs to, for a leaf under `objects`.
    public var objectID: ObjectID? {
        guard components.count >= 2, components[0] == Project.objectsKey else { return nil }
        return ObjectID(components[1])
    }

    /// The keys below the object, dot-separated: `buildSettings.SWIFT_VERSION`.
    public var keyPath: String {
        objectID == nil ? components.joined(separator: ".") : components.dropFirst(2).joined(separator: ".")
    }

    /// `<ID> buildSettings.SWIFT_VERSION` under `objects`, else the dotted keys.
    public var description: String {
        guard let id = objectID else { return keyPath }
        return keyPath.isEmpty ? id.rawValue : "\(id) \(keyPath)"
    }
}

/// Every leaf of a tree (merge design D8): a dictionary recurses per key,
/// the first entry winning; an array, a string, a data value and an empty
/// dictionary are each one leaf.
public struct PlistLeaves: Equatable, Sendable {
    /// In document order.
    public private(set) var paths: [LeafPath] = []
    public private(set) var values: [LeafPath: PlistValue] = [:]

    public init(_ tree: SyntaxTree) { self.init(PlistValue(tree.root)) }

    public init(_ project: Project) { self.init(project.tree) }

    public init(_ root: PlistValue) { collect(root, at: []) }

    /// With `depth`, a dictionary that many keys down is one leaf (the
    /// `wholeDictionaryLeaves` fault uses 3: each object's attributes).
    init(_ tree: SyntaxTree, depth: Int?) {
        self.depth = depth
        collect(PlistValue(tree.root), at: [])
    }

    private var depth: Int?

    public subscript(path: LeafPath) -> PlistValue? { values[path] }

    public subscript(components: [String]) -> PlistValue? { values[LeafPath(components)] }

    private mutating func collect(_ value: PlistValue, at path: [String]) {
        if case .dictionary(let entries) = value, !entries.isEmpty, depth.map({ path.count < $0 }) ?? true {
            var seen: Set<[UInt8]> = []
            for entry in entries where seen.insert(Array(entry.key.utf8)).inserted {
                collect(entry.value, at: path + [entry.key])
            }
            return
        }
        let leaf = LeafPath(path)
        paths.append(leaf)
        values[leaf] = value
    }
}
