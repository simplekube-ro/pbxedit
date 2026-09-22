/// One step from a container to a child: a dictionary key or an array index.
public enum PathComponent: Sendable, Equatable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    CustomStringConvertible
{
    case key(String)
    case index(Int)

    public init(stringLiteral value: String) { self = .key(value) }

    public init(integerLiteral value: Int) { self = .index(value) }

    public var description: String {
        switch self {
        case .key(let key): return key
        case .index(let index): return "[\(index)]"
        }
    }
}

/// A structural address from the root (design D3). Keys are matched byte for
/// byte; a path stays valid across edits elsewhere in the tree.
public typealias SyntaxPath = [PathComponent]

extension Node {
    /// The child one step away, or `nil` when there is none.
    func child(_ component: PathComponent) -> Node? {
        switch (self, component) {
        case (.dictionary(let node), .key(let key)):
            return node[key]
        case (.array(let node), .index(let index)):
            return node.elements.indices.contains(index) ? node.elements[index].value : nil
        default:
            return nil
        }
    }
}

extension SyntaxTree {
    /// The node at `path`, or `nil` when the path does not resolve.
    public func node(at path: SyntaxPath) -> Node? {
        var node = root
        for component in path {
            guard let next = node.child(component) else { return nil }
            node = next
        }
        return node
    }
}
