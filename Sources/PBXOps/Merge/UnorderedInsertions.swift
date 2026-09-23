import PBXModel

/// Leaves both sides of a hunk change that `both` may still take (issue #13,
/// change `merge-both-unordered-insertions` design D2): insertions of
/// different elements into one array whose order means nothing.
enum UnorderedInsertions {
    /// Attributes whose order carries no meaning. A `PBXFrameworksBuildPhase`'s
    /// `files` is the link order and is excluded apart.
    static let keys: Set<String> = [
        "buildConfigurations", "children", "dependencies", "exceptions", "fileSystemSynchronizedGroups", "files", "knownRegions",
        "membershipExceptions", "packageProductDependencies", "packageReferences", "targets",
    ]

    /// The fields that say two objects of one `isa` are the same thing under two IDs.
    static let identifyingFields: [String: [String]] = {
        var fields: [String: [String]] = [
            "XCRemoteSwiftPackageReference": ["repositoryURL"],
            "XCLocalSwiftPackageReference": ["relativePath"],
            "XCSwiftPackageProductDependency": ["package", "productName"],
            "PBXBuildFile": ["fileRef", "productRef"],
            "PBXTargetDependency": ["target", "targetProxy", "productRef"],
            "PBXContainerItemProxy": ["containerPortal", "proxyType", "remoteGlobalIDString", "remoteInfo"],
            "XCBuildConfiguration": ["name"],
            "PBXFileSystemSynchronizedBuildFileExceptionSet": ["target"],
            "PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet": ["buildPhase"],
        ]
        for isa in ["PBXFileReference", "PBXGroup", "PBXVariantGroup", "XCVersionGroup", "PBXReferenceProxy", "PBXFileSystemSynchronizedRootGroup"] {
            fields[isa] = ["sourceTree", "path", "name"]
        }
        for isa in ["PBXNativeTarget", "PBXAggregateTarget", "PBXLegacyTarget"] { fields[isa] = ["name"] }
        return fields
    }()

    /// Design D2: every leaf of `shared` is an insertion by both sides into
    /// an unordered array, and no element ours inserts is one theirs inserts.
    /// The roots are the hunk's three counterfactual texts; `theirsVersion`,
    /// the text with every hunk `theirs`, holds the objects theirs added in
    /// other hunks, which the counterfactual resolves `ours`.
    static func admits(_ shared: Set<LeafPath>, base: PlistValue, ours: PlistValue, theirs: PlistValue, theirsVersion: () -> PlistValue?) -> Bool {
        let (baseObjects, oursObjects, theirsObjects) = (base[Project.objectsKey], ours[Project.objectsKey], theirs[Project.objectsKey])
        return shared.allSatisfy { path in
            guard path.components.count == 3, let id = path.objectID, keys.contains(path.components[2]) else { return false }
            let key = path.components[2]
            if key == "files", case .string(let isa)? = baseObjects?[id.rawValue]?["isa"], isa == "PBXFrameworksBuildPhase" { return false }
            guard case .array(let was)? = baseObjects?[id.rawValue]?[key], case .array(let mine)? = oursObjects?[id.rawValue]?[key],
                  case .array(let yours)? = theirsObjects?[id.rawValue]?[key],
                  MergeChecks.isSubsequence(was, of: mine), MergeChecks.isSubsequence(was, of: yours)
            else { return false }
            let oursAdded = (Multiset(mine) - Multiset(was)).sorted().map { identity(of: $0, in: oursObjects) }
            let theirsAdded = Set((Multiset(yours) - Multiset(was)).sorted().map { element in
                identity(of: element, in: theirsObjects?[element.stringValue ?? ""] == nil ? theirsVersion()?[Project.objectsKey] : theirsObjects)
            })
            return !oursAdded.contains(where: theirsAdded.contains)
        }
    }

    /// A string naming no object is itself; one naming an object is its
    /// `isa` and identifying fields, a field naming an object replaced by
    /// that object's identity; an unknown `isa` is the whole object.
    static func identity(of element: PlistValue, in objects: PlistValue?, depth: Int = 4) -> PlistValue {
        guard depth > 0, case .string(let id) = element, let object = objects?[id], case .string(let isa)? = object["isa"] else {
            return element
        }
        guard let fields = identifyingFields[isa] else { return object }
        var entries = [PlistValue.Entry(key: "isa", value: .string(isa))]
        for field in fields {
            guard let value = object[field] else { continue }
            entries.append(PlistValue.Entry(key: field, value: identity(of: value, in: objects, depth: depth - 1)))
        }
        return .dictionary(entries)
    }
}

private extension PlistValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
