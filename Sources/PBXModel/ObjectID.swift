/// The key of an object in the `objects` dictionary. IDs are opaque strings:
/// any length, any alphabet, compared byte for byte — never by prefix, never
/// assumed to be hexadecimal.
public struct ObjectID: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral, Comparable {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(stringLiteral value: String) { self.rawValue = value }

    public var description: String { rawValue }

    /// Byte-exact equality; `String ==` would also accept canonically
    /// equivalent text.
    public static func == (lhs: ObjectID, rhs: ObjectID) -> Bool {
        lhs.rawValue.utf8.elementsEqual(rhs.rawValue.utf8)
    }

    public func hash(into hasher: inout Hasher) {
        for byte in rawValue.utf8 { hasher.combine(byte) }
    }

    /// Byte-wise order: the order Xcode sorts a section by.
    public static func < (lhs: ObjectID, rhs: ObjectID) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }
}
