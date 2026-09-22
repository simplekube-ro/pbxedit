import Yams

/// Why a configuration file was refused: the file, the line (when one is
/// known) and what was expected. Rendered `<file>:<line>: <message>`.
public struct ConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    public let file: String
    public let line: Int?
    public let message: String

    public init(file: String, line: Int?, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String {
        if let line { return "\(file):\(line): \(message)" }
        return "\(file): \(message)"
    }
}

/// The contents of `.pbxedit.yml` (`docs/design.md` § Config), decoded
/// strictly (design D4): every key known, every value of the right kind,
/// every name checked against the lists the tool already holds.
public struct Config: Equatable, Sendable {
    /// One entry of `rules`: a glob and the attributes it supplies.
    public struct Rule: Equatable, Sendable {
        public static let keys = ["match", "targets", "platformFilters"]

        /// 1-based, in file order: what the output calls "rule 2".
        public let position: Int
        /// The line the entry starts on.
        public let line: Int
        public let match: PathGlob
        public let targets: [String]?
        public let platformFilters: [String]?

        public init(position: Int, line: Int, match: PathGlob, targets: [String]? = nil, platformFilters: [String]? = nil) {
            self.position = position
            self.line = line
            self.match = match
            self.targets = targets
            self.platformFilters = platformFilters
        }
    }

    /// The `lint` section.
    public struct Lint: Equatable, Sendable {
        public static let keys = ["baseline", "exempt"]

        public var baseline: String?
        public var exempt: [RuleID: [PathGlob]]

        public init(baseline: String? = nil, exempt: [RuleID: [PathGlob]] = [:]) {
            self.baseline = baseline
            self.exempt = exempt
        }
    }

    public static let keys = ["project", "rules", "lint"]
    /// The rules whose findings carry a path (spec: Path exemptions).
    public static let exemptibleRules: [RuleID] = [.M3, .M6, .D1, .D2]

    public var project: String?
    public var rules: [Rule]
    public var lint: Lint

    public init(project: String? = nil, rules: [Rule] = [], lint: Lint = Lint()) {
        self.project = project
        self.rules = rules
        self.lint = lint
    }

    // MARK: Decoding

    /// Decodes `text`; `file` is only for messages.
    public static func parse(_ text: String, file: String) throws -> Config {
        let root: Node?
        do {
            root = try Yams.compose(yaml: text)
        } catch let error as YamlError {
            throw ConfigError(file: file, line: Config.line(of: error), message: "malformed YAML: \(Config.problem(of: error))")
        } catch {
            throw ConfigError(file: file, line: nil, message: "malformed YAML: \(error)")
        }
        guard let root else { return Config() }
        let decoder = Decoder(file: file)
        var config = Config()
        for (key, value) in try decoder.mapping(root, keys: keys, what: "the configuration") {
            switch key {
            case "project":
                config.project = try decoder.string(value, key: key)
            case "rules":
                var rules: [Rule] = []
                for (index, entry) in try decoder.list(value, key: key).enumerated() {
                    rules.append(try decoder.rule(entry, position: index + 1))
                }
                config.rules = rules
            case "lint":
                config.lint = try decoder.lint(value)
            default:
                break  // `mapping` has already rejected it.
            }
        }
        return config
    }

    private struct Decoder {
        let file: String

        func error(_ node: Node?, _ message: String) -> ConfigError {
            ConfigError(file: file, line: node?.mark?.line, message: message)
        }

        /// The pairs of a mapping whose keys are all in `keys`, in file order.
        func mapping(_ node: Node, keys: [String], what: String) throws -> [(key: String, value: Node)] {
            guard let mapping = node.mapping else { throw error(node, "expected a mapping for \(what)") }
            var pairs: [(key: String, value: Node)] = []
            for (keyNode, value) in mapping {
                guard let key = keyNode.scalar?.string else { throw error(keyNode, "expected a string key in \(what)") }
                guard keys.contains(key) else {
                    throw error(keyNode, "unknown key '\(key)' in \(what); allowed keys: \(keys.joined(separator: ", "))")
                }
                pairs.append((key, value))
            }
            return pairs
        }

        func string(_ node: Node, key: String) throws -> String {
            guard let scalar = node.scalar, !scalar.string.isEmpty, node.tag != Tag(.null) else {
                throw error(node, "expected a string for '\(key)'")
            }
            return scalar.string
        }

        func list(_ node: Node, key: String) throws -> [Node] {
            guard let sequence = node.sequence else { throw error(node, "expected a list for '\(key)'") }
            return Array(sequence)
        }

        func strings(_ node: Node, key: String) throws -> [String] {
            var strings: [String] = []
            for entry in try list(node, key: key) {
                guard let scalar = entry.scalar, !scalar.string.isEmpty, entry.tag != Tag(.null) else {
                    throw error(entry.scalar == nil ? entry : node, "expected a list of strings for '\(key)'")
                }
                strings.append(scalar.string)
            }
            return strings
        }

        func glob(_ pattern: String, at node: Node) throws -> PathGlob {
            do {
                return try PathGlob(pattern)
            } catch let failure as PathGlob.Error {
                throw error(node, failure.description)
            }
        }

        func rule(_ node: Node, position: Int) throws -> Rule {
            let what = "rule \(position)"
            var match: PathGlob?
            var targets: [String]?
            var platformFilters: [String]?
            for (key, value) in try mapping(node, keys: Rule.keys, what: what) {
                switch key {
                case "match":
                    match = try glob(try string(value, key: key), at: value)
                case "targets":
                    targets = try strings(value, key: key)
                case "platformFilters":
                    let names = try strings(value, key: key)
                    for name in names where !PlatformFilters.known.contains(name) {
                        throw error(value, "unknown platform '\(name)' in \(what); known platform names: \(PlatformFilters.known.joined(separator: ", "))")
                    }
                    platformFilters = names
                default:
                    break
                }
            }
            guard let match else { throw error(node, "\(what) has no 'match' glob") }
            return Rule(position: position, line: node.mark?.line ?? 0, match: match, targets: targets, platformFilters: platformFilters)
        }

        func lint(_ node: Node) throws -> Lint {
            var lint = Lint()
            for (key, value) in try mapping(node, keys: Lint.keys, what: "'lint'") {
                switch key {
                case "baseline":
                    lint.baseline = try string(value, key: key)
                case "exempt":
                    guard let mapping = value.mapping else { throw error(value, "expected a mapping of rule ID to globs for 'exempt'") }
                    for (keyNode, globs) in mapping {
                        guard let name = keyNode.scalar?.string, let rule = RuleID(rawValue: name) else {
                            throw error(keyNode, "unknown rule ID '\(keyNode.scalar?.string ?? "")' in 'exempt'; the rules are \(RuleID.allCases.map(\.rawValue).joined(separator: ", "))")
                        }
                        guard Config.exemptibleRules.contains(rule) else {
                            throw error(keyNode, "\(rule.rawValue) is not exemptible; only findings that carry a path can be exempted: \(Config.exemptibleRules.map(\.rawValue).joined(separator: ", "))")
                        }
                        var patterns: [PathGlob] = []
                        for entry in try list(globs, key: name) {
                            patterns.append(try glob(try string(entry, key: name), at: entry))
                        }
                        lint.exempt[rule] = patterns
                    }
                default:
                    break
                }
            }
            return lint
        }
    }

    private static func line(of error: YamlError) -> Int? {
        switch error {
        case .scanner(_, _, let mark, _), .parser(_, _, let mark, _), .composer(_, _, let mark, _):
            return mark.line
        default:
            return nil
        }
    }

    private static func problem(of error: YamlError) -> String {
        switch error {
        case .scanner(_, let problem, _, _), .parser(_, let problem, _, _), .composer(_, let problem, _, _):
            return problem
        default:
            return "\(error)"
        }
    }
}
