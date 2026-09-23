import Foundation

/// The version `--version` prints (release-distribution design D1).
///
/// `base` is the next version to be tagged, with a `-dev` suffix; the release
/// workflow rewrites this one line from the tag before building and refuses a
/// tag that disagrees with it. A development build — one whose `base` ends in
/// `-dev` — appends `+<hash>` when `PBXEDIT_BUILD_HASH` names the commit; a
/// release build ignores the environment, so its version is this literal.
enum Version {
    static let base = "1.2.0-dev"

    static let developmentSuffix = "-dev"
    static let buildHashVariable = "PBXEDIT_BUILD_HASH"
    static let shortHashLength = 7

    /// The version of this process, read once.
    static let current = string(environment: ProcessInfo.processInfo.environment)

    /// `base`, plus `+<hash>` for a development build whose environment holds
    /// a usable hash: lowercase hex, at least `shortHashLength` characters,
    /// of which the first `shortHashLength` are printed.
    static func string(environment: [String: String]) -> String {
        guard base.hasSuffix(developmentSuffix), let hash = shortHash(environment[buildHashVariable]) else {
            return base
        }
        return base + "+" + hash
    }

    static func shortHash(_ value: String?) -> String? {
        guard let value, value.count >= shortHashLength,
              value.allSatisfy({ ($0.isHexDigit && ($0.isNumber || $0.isLowercase)) })
        else { return nil }
        return String(value.prefix(shortHashLength))
    }
}
