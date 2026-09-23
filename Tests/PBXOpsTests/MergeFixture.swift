import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command design D13: the three versions of a merge, built in memory
/// from the Xcode-saved base with pbxedit's own planners, and with a text
/// helper for settings. Each helper takes and returns a project; `seed`
/// varies the minted IDs, so two sides that make the same change carry
/// different IDs, as two branches would.
enum MergeFixture {
    static let basePath = "xcode27/platform-filters-after-xcode27-save.pbxproj"

    static func base() throws -> Project { try loadProject(basePath) }

    static func baseBytes() throws -> [UInt8] { try Fixtures.load(basePath) }

    static func add(_ paths: [String], to project: Project, targets: [String]? = nil, platforms: [String]? = nil,
                    phase: PhaseChoice? = nil, exemptions: Exemptions? = nil, seed: UInt64 = 1) throws -> Project {
        let flags = Conventions.Flags(targets: targets, platformFilters: platforms, phase: phase)
        let plan = try AddPlanner.plan(paths, in: project, conventions: Conventions(flags: flags), exemptions: exemptions,
                                       minter: IDMinter(generator: SplitMix(seed: seed)))
        return try plan.apply(to: project)
    }

    static func remove(_ paths: [String], from project: Project, target: String? = nil, all: Bool = false) throws -> Project {
        try RemovePlanner.plan(paths, in: project, target: target, all: all).apply(to: project)
    }

    static func move(_ from: String, to: String, in project: Project, keepMembership: Bool = true, seed: UInt64 = 1) throws -> Project {
        let plan = try MovePlanner.plan(from: from, to: to, in: project, conventions: Conventions(), keepMembership: keepMembership,
                                        disk: MovedDisk(from: from, to: to), minter: IDMinter(generator: SplitMix(seed: seed)))
        return try plan.apply(to: project)
    }

    /// Sets `key` of `configuration`'s `buildSettings`, inserting it last when absent.
    static func setting(_ key: String, _ value: String, in configuration: ObjectID, of project: Project) throws -> Project {
        var tree = project.tree
        let settings: SyntaxPath = [.key(Project.objectsKey), .key(configuration.rawValue), .key("buildSettings")]
        if tree.node(at: settings + [.key(key)]) != nil {
            try tree.replaceValue(at: settings + [.key(key)], with: .string(value))
        } else {
            try tree.insert(NewEntry(key, .string(value)), intoDictionaryAt: settings, position: .last)
        }
        return try Project(tree: tree)
    }

    /// `knownRegions` of the project object, one element per line as Xcode
    /// writes it, by a text edit: two changes at the two ends of the array
    /// then fall in two hunks, as they do in a real file.
    static func knownRegions(_ regions: [String], of project: Project) throws -> Project {
        let text = String(decoding: project.serialize(), as: UTF8.self)
        let old = "\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
        let range = try XCTUnwrap(text.range(of: old), "the base spells knownRegions as (en, Base)")
        let new = "\t\t\tknownRegions = (\n" + regions.map { "\t\t\t\t\($0),\n" }.joined() + "\t\t\t);\n"
        return try Project.load(Array(text.replacingCharacters(in: range, with: new).utf8))
    }

    /// `project` with the text `old`, which must occur, replaced by `new`.
    static func edit(_ project: Project, replacing old: String, with new: String) throws -> Project {
        let text = String(decoding: project.serialize(), as: UTF8.self)
        let range = try XCTUnwrap(text.range(of: old), "the project holds \(old)")
        return try Project.load(Array(text.replacingCharacters(in: range, with: new).utf8))
    }

    /// Issue #13: the project object's `packageReferences`, one element per
    /// line after `knownRegions`, and an `XCRemoteSwiftPackageReference`
    /// section before the end of `objects`; each package is an ID and its URL.
    static func packages(_ packages: [(id: String, url: String)], of project: Project) throws -> Project {
        let regions = "\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
        let list = "\t\t\tpackageReferences = (\n" + packages.map { "\t\t\t\t\($0.id) /* XCRemoteSwiftPackageReference */,\n" }.joined()
            + "\t\t\t);\n"
        let objects = packages.sorted { $0.id < $1.id }.map { package in
            "\t\t\(package.id) /* XCRemoteSwiftPackageReference */ = {\n\t\t\tisa = XCRemoteSwiftPackageReference;\n"
                + "\t\t\trepositoryURL = \"\(package.url)\";\n\t\t\trequirement = {\n\t\t\t\tkind = upToNextMajorVersion;\n"
                + "\t\t\t\tminimumVersion = 1.0.0;\n\t\t\t};\n\t\t};\n"
        }.joined()
        let section = "/* Begin XCRemoteSwiftPackageReference section */\n" + objects + "/* End XCRemoteSwiftPackageReference section */\n"
        let listed = try edit(project, replacing: regions, with: regions + list)
        return try edit(listed, replacing: "/* End XCConfigurationList section */\n", with: "/* End XCConfigurationList section */\n\n" + section)
    }

    /// `lint.exempt` from YAML, as `.pbxedit.yml` would give it.
    static func exemptions(_ yaml: String) throws -> Exemptions {
        Exemptions(try Config.parse(yaml, file: ".pbxedit.yml").lint.exempt)
    }

    /// Runs the engine on the base and the two sides, with deterministic IDs.
    static func merge(base: Project? = nil, ours: Project, theirs: Project, decisions: MergeDecisions? = nil,
                      exemptions: Exemptions? = nil) throws -> MergeReport {
        var engine = MergeEngine(exemptions: exemptions, decisions: decisions)
        engine.minter = IDMinter(generator: SplitMix(seed: 1234))
        return engine.run(base: try base?.serialize() ?? baseBytes(), ours: ours.serialize(), theirs: theirs.serialize())
    }

    /// The report's template with every open unit and hunk set by `choose`.
    static func decide(_ report: MergeReport, units: (MergeReport.UnitEntry) -> String? = { _ in nil },
                       hunks: (MergeReport.HunkEntry) -> String? = { _ in nil }) throws -> MergeDecisions {
        var decisions = try XCTUnwrap(report.template)
        for unit in report.units where decisions.units[unit.key] != nil { decisions.units[unit.key] = .some(units(unit)) }
        for hunk in report.hunks where decisions.hunks[hunk.key] != nil { decisions.hunks[hunk.key] = .some(hunks(hunk)) }
        return decisions
    }

    /// Sets a top-level attribute of an object.
    static func attribute(_ key: String, _ value: NewValue?, of id: ObjectID, in project: Project) throws -> Project {
        var result = project
        try result.setAttribute(key, of: id, to: value)
        return result
    }
}

/// A disk on which `from` has moved to `to`, or every file under the
/// directory `from` to the same place under `to`.
struct MovedDisk: DiskReader {
    let from: String
    let to: String

    func exists(_ path: String) -> Bool {
        path == to || path.hasPrefix(to + "/")
    }

    func files(in path: String) -> [String] { [] }
}
