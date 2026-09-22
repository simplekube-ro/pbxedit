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
    /// Warnings among the touched objects; they do not abort.
    public let warnings: [Finding]
    /// The post-operation model: what was written (reloaded from disk), or
    /// what would have been (dry run, no-op). `nil` when the operation failed.
    public let project: Project?
    /// The unified diff of a dry run; `""` for a no-op; `nil` otherwise.
    public let diff: String?
    /// Why the operation `failed`.
    public let error: String?
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

    public func run(_ plan: Plan, dryRun: Bool) -> OperationResult {
        let result: Project
        do {
            result = try plan.apply(to: project)
        } catch {
            return OperationResult(plan: plan, outcome: .failed, modified: false, findings: [], warnings: [], project: nil, diff: nil,
                                   error: "the plan could not be applied: \(error)")
        }
        let scoped = ruleSet.evaluate(result, scope: plan.touched)
        let errors = scoped.filter { $0.severity == .error }
        let warnings = scoped.filter { $0.severity == .warning }
        guard errors.isEmpty else {
            return OperationResult(plan: plan, outcome: .violations(stage: .beforeWrite), modified: false, findings: errors,
                                   warnings: warnings, project: nil, diff: nil, error: nil)
        }
        let newBytes = result.serialize()
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
        var verification = (postWriteRuleSet ?? ruleSet).evaluate(bytes: onDisk, scope: plan.touched).filter { $0.severity == .error }
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
