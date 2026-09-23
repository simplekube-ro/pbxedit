import Foundation
import PBXSyntax
import PBXModel

/// What running a plan came to (design D2). `modified` is the one fact the
/// command-line output derives its "modified / not modified" line from: it
/// is set in exactly one place, from the bytes read back after the write.
public struct OperationResult {
    public enum Stage: Equatable, Sendable { case beforeWrite, afterWrite }

    public enum Outcome: Equatable, Sendable {
        /// Applied, or nothing to apply.
        case ok
        /// The rule set found an error among the touched objects; nothing
        /// (or, after the write, nothing any more) is on disk.
        case violations(stage: Stage)
        /// A step could not be applied or the file could not be written.
        case failed
    }

    public let plan: Plan
    public let outcome: Outcome
    /// Whether the bytes of the project file were replaced.
    public let modified: Bool
    /// The errors that aborted the operation, in rule-set order.
    public let findings: [Finding]
    /// Warnings among the touched objects; they do not abort. Empty in the
    /// whole-project mode, where a new warning aborts and the rest are the
    /// report's business.
    public let warnings: [Finding]
    /// The post-operation model: what was written (reloaded from disk), or
    /// what would have been (dry run, no-op). `nil` when the operation failed.
    public let project: Project?
    /// The unified diff of a dry run; `""` for a no-op; `nil` otherwise.
    public let diff: String?
    /// Why the operation `failed`.
    public let error: String?
}

/// How the result of a plan is judged, before the write and again on the
/// bytes read back.
public enum Verification: Equatable, Sendable {
    /// Every ordinary operation: an error among `plan.touched` aborts,
    /// warnings there are reported (add-command design D2).
    case scoped
    /// A repair (integrity-repair design D5): the complete finding sets are
    /// compared by identity; a `selected` finding that survives, or any
    /// finding absent from `before`, aborts. `before` is the evaluation of
    /// the project as loaded, with the same rule set and exemptions.
    case wholeProject(before: [Finding], selected: [Finding])
}

/// Owns the pipeline after planning: execute in memory, check, write
/// atomically, read back, check again, restore on failure (design D2, D7).
/// It never sees flags or paths; the CLI plans, the runner runs.
public struct OperationRunner {
    /// Why the project file could not be read or loaded.
    public struct LoadFailure: Error, CustomStringConvertible {
        public let description: String
    }

    public let url: URL
    public let originalBytes: [UInt8]
    /// The project as loaded, for planners and for validating flags.
    public let project: Project
    public var ruleSet: RuleSet = .standard
    /// `lint.exempt` of the configuration, honoured by both checks
    /// (conventions-config design D5); `nil` without a configuration.
    public var exemptions: Exemptions?
    /// The rule set of the post-write check, when a test needs it to differ.
    var postWriteRuleSet: RuleSet?

    /// Reads and loads the project file once.
    public init(projectFile url: URL) throws {
        self.url = url
        do {
            originalBytes = Array(try Data(contentsOf: url))
        } catch {
            throw LoadFailure(description: "cannot read \(url.path): \(error.localizedDescription)")
        }
        do {
            project = try Project.load(originalBytes)
        } catch {
            throw LoadFailure(description: "cannot load \(url.path): \(error)")
        }
    }

    public func run(_ plan: Plan, dryRun: Bool, verification: Verification = .scoped) -> OperationResult {
        let result: Project
        do {
            result = try plan.apply(to: project)
        } catch {
            return OperationResult(plan: plan, outcome: .failed, modified: false, findings: [], warnings: [], project: nil, diff: nil,
                                   error: "the plan could not be applied: \(error)")
        }
        let (errors, warnings) = judge(ruleSet.evaluate(result, scope: scope(of: plan, verification), exemptions: exemptions), verification)
        guard errors.isEmpty else {
            return OperationResult(plan: plan, outcome: .violations(stage: .beforeWrite), modified: false, findings: errors,
                                   warnings: warnings, project: nil, diff: nil, error: nil)
        }
        let newBytes = result.serialize()
        // Remove design D6, belt and braces: once the rule set is clean, no
        // deleted ID can still be named anywhere in the file. A failure here
        // is a gap in S2's key list, not a user error.
        assert(plan.deletedObjectsMentioned(in: newBytes).isEmpty,
               "deleted objects still mentioned after a clean check: \(plan.deletedObjectsMentioned(in: newBytes))")
        if dryRun {
            let diff = UnifiedDiff.make(from: originalBytes, to: newBytes, name: url.lastPathComponent)
            return OperationResult(plan: plan, outcome: .ok, modified: false, findings: [], warnings: warnings, project: result,
                                   diff: diff, error: nil)
        }
        if plan.isNoOp {
            return OperationResult(plan: plan, outcome: .ok, modified: false, findings: [], warnings: warnings, project: result,
                                   diff: nil, error: nil)
        }
        do {
            try OperationRunner.writeAtomically(newBytes, to: url)
        } catch {
            return OperationResult(plan: plan, outcome: .failed, modified: false, findings: [], warnings: warnings, project: nil,
                                   diff: nil, error: "cannot write \(url.path): \(error)")
        }
        // Verify what is on disk, not what was meant to be.
        var onDisk = (try? Data(contentsOf: url)).map(Array.init) ?? []
        let readBack = (postWriteRuleSet ?? ruleSet).evaluate(bytes: onDisk, scope: scope(of: plan, verification), exemptions: exemptions)
        var verification = judge(readBack, verification).errors
        if onDisk != newBytes {
            verification.insert(Finding(rule: .S1, object: nil, message: "the bytes read back differ from the bytes written"), at: 0)
        }
        if !verification.isEmpty {
            var restoreError: String?
            do {
                try OperationRunner.writeAtomically(originalBytes, to: url)
            } catch {
                restoreError = "and the original could not be restored: \(error)"
            }
            onDisk = (try? Data(contentsOf: url)).map(Array.init) ?? []
            return OperationResult(plan: plan, outcome: .violations(stage: .afterWrite), modified: onDisk != originalBytes,
                                   findings: verification, warnings: warnings, project: nil, diff: nil, error: restoreError)
        }
        let reloaded = try? Project.load(onDisk)
        return OperationResult(plan: plan, outcome: .ok, modified: onDisk != originalBytes, findings: [], warnings: warnings,
                               project: reloaded, diff: nil, error: nil)
    }

    /// The evaluation scope for a mode: the touched objects, or everything.
    private func scope(of plan: Plan, _ verification: Verification) -> Set<ObjectID>? {
        switch verification {
        case .scoped: return plan.touched
        case .wholeProject: return nil
        }
    }

    /// What aborts and what is merely reported, per mode.
    private func judge(_ findings: [Finding], _ verification: Verification) -> (errors: [Finding], warnings: [Finding]) {
        switch verification {
        case .scoped:
            return (findings.filter { $0.severity == .error }, findings.filter { $0.severity == .warning })
        case .wholeProject(let before, let selected):
            let known = Set(before.map(\.identity))
            let chosen = Set(selected.map(\.identity))
            let violations = findings.filter { chosen.contains($0.identity) || !known.contains($0.identity) }
            return (RuleSet.ordered(violations), [])
        }
    }

    /// Design D7: temp file beside the target, `fsync`, `rename(2)`. The
    /// temp file is removed on every path; after a successful rename it is
    /// already gone and the removal is a no-op.
    static func writeAtomically(_ bytes: [UInt8], to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".pbxedit-\(getpid())")
        defer { try? FileManager.default.removeItem(at: temp) }
        let manager = FileManager.default
        guard manager.createFile(atPath: temp.path, contents: nil) else {
            throw POSIXError(.EACCES)
        }
        if let permissions = try? manager.attributesOfItem(atPath: url.path)[.posixPermissions] {
            try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path)
        }
        let handle = try FileHandle(forWritingTo: temp)
        try handle.write(contentsOf: Data(bytes))
        try handle.synchronize()
        try handle.close()
        guard rename(temp.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

/// The write every command shares (design D7): a temporary file beside the
/// target, `fsync`, `rename(2)`. `merge` writes through here too (merge
/// design D11).
public enum AtomicFile {
    public static func write(_ bytes: [UInt8], to url: URL) throws {
        try OperationRunner.writeAtomically(bytes, to: url)
    }
}
