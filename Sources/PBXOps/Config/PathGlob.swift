/// A path glob over slash-separated segments (design D3): `*` and `?` match
/// within one segment, a segment that is exactly `**` matches zero or more
/// whole segments. Anchored at both ends; case-sensitive. Character classes,
/// brace expansion, empty segments and `**` mixed into a segment are
/// rejected when the pattern is compiled, so nobody relies on them by
/// accident.
public struct PathGlob: Equatable, Hashable, Sendable, CustomStringConvertible {
    public struct Error: Swift.Error, Equatable, CustomStringConvertible {
        public let pattern: String
        public let reason: String
        public var description: String { "unsupported glob \"\(pattern)\": \(reason)" }
    }

    private enum Segment: Equatable, Hashable {
        case any            // `**`
        case wildcard([Unicode.Scalar])  // `*`, `?` and literals
    }

    public let pattern: String
    private let segments: [Segment]

    public var description: String { pattern }

    public init(_ pattern: String) throws {
        self.pattern = pattern
        guard !pattern.isEmpty else { throw Error(pattern: pattern, reason: "the pattern is empty") }
        for scalar in pattern.unicodeScalars where "[]{}".unicodeScalars.contains(scalar) {
            throw Error(pattern: pattern, reason: "'\(scalar)' is not supported; only *, ** and ? are")
        }
        var segments: [Segment] = []
        for piece in pattern.split(separator: "/", omittingEmptySubsequences: false) {
            if piece.isEmpty {
                throw Error(pattern: pattern, reason: "an empty path segment (a leading, trailing or doubled slash) is not supported")
            }
            if piece == "**" {
                segments.append(.any)
            } else if piece.contains("**") {
                throw Error(pattern: pattern, reason: "** must be a whole path segment")
            } else {
                segments.append(.wildcard(Array(piece.unicodeScalars)))
            }
        }
        self.segments = segments
    }

    /// Whether `path` (slash-separated, no leading slash) matches.
    public func matches(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map { Array($0.unicodeScalars) }
        return PathGlob.match(segments[...], parts[...])
    }

    private static func match(_ segments: ArraySlice<Segment>, _ parts: ArraySlice<[Unicode.Scalar]>) -> Bool {
        guard let segment = segments.first else { return parts.isEmpty }
        switch segment {
        case .any:
            // Zero or more segments: try every split point.
            var rest = parts
            while true {
                if match(segments.dropFirst(), rest) { return true }
                guard !rest.isEmpty else { return false }
                rest = rest.dropFirst()
            }
        case .wildcard(let text):
            guard let part = parts.first, matchSegment(text[...], part[...]) else { return false }
            return match(segments.dropFirst(), parts.dropFirst())
        }
    }

    private static func matchSegment(_ pattern: ArraySlice<Unicode.Scalar>, _ text: ArraySlice<Unicode.Scalar>) -> Bool {
        guard let scalar = pattern.first else { return text.isEmpty }
        switch scalar {
        case "*":
            var rest = text
            while true {
                if matchSegment(pattern.dropFirst(), rest) { return true }
                guard !rest.isEmpty else { return false }
                rest = rest.dropFirst()
            }
        case "?":
            guard !text.isEmpty else { return false }
            return matchSegment(pattern.dropFirst(), text.dropFirst())
        default:
            guard text.first == scalar else { return false }
            return matchSegment(pattern.dropFirst(), text.dropFirst())
        }
    }
}
