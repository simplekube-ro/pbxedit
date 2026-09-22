import PBXSyntax
import PBXModel

/// One primitive edit of a plan (design D1): each case maps onto one
/// mutation of `PBXModel`. Steps carry values, never closures, so a plan can
/// be printed, compared and applied to a copy.
public enum Step: Equatable, Sendable {
    /// A `PBXFileReference`. `name` is written only when given; `sourceTree`
    /// is `<group>` or `SOURCE_ROOT` (design D5).
    case createFileReference(id: ObjectID, path: String, name: String?, sourceTree: String, lastKnownFileType: String?)
    /// A `PBXGroup` with no children yet; `addChild` steps fill it.
    case createGroup(id: ObjectID, name: String?, path: String?, sourceTree: String)
    /// A `PBXBuildFile`; empty `platformFilters` writes no attribute.
    case createBuildFile(id: ObjectID, fileRef: ObjectID, platformFilters: [String])
    case addChild(ObjectID, to: ObjectID, position: InsertPosition)
    case addPhaseEntry(ObjectID, to: ObjectID, position: InsertPosition)
    case removeChild(ObjectID, from: ObjectID)
    case removePhaseEntry(ObjectID, from: ObjectID)
    case deleteObject(ObjectID)
    case setAttribute(key: String, of: ObjectID, to: NewValue?)
    case refreshAnnotations(ObjectID)
}

/// What a plan does to one object, for people and for `--json`: the object,
/// created or reused, with its ID and a detail line.
public struct Change: Equatable, Sendable {
    public enum Action: String, Sendable {
        case createdFileReference, reusedFileReference
        case createdGroup, reusedGroup
        case createdBuildFile, reusedBuildFile
        case addedChild, addedPhaseEntry
        case removedChild, removedPhaseEntry, deletedObject, setAttribute
        case synchronized
    }

    /// The path argument this change serves.
    public let path: String
    public let action: Action
    public let object: ObjectID
    public let detail: String

    public init(path: String, action: Action, object: ObjectID, detail: String) {
        self.path = path
        self.action = action
        self.object = object
        self.detail = detail
    }
}

/// A plan: primitive edits plus their description (design D1). `touched`
/// names every object the steps create or modify and every object the plan
/// reuses, which is the scope of the pre-write check.
public struct Plan: Equatable, Sendable {
    public var steps: [Step]
    public var changes: [Change]
    public var decisions: [Decision]
    public var notes: [String]
    public var touched: Set<ObjectID>

    public init(steps: [Step] = [], changes: [Change] = [], decisions: [Decision] = [], notes: [String] = [],
                touched: Set<ObjectID> = []) {
        self.steps = steps
        self.changes = changes
        self.decisions = decisions
        self.notes = notes
        self.touched = touched
    }

    /// Nothing to write.
    public var isNoOp: Bool { steps.isEmpty }
}

/// A step that could not be applied: which one, and why the model refused.
public struct PlanExecutionError: Error, CustomStringConvertible {
    public let stepIndex: Int
    public let step: Step
    public let underlying: any Error

    public var description: String { "step \(stepIndex + 1) (\(step)) failed: \(underlying)" }
}

extension Plan {
    /// Applies every step, in order, to a copy of `project` and returns it.
    /// The first failing step discards the copy; `project` itself is a value
    /// the caller still holds unchanged.
    public func apply(to project: Project) throws -> Project {
        var result = project
        for (index, step) in steps.enumerated() {
            do {
                try Plan.apply(step, to: &result)
            } catch {
                throw PlanExecutionError(stepIndex: index, step: step, underlying: error)
            }
        }
        return result
    }

    private static func apply(_ step: Step, to project: inout Project) throws {
        switch step {
        case .createFileReference(let id, let path, let name, let sourceTree, let lastKnownFileType):
            var attributes = [NewEntry("path", .string(path)), NewEntry("sourceTree", .string(sourceTree))]
            if let name { attributes.append(NewEntry("name", .string(name))) }
            if let lastKnownFileType { attributes.append(NewEntry("lastKnownFileType", .string(lastKnownFileType))) }
            try project.createObject(id, isa: Kind.fileReference, attributes: attributes)
        case .createGroup(let id, let name, let path, let sourceTree):
            var attributes = [NewEntry("children", .array([])), NewEntry("sourceTree", .string(sourceTree))]
            if let name { attributes.append(NewEntry("name", .string(name))) }
            if let path { attributes.append(NewEntry("path", .string(path))) }
            try project.createObject(id, isa: Kind.group, attributes: attributes)
        case .createBuildFile(let id, let fileRef, let platformFilters):
            var attributes = [NewEntry("fileRef", project.reference(to: fileRef))]
            if !platformFilters.isEmpty {
                attributes.append(NewEntry("platformFilters", .array(platformFilters.map { .string($0) })))
            }
            try project.createObject(id, isa: Kind.buildFile, attributes: attributes)
        case .addChild(let child, let group, let position):
            try project.addChild(child, to: group, position: position)
        case .addPhaseEntry(let buildFile, let phase, let position):
            try project.addPhaseEntry(buildFile, to: phase, position: position)
        case .removeChild(let child, let group):
            try project.removeChild(child, from: group)
        case .removePhaseEntry(let buildFile, let phase):
            try project.removePhaseEntry(buildFile, from: phase)
        case .deleteObject(let id):
            try project.deleteObject(id)
        case .setAttribute(let key, let id, let value):
            try project.setAttribute(key, of: id, to: value)
        case .refreshAnnotations(let id):
            try project.refreshAnnotations(for: id)
        }
    }
}
