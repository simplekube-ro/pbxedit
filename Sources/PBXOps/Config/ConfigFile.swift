import Foundation
import PBXModel

/// A decoded `.pbxedit.yml` together with where it lives: `project`,
/// `lint.baseline` and every glob are relative to its directory (design D7).
public struct ConfigFile: Equatable, Sendable {
    public static let fileName = ".pbxedit.yml"

    public let url: URL
    public let config: Config

    public init(url: URL, config: Config) {
        self.url = url
        self.config = config
    }

    /// The directory the file's paths are relative to.
    public var directory: URL { url.deletingLastPathComponent() }

    /// `project`, resolved against the directory.
    public var projectURL: URL? {
        config.project.map { URL(fileURLWithPath: $0, relativeTo: directory).standardizedFileURL }
    }

    /// `lint.baseline`, resolved against the directory.
    public var baselineURL: URL? {
        config.lint.baseline.map { URL(fileURLWithPath: $0, relativeTo: directory).standardizedFileURL }
    }

    /// Reads and decodes the file at `url`. Errors are `ConfigError`s naming
    /// the path as given.
    public static func load(_ url: URL) throws -> ConfigFile {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError(file: url.path, line: nil, message: "cannot read the configuration: \(error.localizedDescription)")
        }
        return ConfigFile(url: url, config: try Config.parse(text, file: url.path))
    }

    /// The nearest `.pbxedit.yml` in `directory` or its ancestors, or `nil`
    /// (spec: Discovery).
    public static func discover(from directory: URL) throws -> ConfigFile? {
        var current = directory.standardizedFileURL
        while true {
            let candidate = current.appendingPathComponent(fileName)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return try load(candidate)
            }
            // `deletingLastPathComponent()` of `/` is `/..`, so stop on the root explicitly.
            guard current.path != "/", current.pathComponents.count > 1 else { return nil }
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }

    /// Binds the file to a project's source root (design D7): the file's
    /// directory must be that root or an ancestor of it, and the root's path
    /// relative to the directory becomes the prefix globs are matched under.
    public func bind(sourceRoot: URL) throws -> BoundConfig {
        let base = directory.standardizedFileURL.path
        let root = sourceRoot.standardizedFileURL.path
        if root == base { return BoundConfig(file: self, prefix: "") }
        let baseWithSlash = base.hasSuffix("/") ? base : base + "/"
        guard root.hasPrefix(baseWithSlash) else {
            throw ConfigError(file: url.path, line: nil,
                              message: "the configuration's directory \(base) is neither the project's source root \(root) nor an ancestor of it")
        }
        return BoundConfig(file: self, prefix: String(root.dropFirst(baseWithSlash.count)) + "/")
    }
}

/// A configuration as seen from one project: globs re-based to the source
/// root, and the project-dependent checks.
public struct BoundConfig: Equatable, Sendable {
    public let file: ConfigFile
    /// `""` when the configuration lies at the source root, else the root's
    /// path relative to the configuration's directory with a trailing slash.
    public let prefix: String

    public init(file: ConfigFile, prefix: String) {
        self.file = file
        self.prefix = prefix
    }

    public var config: Config { file.config }

    /// The layer `Conventions` consults between flags and inference.
    public var conventions: ConfigConventions { ConfigConventions(rules: config.rules, prefix: prefix) }

    /// The filter on findings (design D5).
    public var exemptions: Exemptions { Exemptions(config.lint.exempt, prefix: prefix) }

    /// Every target a rule names must be one of `targets` (spec: Target that
    /// does not exist). Runs after the project loads, before any planner.
    public func validate(targets: [String]) throws {
        let available = targets.sorted()
        for rule in config.rules {
            for name in rule.targets ?? [] where !available.contains(where: { $0.utf8.elementsEqual(name.utf8) }) {
                throw ConfigError(file: file.url.path, line: rule.line,
                                  message: "rule \(rule.position) (\(rule.match.pattern)) names the target \(name), which the project does not have; the project's targets are: \(available.joined(separator: ", "))")
            }
        }
    }
}

/// The configuration's answers to the two questions planners ask through
/// `Conventions` (design D1, D2): the first rule in file order that matches
/// the path and sets the attribute supplies it.
public struct ConfigConventions: Equatable, Sendable {
    public let rules: [Config.Rule]
    public let prefix: String

    public init(rules: [Config.Rule], prefix: String = "") {
        self.rules = rules
        self.prefix = prefix
    }

    public func targets(for path: String) -> Decided<[String]>? {
        first(matching: path, setting: \.targets)
    }

    public func platformFilters(for path: String) -> Decided<[String]>? {
        first(matching: path, setting: \.platformFilters)
    }

    private func first(matching path: String, setting attribute: KeyPath<Config.Rule, [String]?>) -> Decided<[String]>? {
        let rebased = prefix + path
        for rule in rules {
            guard let value = rule[keyPath: attribute], rule.match.matches(rebased) else { continue }
            return Decided(value, source: .config(rule: rule.position, glob: rule.match.pattern))
        }
        return nil
    }
}

/// `lint.exempt` applied to findings (design D5): a finding is exempt when
/// its rule is listed and its path matches one of the rule's globs.
public struct Exemptions: Equatable, Sendable {
    public let entries: [RuleID: [PathGlob]]
    public let prefix: String

    public init(_ entries: [RuleID: [PathGlob]], prefix: String = "") {
        self.entries = entries
        self.prefix = prefix
    }

    public var isEmpty: Bool { entries.values.allSatisfy(\.isEmpty) }

    public func exempts(_ finding: Finding) -> Bool {
        guard let path = finding.path else { return false }
        return match(finding.rule, path: path) != nil
    }

    /// The first glob under `rule` that matches `path`, for provenance;
    /// `nil` when the path is not exempt from that rule.
    public func match(_ rule: RuleID, path: String) -> PathGlob? {
        guard let globs = entries[rule] else { return nil }
        let rebased = prefix + path
        return globs.first { $0.matches(rebased) }
    }

    /// The findings that stand, and the ones suppressed, each in their
    /// original order.
    public func apply(to findings: [Finding]) -> (kept: [Finding], exempt: [Finding]) {
        var kept: [Finding] = []
        var exempt: [Finding] = []
        for finding in findings {
            if exempts(finding) { exempt.append(finding) } else { kept.append(finding) }
        }
        return (kept, exempt)
    }
}
