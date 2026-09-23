import PBXSyntax
import PBXModel

/// What one version of a project holds as membership (merge design D2):
/// every *managed* file reference by resolved path, with its spelling, its
/// parents, its other attributes and its rows. Everything else in the file
/// is text to the merge.
public struct MembershipSnapshot {
    /// One build file listed in one target's phase.
    public struct Row: Equatable, Sendable {
        public let target: String
        public let phase: PhaseChoice
        public let filters: [String]
        public let settings: PlistValue?
        public let buildFile: ObjectID
        public let phaseID: ObjectID
        /// The build file's attributes other than `isa`, `fileRef`, the
        /// filter keys and `settings`.
        public let attributes: [String: PlistValue]

        public var masked: MaskedRow { MaskedRow(target: target, phase: phase, filters: filters, settings: settings) }
    }

    /// A row without IDs: what "the same membership" compares.
    public struct MaskedRow: Hashable, Sendable, Comparable, CustomStringConvertible {
        public let target: String
        public let phase: PhaseChoice
        public let filters: [String]
        public let settings: PlistValue?

        public init(target: String, phase: PhaseChoice, filters: [String], settings: PlistValue?) {
            self.target = target
            self.phase = phase
            self.filters = filters
            self.settings = settings
        }

        public static func < (lhs: MaskedRow, rhs: MaskedRow) -> Bool {
            let l = (lhs.target, lhs.phase.rawValue, lhs.filters.joined(separator: ","), lhs.settings?.description ?? "")
            let r = (rhs.target, rhs.phase.rawValue, rhs.filters.joined(separator: ","), rhs.settings?.description ?? "")
            return l < r
        }

        /// `App (sources) [ios]` and `settings = {…}` when there are any.
        public var description: String {
            var text = "\(target) (\(phase.rawValue))"
            if !filters.isEmpty { text += " [\(filters.joined(separator: ", "))]" }
            if let settings { text += " settings = \(settings)" }
            return text
        }
    }

    /// A managed reference and its rows.
    public struct Reference: Equatable, Sendable {
        public let id: ObjectID
        public let resolvedPath: String
        public let path: String?
        public let name: String?
        public let sourceTree: String
        public let parents: [ObjectID]
        /// The resolved path of each parent group, in order; the first is
        /// the one the reference resolves through.
        public let groupPaths: [String]
        /// Every attribute other than `isa`, `path`, `name` and `sourceTree`.
        public let attributes: [String: PlistValue]
        public let buildFiles: [ObjectID]
        /// In object order of the build files, then phase listing order.
        public let rows: [Row]

        public var groupPath: String? { groupPaths.first }

        public var masked: MaskedState {
            MaskedState(path: path, name: name, sourceTree: sourceTree, groupPaths: groupPaths, rows: rows.map(\.masked).sorted())
        }
    }

    /// A path's membership without IDs (spec: Membership changes are
    /// grouped into units): spelling, parent directories and rows.
    public struct MaskedState: Hashable, Sendable {
        public let path: String?
        public let name: String?
        public let sourceTree: String
        public let groupPaths: [String]
        public let rows: [MaskedRow]
    }

    /// Managed references by resolved path; the first in object order when
    /// several resolve there.
    public let references: [String: Reference]
    /// Paths at which more than one managed reference resolves (M4 damage).
    public let collisions: Set<String>
    /// Managed references by ID.
    public let byID: [ObjectID: Reference]
    /// Path → every managed reference resolving there, in object order.
    public let idsByPath: [String: [ObjectID]]

    public init(_ project: Project) {
        var references: [String: Reference] = [:]
        var collisions: Set<String> = []
        var byID: [ObjectID: Reference] = [:]
        var idsByPath: [String: [ObjectID]] = [:]
        let products = Set(project.targets.compactMap(\.productReference))
        var seen: Set<ObjectID> = []
        for reference in project.fileReferences where seen.insert(reference.id).inserted {
            guard !products.contains(reference.id),
                  let managed = MembershipSnapshot.managed(reference, in: project)
            else { continue }
            if references[managed.resolvedPath] != nil {
                collisions.insert(managed.resolvedPath)
            } else {
                references[managed.resolvedPath] = managed
            }
            byID[managed.id] = managed
            idsByPath[managed.resolvedPath, default: []].append(managed.id)
        }
        self.references = references
        self.collisions = collisions
        self.byID = byID
        self.idsByPath = idsByPath
    }

    /// Every managed path, sorted.
    public var paths: [String] { references.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) } }

    /// The path's membership without IDs; `nil` when no managed reference resolves there.
    public func masked(at path: String) -> MaskedState? { references[path]?.masked }

    static let phases: [String: PhaseChoice] = Dictionary(
        uniqueKeysWithValues: PhaseChoice.allCases.compactMap { choice in choice.isa.map { ($0, choice) } })

    static let spellingKeys: Set<String> = ["isa", "path", "name", "sourceTree"]
    static let rowKeys: Set<String> = ["isa", "fileRef", PlatformFilters.singularKey, PlatformFilters.pluralKey, "settings"]

    /// Design D2's definition, or `nil` for a reference that is not managed.
    static func managed(_ reference: FileReference, in project: Project) -> Reference? {
        let sourceTree = reference.sourceTree
        guard sourceTree == Kind.groupSourceTree || sourceTree == Kind.sourceRootSourceTree,
              case .relative(let resolved)? = project.resolvedPath(of: reference.id),
              project.synchronizedRootGroup(covering: resolved) == nil
        else { return nil }
        let parents = project.parents(of: reference.id)
        guard parents.allSatisfy({ $0.isa == Kind.group }) else { return nil }
        let membership = project.membership(of: reference.id)
        var rows: [Row] = []
        for entry in membership.buildFiles {
            guard !entry.phases.isEmpty else { return nil }
            let settings = entry.buildFile.object.attributes?["settings"].map(PlistValue.init)
            let attributes = MembershipSnapshot.attributes(of: entry.buildFile.object, except: rowKeys)
            let filters = PlatformFilters.read(from: entry.buildFile)
            for listing in entry.phases {
                guard let phase = phases[listing.phase.isa], !listing.targets.isEmpty else { return nil }
                for target in listing.targets {
                    rows.append(Row(target: target.name ?? target.id.rawValue, phase: phase, filters: filters, settings: settings,
                                    buildFile: entry.buildFile.id, phaseID: listing.phase.id, attributes: attributes))
                }
            }
        }
        let groupPaths = parents.map { project.resolvedPath(of: $0.id)?.description ?? "" }
        return Reference(
            id: reference.id, resolvedPath: resolved, path: reference.path, name: reference.name, sourceTree: sourceTree,
            parents: parents.map(\.id), groupPaths: groupPaths,
            attributes: attributes(of: reference.object, except: spellingKeys),
            buildFiles: membership.buildFiles.map(\.buildFile.id), rows: rows)
    }

    static func attributes(of object: Object, except excluded: Set<String>) -> [String: PlistValue] {
        var result: [String: PlistValue] = [:]
        for entry in object.attributes?.entries ?? [] {
            let key = entry.key.value
            guard !excluded.contains(key), result[key] == nil else { continue }
            result[key] = PlistValue(entry.value)
        }
        return result
    }
}
