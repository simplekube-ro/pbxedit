import PBXSyntax
import PBXModel

/// The group standing for a directory (design D5), and whether a
/// `<group>`-relative child resolves through it to that directory.
public struct GroupLocation: Equatable, Sendable {
    public let group: ObjectID
    public let resolvesToDirectory: Bool

    public init(group: ObjectID, resolvesToDirectory: Bool) {
        self.group = group
        self.resolvesToDirectory = resolvesToDirectory
    }
}

/// How a new file reference is written: `<group>` plus basename, or
/// `SOURCE_ROOT` plus the full path with `name` set.
public struct ReferenceSpelling: Equatable, Sendable {
    public let path: String
    public let name: String?
    public let sourceTree: String
}

extension PlanBuilder {
    static func basename(of path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
    }

    /// The group for `directory`, planning the creation of a chain beneath the
    /// deepest existing ancestor when nothing represents it yet. `path` is
    /// the request path the change lines cite.
    public mutating func group(forDirectory directory: String, path: String) throws -> GroupLocation {
        if directory.isEmpty {
            guard let main = project.mainGroup else { throw PlanError.noMainGroup }
            return GroupLocation(group: main.id, resolvesToDirectory: true)
        }
        if let planned = plannedGroups[directory] {
            return GroupLocation(group: planned.id, resolvesToDirectory: planned.resolvesToDirectory)
        }
        let candidates = project.groups(at: directory).filter { $0.isa == Kind.group }
        if let found = candidates.first(where: { !($0.path ?? "").isEmpty }) ?? candidates.first {
            return GroupLocation(group: found.id, resolvesToDirectory: true)
        }
        let parentDirectory = SiblingInference.directory(of: directory)
        let name = PlanBuilder.basename(of: directory)
        let parent = try group(forDirectory: parentDirectory, path: path)
        if let existingParent = project.group(parent.group) {
            for child in existingParent.children {
                guard let group = project.group(child), group.isa == Kind.group, (group.path ?? "").isEmpty,
                      group.name?.utf8.elementsEqual(name.utf8) == true
                else { continue }
                return GroupLocation(group: group.id, resolvesToDirectory: false)
            }
        }
        let id = mint()
        if parent.resolvesToDirectory {
            add(.createGroup(id: id, name: nil, path: name, sourceTree: Kind.groupSourceTree), touching: [id])
        } else {
            add(.createGroup(id: id, name: name, path: directory, sourceTree: Kind.sourceRootSourceTree), touching: [id])
        }
        record(Change(path: path, action: .createdGroup, object: id, detail: "group \(name) for \(directory) under \(describe(parent.group))"))
        addChild(id, named: name, to: parent.group)
        planGroup(PlannedGroup(id: id, resolvesToDirectory: true), for: directory)
        return GroupLocation(group: id, resolvesToDirectory: true)
    }

    /// Design D5, for the file itself.
    public func reference(for path: String, in location: GroupLocation) -> ReferenceSpelling {
        let name = PlanBuilder.basename(of: path)
        if location.resolvesToDirectory {
            return ReferenceSpelling(path: name, name: nil, sourceTree: Kind.groupSourceTree)
        }
        return ReferenceSpelling(path: path, name: name, sourceTree: Kind.sourceRootSourceTree)
    }

    /// Where a child named `name` goes among `group`'s children: in name
    /// order when they already are in name order, last otherwise.
    public mutating func childPosition(in group: ObjectID, name: String) -> InsertPosition {
        let children = children(of: group)
        let names = children.map(\.name)
        let sorted = zip(names, names.dropFirst()).allSatisfy { !PlanBuilder.precedes($1, $0) }
        guard sorted, let next = children.first(where: { PlanBuilder.precedes(name, $0.name) }) else { return .last }
        return .before(next.id.rawValue)
    }

    /// Plans `child` into `group` at its name-ordered position and remembers
    /// it, so later children of the same group are ordered against it too.
    public mutating func addChild(_ child: ObjectID, named name: String, to group: ObjectID) {
        let position = childPosition(in: group, name: name)
        add(.addChild(child, to: group, position: position), touching: [child, group])
        var children = children(of: group)
        if case .before(let sibling) = position, let index = children.firstIndex(where: { $0.id.rawValue == sibling }) {
            children.insert((child, name), at: index)
        } else {
            children.append((child, name))
        }
        knownChildren[group] = children
    }

    /// `<name> (<id>)` for a group in a change line.
    func describe(_ group: ObjectID) -> String {
        if let known = project.group(group) {
            let name = known.name ?? known.path ?? (group == project.mainGroup?.id ? "main group" : "")
            return name.isEmpty ? group.rawValue : "\(name) (\(group))"
        }
        if let planned = plannedGroups.first(where: { $0.value.id == group }) {
            return "\(PlanBuilder.basename(of: planned.key)) (\(group))"
        }
        return group.rawValue
    }

    private mutating func children(of group: ObjectID) -> [(id: ObjectID, name: String)] {
        if let known = knownChildren[group] { return known }
        let children = (project.group(group)?.children ?? []).map { ($0, project.annotation(for: $0) ?? "") }
        knownChildren[group] = children
        return children
    }

    /// Case-insensitive byte order, the order Xcode's navigator shows.
    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased().utf8.lexicographicallyPrecedes(rhs.lowercased().utf8)
    }
}
