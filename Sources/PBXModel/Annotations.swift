import PBXSyntax

extension Project {
    /// The comment Xcode writes after a reference to `id` and on its
    /// definition line (design D6), or `nil` when Xcode writes none: for the
    /// main group, for a build file in no phase, and for kinds the model does
    /// not write.
    public func annotation(for id: ObjectID) -> String? {
        guard let object = object(id) else { return nil }
        switch object.isa {
        case Kind.fileReference, Kind.group, Kind.variantGroup, Kind.versionGroup, Kind.synchronizedRootGroup:
            return object.string("name") ?? object.string("path")
        case Kind.nativeTarget, Kind.aggregateTarget, Kind.legacyTarget:
            return object.string("name")
        case Kind.project:
            return "Project object"
        case Kind.buildFile:
            guard let phase = phases(of: id).first else { return nil }
            return annotation(for: BuildFile(object: object), in: phase)
        case let isa? where Kind.buildPhases.contains(isa):
            return BuildPhase(object: object).displayName
        default:
            return nil
        }
    }

    /// `<file> in <phase>`, or `nil` when the build file's `fileRef` or
    /// `productRef` gives no name.
    func annotation(for buildFile: BuildFile, in phase: BuildPhase) -> String? {
        name(of: buildFile).map { "\($0) in \(phase.displayName)" }
    }

    /// What a build file is called: its reference's name, or its package
    /// product's `productName`.
    func name(of buildFile: BuildFile) -> String? {
        if let fileRef = buildFile.fileRef { return annotation(for: fileRef) }
        if let productRef = buildFile.productRef, let product = object(productRef) {
            return product.string("productName") ?? annotation(for: productRef)
        }
        return nil
    }

    /// Rewrites the annotation on `id`'s definition line and on every
    /// reference to it — where a comment already exists, since Xcode leaves
    /// some references bare — and then on the objects whose comments embed
    /// `id`'s name: a file reference's build files, a phase's build files.
    public mutating func refreshAnnotations(for id: ObjectID) throws {
        guard let object = object(id) else { throw MutationError.noSuchObject(id) }
        try refreshOwnAnnotations(for: id)
        switch object.isa {
        case Kind.fileReference?:
            for buildFile in buildFiles(for: id) { try refreshOwnAnnotations(for: buildFile.id) }
        case let isa? where Kind.buildPhases.contains(isa):
            for buildFile in BuildPhase(object: object).files { try refreshOwnAnnotations(for: buildFile) }
        default:
            break
        }
    }

    private mutating func refreshOwnAnnotations(for id: ObjectID) throws {
        guard let comment = annotation(for: id) else { return }
        let ownPath = Project.path(of: id)
        var definition = false
        if let existing = tree.keyAnnotation(at: ownPath), existing != comment { definition = true }
        let references = referencePaths(to: id).filter { path in
            guard let existing = tree.annotation(at: path) else { return false }
            return existing != comment
        }
        guard definition || !references.isEmpty else { return }
        try mutateValues(dropping: []) { tree in
            if definition { try tree.setKeyAnnotation(comment, at: ownPath) }
            for path in references { try tree.setAnnotation(comment, at: path) }
        }
    }

    /// The paths of every string value among the objects' attributes that is
    /// exactly `id`, at any depth.
    func referencePaths(to id: ObjectID) -> [SyntaxPath] {
        var paths: [SyntaxPath] = []
        for entry in objectEntries {
            Project.collectReferences(in: entry.value, at: Project.objectsPath + [.key(entry.key.value)], to: id.rawValue, into: &paths)
        }
        return paths
    }

    private static func collectReferences(in node: Node, at path: SyntaxPath, to id: String, into paths: inout [SyntaxPath]) {
        switch node {
        case .string(let string):
            if string.matches(id) { paths.append(path) }
        case .dictionary(let dictionary):
            for entry in dictionary.entries {
                collectReferences(in: entry.value, at: path + [.key(entry.key.value)], to: id, into: &paths)
            }
        case .array(let array):
            for (index, element) in array.elements.enumerated() {
                collectReferences(in: element.value, at: path + [.index(index)], to: id, into: &paths)
            }
        case .data:
            break
        }
    }
}
