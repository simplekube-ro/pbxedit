/// The platform names `platformFilters` may hold: rule S4's list, shared
/// with `--platform` validation so the two can never disagree.
public enum PlatformFilters {
    /// In the order Xcode's target editor lists them.
    public static let known = ["ios", "maccatalyst", "macos", "tvos", "watchos", "xros", "driverkit"]

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
