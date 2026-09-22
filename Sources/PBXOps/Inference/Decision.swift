/// One attributable decision of a plan (design D4): what was decided for
/// which path, and where the value came from. Every decision is printed with
/// its provenance, for example `targets: AppTests (inferred, 94 siblings in AppTests/Views)`.
public struct Decision: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// A command-line flag.
        case flag
        /// Sibling inference over `siblings` files in `directory`; zero
        /// siblings means nothing in the directory took part (a first file
        /// joining a target from there).
        case inferred(siblings: Int, directory: String)
        /// The file-type table.
        case fileType
        /// Derived structurally from the group chain.
        case structure

        /// The provenance as printed after the value.
        public var description: String {
            switch self {
            case .flag: return "flag"
            case .inferred(let siblings, let directory):
                let where_ = directory.isEmpty ? "the source root" : directory
                switch siblings {
                case 0: return "inferred, no siblings in \(where_)"
                case 1: return "inferred, 1 sibling in \(where_)"
                default: return "inferred, \(siblings) siblings in \(where_)"
                }
            case .fileType: return "file type"
            case .structure: return "structure"
            }
        }

        /// A stable name for `--json`.
        public var kind: String {
            switch self {
            case .flag: return "flag"
            case .inferred: return "inferred"
            case .fileType: return "fileType"
            case .structure: return "structure"
            }
        }
    }

    /// The path argument the decision is about.
    public let path: String
    /// `targets`, `platformFilters`, `phase` or `location`.
    public let attribute: String
    /// The value as printed.
    public let value: String
    public let source: Source

    public init(path: String, attribute: String, value: String, source: Source) {
        self.path = path
        self.attribute = attribute
        self.value = value
        self.source = source
    }
}

/// A value together with where it came from, before it is rendered into a
/// `Decision`.
public struct Decided<Value> {
    public let value: Value
    public let source: Decision.Source

    public init(_ value: Value, source: Decision.Source) {
        self.value = value
        self.source = source
    }
}
