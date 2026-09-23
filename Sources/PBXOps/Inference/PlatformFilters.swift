import PBXSyntax
import PBXModel

/// How a build file's platform filter is read, checked and written
/// (capability `platform-filters`): rule S4's list of names, shared with
/// `--platform` validation so the two can never disagree; the one reading
/// of the two keys Xcode has used; and the spelling Xcode 27 writes.
public enum PlatformFilters {
    /// In the order Xcode's target editor lists them.
    public static let known = ["ios", "maccatalyst", "macos", "tvos", "watchos", "xros", "driverkit"]

    /// The values Xcode 27 writes with the singular key, `platformFilter =
    /// <value>;`, when they are a build file's only filter (measured with
    /// Xcode 27.0, `Tests/Fixtures/xcode27/`); every other filter set is
    /// the `platformFilters` array.
    public static let singularValues = ["ios", "maccatalyst"]

    /// The build file's filters: the `platformFilters` array when present,
    /// else the single `platformFilter` as a one-element list, else none.
    /// Every reader in `PBXOps` goes through here (design D1).
    public static func read(from buildFile: BuildFile) -> [String] {
        buildFile.platformFilters ?? buildFile.platformFilter.map { [$0] } ?? []
    }

    /// How a filter set is spelled in the file: `platformFilter = <value>;`
    /// for exactly one of `singularValues`, `platformFilters = (…);` in the
    /// order given for any other non-empty set, neither key for none.
    public enum Spelling: Equatable, Sendable {
        case none
        case singular(String)
        case plural([String])

        /// The key the spelling writes, if any.
        public var key: String? {
            switch self {
            case .none: return nil
            case .singular: return PlatformFilters.singularKey
            case .plural: return PlatformFilters.pluralKey
            }
        }

        /// The value the spelling writes, if any.
        public var value: NewValue? {
            switch self {
            case .none: return nil
            case .singular(let name): return .string(name)
            case .plural(let names): return .array(names.map { .string($0) })
            }
        }
    }

    public static let singularKey = "platformFilter"
    public static let pluralKey = "platformFilters"

    /// The spelling Xcode 27 writes for `filters` (design D2). Every writer
    /// in `PBXOps` goes through here.
    public static func spelling(of filters: [String]) -> Spelling {
        if filters.isEmpty { return .none }
        if filters.count == 1, let only = filters.first, singularValues.contains(only) { return .singular(only) }
        return .plural(filters)
    }

    /// `filters` for reports: `none`, or the names joined by `, `.
    static func describe(_ filters: [String]) -> String {
        filters.isEmpty ? "none" : filters.joined(separator: ", ")
    }

    /// Parses `--platform`: `none` is the empty list; otherwise comma-separated
    /// known names. Throws `PlanError.unknownPlatform` for anything else.
    public static func parse(_ argument: String) throws -> [String] {
        let trimmed = argument.trimmingCharacters(in: .whitespaces)
        if trimmed == "none" || trimmed.isEmpty { return [] }
        var names: [String] = []
        for piece in trimmed.split(separator: ",") {
            let name = piece.trimmingCharacters(in: .whitespaces)
            guard known.contains(name) else { throw PlanError.unknownPlatform(name: name, known: known) }
            if !names.contains(name) { names.append(name) }
        }
        return names
    }
}
