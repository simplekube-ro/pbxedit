import PBXSyntax

/// Why a primitive mutation was refused. The model never refuses a mutation
/// because the result would be *wrong* — that judgement belongs to the rule
/// set — only because it cannot be expressed.
public enum MutationError: Error, Equatable {
    case noSuchObject(ObjectID)
    case objectExists(ObjectID)
    case notAGroup(ObjectID)
    case notABuildPhase(ObjectID)
    case notAChild(ObjectID, of: ObjectID)
    case notInPhase(ObjectID, phase: ObjectID)
    /// `isa` is what makes an object what it is; delete and recreate instead.
    case isaIsImmutable(ObjectID)
    /// Section-marker text that does not scan as trivia; cannot happen for
    /// an `isa` that is a plain identifier.
    case malformedTrivia(String)
}

extension Project {
    static let objectsPath: SyntaxPath = [.key(Project.objectsKey)]

    /// A reference to `id` as a value, annotated as Xcode would annotate it.
    public func reference(to id: ObjectID) -> NewValue {
        .string(id.rawValue, comment: annotation(for: id))
    }

    // MARK: Create and delete

    /// Creates an object in the section for its kind, in ID order when the
    /// section is sorted (design D5). `isa` goes first, the other attributes
    /// in key order, as Xcode writes them. The definition line carries the
    /// annotation of design D6 when the kind has one.
    public mutating func createObject(_ id: ObjectID, isa: String, attributes: [NewEntry]) throws {
        guard !contains(id) else { throw MutationError.objectExists(id) }
        var entries = [NewEntry("isa", .string(isa))]
        entries += attributes.filter { $0.key != "isa" }.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
        let entry = NewEntry(id.rawValue, .dictionary(entries))
        let kindLayout: NewValueLayout = Kind.singleLine.contains(isa) ? .singleLine : .multiLine
        let map = sections
        let ownPath = Project.path(of: id)
        try insertObject(id, isa: isa) { tree in
            switch map.placement(for: isa, id: id) {
            case .inSection(let position):
                try tree.insert(entry, intoDictionaryAt: Project.objectsPath, position: position)
            case .newSection(let nextFirst):
                // The new entry takes over the next block's leading trivia,
                // whose End marker is the previous block's and whose Begin
                // marker becomes the new block's; the next block's first entry
                // gets the trivia back with the new block's End marker.
                let nextPath = Project.objectsPath + [.key(nextFirst)]
                let original = tree.leadingTrivia(at: nextPath) ?? .empty
                try tree.insert(entry, intoDictionaryAt: Project.objectsPath, position: .before(nextFirst), layout: kindLayout)
                let newline = original.lineBreak
                try tree.setLeadingTrivia(
                    try SectionMap.replacingMarker(in: original, begin: true, with: isa, newline: newline), at: ownPath)
                try tree.setLeadingTrivia(
                    try SectionMap.replacingMarker(in: original, begin: false, with: isa, newline: newline), at: nextPath)
            case .newSectionLast:
                try tree.insert(entry, intoDictionaryAt: Project.objectsPath, position: .last, layout: kindLayout)
                let own = tree.leadingTrivia(at: ownPath) ?? .empty
                let closing = tree.closingTrivia(at: Project.objectsPath) ?? .empty
                let newline = own.lineBreak
                let previousEnd = SectionMap.markers(in: closing).first { !$0.isBegin }
                let text = (previousEnd.map { newline + SectionMap.markerComment($0.isa, begin: false) + newline } ?? "")
                    + newline + SectionMap.markerComment(isa, begin: true) + own.text
                guard let leading = Trivia(validating: text) else { throw MutationError.malformedTrivia(text) }
                try tree.setLeadingTrivia(leading, at: ownPath)
                try tree.setClosingTrivia(
                    try SectionMap.replacingMarker(in: closing, begin: false, with: isa, newline: newline),
                    at: Project.objectsPath)
            case .append:
                try tree.insert(entry, intoDictionaryAt: Project.objectsPath, position: .last, layout: kindLayout)
            }
        }
        if let comment = annotation(for: id) {
            try mutateValues(dropping: []) { try $0.setKeyAnnotation(comment, at: ownPath) }
        }
    }

    /// Deletes an object. When it was the last of its kind, its section's
    /// markers go with it. References to it elsewhere are left alone: they
    /// are rule S2's business.
    public mutating func deleteObject(_ id: ObjectID) throws {
        guard let object = object(id), let position = entryIndex(of: id) else { throw MutationError.noSuchObject(id) }
        let map = sections
        let emptied = object.isa.flatMap { isa in map.section(for: isa).flatMap { $0.range.count == 1 ? $0 : nil } }
        try removeObject(id, at: position) { tree in
            try tree.removeEntry(forKey: id.rawValue, fromDictionaryAt: Project.objectsPath)
            guard let emptied else { return }
            // The markers now sit in the trivia of what followed the entry.
            let entries = tree.node(at: Project.objectsPath)?.dictionary?.entries ?? []
            let index = emptied.range.lowerBound
            if entries.indices.contains(index) {
                let path = Project.objectsPath + [.key(entries[index].key.value)]
                if let trivia = tree.leadingTrivia(at: path) {
                    try tree.setLeadingTrivia(SectionMap.removingEmptySection(emptied.isa, from: trivia), at: path)
                }
            } else if let closing = tree.closingTrivia(at: Project.objectsPath) {
                try tree.setClosingTrivia(SectionMap.removingEmptySection(emptied.isa, from: closing), at: Project.objectsPath)
            }
        }
    }

    // MARK: Children and phase entries

    /// Adds `child` to the `children` of `group`, annotated as Xcode would.
    public mutating func addChild(_ child: ObjectID, to group: ObjectID, position: InsertPosition = .last) throws {
        guard let object = object(group) else { throw MutationError.noSuchObject(group) }
        guard Kind.groups.contains(object.isa ?? "") else { throw MutationError.notAGroup(group) }
        let element = reference(to: child)
        try insertChild(child, into: group) { try $0.insert(element, intoArrayAt: Project.path(of: group, "children"), position: position) }
    }

    /// Removes the first listing of `child` from the `children` of `group`,
    /// with its annotation. The child object itself stays.
    public mutating func removeChild(_ child: ObjectID, from group: ObjectID) throws {
        guard let object = object(group) else { throw MutationError.noSuchObject(group) }
        guard Kind.groups.contains(object.isa ?? "") else { throw MutationError.notAGroup(group) }
        guard Group(object: object).children.contains(child) else { throw MutationError.notAChild(child, of: group) }
        try mutateValues(dropping: .parents) { try $0.removeElement(equalTo: child.rawValue, fromArrayAt: Project.path(of: group, "children")) }
    }

    /// Lists `buildFile` in the `files` of `phase`, annotated `<file> in
    /// <phase>`, and writes that annotation on the build file's definition
    /// line too, since it has none until it is in a phase (design D6).
    public mutating func addPhaseEntry(_ buildFile: ObjectID, to phase: ObjectID, position: InsertPosition = .last) throws {
        guard let object = object(phase) else { throw MutationError.noSuchObject(phase) }
        guard Kind.buildPhases.contains(object.isa ?? "") else { throw MutationError.notABuildPhase(phase) }
        let comment = self.buildFile(buildFile).flatMap { annotation(for: $0, in: BuildPhase(object: object)) }
        let element = NewValue.string(buildFile.rawValue, comment: comment)
        let definition = Project.path(of: buildFile)
        let annotateDefinition = comment != nil && contains(buildFile) && tree.keyAnnotation(at: definition) != comment
        try mutateValues(dropping: .membership) { tree in
            try tree.insert(element, intoArrayAt: Project.path(of: phase, "files"), position: position)
            if annotateDefinition, let comment { try tree.setKeyAnnotation(comment, at: definition) }
        }
    }

    /// Removes the first listing of `buildFile` from the `files` of `phase`.
    /// The build file object itself stays.
    public mutating func removePhaseEntry(_ buildFile: ObjectID, from phase: ObjectID) throws {
        guard let object = object(phase) else { throw MutationError.noSuchObject(phase) }
        guard Kind.buildPhases.contains(object.isa ?? "") else { throw MutationError.notABuildPhase(phase) }
        guard BuildPhase(object: object).files.contains(buildFile) else { throw MutationError.notInPhase(buildFile, phase: phase) }
        try mutateValues(dropping: .membership) { try $0.removeElement(equalTo: buildFile.rawValue, fromArrayAt: Project.path(of: phase, "files")) }
    }

    // MARK: Attributes

    /// Sets, adds or (with `nil`) removes one attribute of an object. A new
    /// attribute goes in key order, as Xcode keeps them; an existing one is
    /// replaced in place, keeping its layout. Comments that embed the
    /// object's name are refreshed afterwards (design D6).
    public mutating func setAttribute(_ key: String, of id: ObjectID, to value: NewValue?) throws {
        guard !key.utf8.elementsEqual("isa".utf8) else { throw MutationError.isaIsImmutable(id) }
        guard let object = object(id) else { throw MutationError.noSuchObject(id) }
        let ownPath = Project.path(of: id)
        let keys = (object.attributes?.keys ?? []).filter { !$0.utf8.elementsEqual("isa".utf8) }
        let exists = keys.contains { $0.utf8.elementsEqual(key.utf8) }
        let sorted = zip(keys, keys.dropFirst()).allSatisfy { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        try mutateValues(dropping: .all) { tree in
            if let value {
                if exists {
                    try tree.replaceValue(at: ownPath + [.key(key)], with: value)
                } else if sorted, let next = keys.first(where: { key.utf8.lexicographicallyPrecedes($0.utf8) }) {
                    try tree.insert(NewEntry(key, value), intoDictionaryAt: ownPath, position: .before(next))
                } else {
                    try tree.insert(NewEntry(key, value), intoDictionaryAt: ownPath, position: .last)
                }
            } else if exists {
                try tree.removeEntry(forKey: key, fromDictionaryAt: ownPath)
            }
        }
        try refreshAnnotations(for: id)
    }
}
