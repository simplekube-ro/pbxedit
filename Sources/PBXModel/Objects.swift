import PBXSyntax

/// Any entry of `objects`: its ID, its `isa` and its attributes, read from the
/// tree node itself (design D1). Kinds the model does not know are still
/// enumerable this way and pass through untouched.
public struct Object: Equatable {
    public let id: ObjectID
    /// The object's value. Always a dictionary in a well-formed file; kept as
    /// a node so that a malformed entry still loads and round-trips.
    public let value: Node

    public var attributes: DictionaryNode? { value.dictionary }

    /// The `isa`, or `nil` when the object has none.
    public var isa: String? { string("isa") }

    /// The decoded string value of `key`, or `nil` when absent or not a string.
    public func string(_ key: String) -> String? { attributes?[key]?.stringValue }

    /// The string elements of the array at `key`; non-string elements are
    /// skipped. `nil` when absent or not an array.
    public func strings(_ key: String) -> [String]? {
        attributes?[key]?.array?.elements.compactMap { $0.value.stringValue }
    }

    public func id(_ key: String) -> ObjectID? { string(key).map { ObjectID($0) } }

    public func ids(_ key: String) -> [ObjectID]? { strings(key)?.map { ObjectID($0) } }
}

/// The kinds the model knows, and which of them stand in each structural role.
public enum Kind {
    public static let fileReference = "PBXFileReference"
    public static let buildFile = "PBXBuildFile"
    public static let group = "PBXGroup"
    public static let variantGroup = "PBXVariantGroup"
    public static let versionGroup = "XCVersionGroup"
    public static let synchronizedRootGroup = "PBXFileSystemSynchronizedRootGroup"
    public static let nativeTarget = "PBXNativeTarget"
    public static let aggregateTarget = "PBXAggregateTarget"
    public static let legacyTarget = "PBXLegacyTarget"
    public static let project = "PBXProject"

    /// Kinds with `children` that take part in path resolution.
    public static let groups: Set<String> = [group, variantGroup, versionGroup]
    /// Kinds with `buildPhases`.
    public static let targets: Set<String> = [nativeTarget, aggregateTarget, legacyTarget]
    /// Build phase kinds and the name Xcode writes when the phase has none.
    public static let buildPhaseDefaultNames: [String: String] = [
        "PBXSourcesBuildPhase": "Sources",
        "PBXFrameworksBuildPhase": "Frameworks",
        "PBXResourcesBuildPhase": "Resources",
        "PBXHeadersBuildPhase": "Headers",
        "PBXCopyFilesBuildPhase": "CopyFiles",
        "PBXShellScriptBuildPhase": "ShellScript",
        "PBXRezBuildPhase": "Rez",
    ]
    public static var buildPhases: Set<String> { Set(buildPhaseDefaultNames.keys) }

    /// Kinds Xcode writes on a single line.
    public static let singleLine: Set<String> = [buildFile, fileReference, synchronizedRootGroup]

    /// `sourceTree` values that resolve against the project directory.
    public static let groupSourceTree = "<group>"
    public static let sourceRootSourceTree = "SOURCE_ROOT"
    public static let absoluteSourceTree = "<absolute>"
}

/// A `PBXFileReference`.
public struct FileReference: Equatable {
    public let object: Object
    public var id: ObjectID { object.id }
    public var name: String? { object.string("name") }
    public var path: String? { object.string("path") }
    /// Missing means `<group>`, which is what Xcode assumes.
    public var sourceTree: String { object.string("sourceTree") ?? Kind.groupSourceTree }
    public var lastKnownFileType: String? { object.string("lastKnownFileType") }
    public var explicitFileType: String? { object.string("explicitFileType") }
}

/// A `PBXBuildFile`.
public struct BuildFile: Equatable {
    public let object: Object
    public var id: ObjectID { object.id }
    public var fileRef: ObjectID? { object.id("fileRef") }
    /// A Swift package product, for build files that have no `fileRef`.
    public var productRef: ObjectID? { object.id("productRef") }
    public var platformFilters: [String]? { object.strings("platformFilters") }
    /// The single-value form older Xcode versions wrote.
    public var platformFilter: String? { object.string("platformFilter") }
}

/// A `PBXGroup`, `PBXVariantGroup` or `XCVersionGroup`: anything with `children`.
public struct Group: Equatable {
    public let object: Object
    public var id: ObjectID { object.id }
    public var isa: String { object.isa ?? "" }
    public var children: [ObjectID] { object.ids("children") ?? [] }
    public var name: String? { object.string("name") }
    public var path: String? { object.string("path") }
    public var sourceTree: String { object.string("sourceTree") ?? Kind.groupSourceTree }
}

/// A `PBXFileSystemSynchronizedRootGroup`: a folder whose contents Xcode
/// enumerates from disk.
public struct SynchronizedRootGroup: Equatable {
    public let object: Object
    public var id: ObjectID { object.id }
    public var name: String? { object.string("name") }
    public var path: String? { object.string("path") }
    public var sourceTree: String { object.string("sourceTree") ?? Kind.groupSourceTree }
    public var exceptions: [ObjectID] { object.ids("exceptions") ?? [] }
}

/// One of the seven `*BuildPhase` kinds.
public struct BuildPhase: Equatable {
    public let object: Object
    public var id: ObjectID { object.id }
    public var isa: String { object.isa ?? "" }
    public var name: String? { object.string("name") }
    public var files: [ObjectID] { object.ids("files") ?? [] }
    /// The name Xcode shows and writes in comments: `name`, or the kind's default.
    public var displayName: String { name ?? Kind.buildPhaseDefaultNames[isa] ?? isa }
}

/// A `PBXNativeTarget`, `PBXAggregateTarget` or `PBXLegacyTarget`.
public struct Target: Equatable {
    public let object: Object
    public var id: ObjectID { object.id }
    public var isa: String { object.isa ?? "" }
    public var name: String? { object.string("name") }
    public var buildPhases: [ObjectID] { object.ids("buildPhases") ?? [] }
    public var productReference: ObjectID? { object.id("productReference") }
    public var fileSystemSynchronizedGroups: [ObjectID] { object.ids("fileSystemSynchronizedGroups") ?? [] }
}
