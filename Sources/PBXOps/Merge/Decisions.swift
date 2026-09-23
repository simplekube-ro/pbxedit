import Foundation
import PBXModel

/// The decisions file (merge design D10): the choices for open units and
/// hunks, bound to the SHA-256 of the three inputs. The template is the
/// same object with every open key `null`.
public struct MergeDecisions: Equatable, Sendable, Codable {
    public struct Inputs: Equatable, Sendable, Codable {
        public let base: String
        public let ours: String
        public let theirs: String

        public init(base: String, ours: String, theirs: String) {
            self.base = base
            self.ours = ours
            self.theirs = theirs
        }

        /// Lower-case hex SHA-256 of each input's bytes.
        public init(base: [UInt8], ours: [UInt8], theirs: [UInt8]) {
            self.init(base: MergeHash.hex(base), ours: MergeHash.hex(ours), theirs: MergeHash.hex(theirs))
        }
    }

    public var inputs: Inputs
    /// Unit key → choice; `nil` is undecided.
    public var units: [String: String?]
    /// Hunk key → choice; `nil` is undecided.
    public var hunks: [String: String?]

    public init(inputs: Inputs, units: [String: String?] = [:], hunks: [String: String?] = [:]) {
        self.inputs = inputs
        self.units = units
        self.hunks = hunks
    }

    /// Decodes the file, or says why it cannot.
    public static func decode(_ data: Data) throws -> MergeDecisions {
        do {
            return try JSONDecoder().decode(MergeDecisions.self, from: data)
        } catch {
            throw MergeDecisionsError.malformed("\(error)")
        }
    }

    enum CodingKeys: String, CodingKey { case inputs, units, hunks }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputs = try container.decode(Inputs.self, forKey: .inputs)
        units = try container.decodeIfPresent([String: String?].self, forKey: .units) ?? [:]
        hunks = try container.decodeIfPresent([String: String?].self, forKey: .hunks) ?? [:]
    }

    /// Every key present, `null` for undecided.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(NullableMap(units), forKey: .units)
        try container.encode(NullableMap(hunks), forKey: .hunks)
    }

    /// A map whose `nil` values encode as `null` rather than disappearing.
    private struct NullableMap: Encodable {
        let map: [String: String?]
        init(_ map: [String: String?]) { self.map = map }

        struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            for key in map.keys.sorted() {
                if let value = map[key] ?? nil {
                    try container.encode(value, forKey: Key(stringValue: key))
                } else {
                    try container.encodeNil(forKey: Key(stringValue: key))
                }
            }
        }
    }
}

/// Why a decisions file cannot be applied (spec: Decisions round trip): exit `2`.
public enum MergeDecisionsError: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case otherInputs
    case unknownKey(String)
    case refusedChoice(key: String, choice: String, offered: [String])

    public var description: String {
        switch self {
        case .malformed(let message): return "the decisions file is not a decisions object: \(message)"
        case .otherInputs: return "the decisions are for other inputs: their SHA-256 do not match base, ours and theirs"
        case .unknownKey(let key): return "decision \(key) matches no open unit or hunk"
        case .refusedChoice(let key, let choice, let offered):
            return "decision \(key): \(choice) is not offered; choose \(offered.joined(separator: " or "))"
        }
    }
}
