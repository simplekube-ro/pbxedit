import ArgumentParser
import Foundation

/// The root command. Subcommands do no logic: they call `PBXOps` and render
/// the result (design D7).
@main
struct PbxEdit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pbxedit",
        abstract: "Manage file membership in an Xcode project.pbxproj.",
        discussion: """
            Exit codes: 0 success or no-op, 1 rule violation or refused operation, \
            2 usage or parse error, 3 decisions needed (merge only).
            """,
        version: Version.current,
        subcommands: [Add.self, Move.self, Remove.self, Merge.self, Lint.self, Query.self]
    )

    /// Parses and runs, mapping every way out to the documented exit codes
    /// (design D7): `--help` exits 0; an argument-parsing error and a
    /// `UsageError` exit 2; a command reports its own outcome as an `ExitCode`.
    static func main() {
        do {
            var command = try parseAsRoot()
            try command.run()
        } catch let error as ExitCode {
            Foundation.exit(error.rawValue)
        } catch let error as UsageError {
            error.report(json: false)
            Foundation.exit(CommandOutcome.usage.code)
        } catch {
            // `--help` and `--version` are successful exits that print help.
            if exitCode(for: error).isSuccess {
                exit(withError: error)
            }
            FileHandle.standardError.write(Data((fullMessage(for: error) + "\n").utf8))
            Foundation.exit(CommandOutcome.usage.code)
        }
    }
}

/// How a command ended, mapped to an exit code in one place.
enum CommandOutcome {
    case ok
    case violations
    case usage
    /// `merge`: a unit or hunk needs a decision that was not supplied.
    case decisionsNeeded

    var code: Int32 {
        switch self {
        case .ok: return 0
        case .violations: return 1
        case .usage: return 2
        case .decisionsNeeded: return 3
        }
    }

    var exitCode: ExitCode { ExitCode(code) }
}

/// A usage error: bad arguments, a project that cannot be located, a file
/// that cannot be read. Printed to standard error, as JSON under `--json`.
struct UsageError: Error {
    let message: String

    init(_ message: String) { self.message = message }

    func report(json: Bool) {
        let text: String
        if json, let data = try? JSONEncoder.pbxedit.encode(["error": message]) {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = "error: " + message
        }
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

extension JSONEncoder {
    /// Sorted keys and pretty printing, so the output is stable and diffable.
    static var pbxedit: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
