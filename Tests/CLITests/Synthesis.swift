import Foundation
import PBXSyntax
import PBXModel

/// The CLI side of the reference-workload substitute (integrity-repair
/// design Evidence; the same synthesis as `PBXOpsTests.OrphanedCorpus`):
/// `Alamofire.pbxproj` plus 655 `SOURCE_ROOT` references in no group, each
/// built, over thirty directories — fifteen that existing groups resolve to
/// and an `Ungrouped` directory beneath each of those, which no group
/// represents. Built through the model so that only the damage is synthetic.
enum OrphanedCorpus {
    static let orphans = 655
    static let directories = 30

    struct NoSourcesPhase: Error {}

    static func alamofire() throws -> [UInt8] {
        var project = try Project.load(try Fixtures.load("corpus/Alamofire-Alamofire/Alamofire.pbxproj"))
        var seen: Set<String> = []
        var existing: [String] = []
        for group in project.groups where group.isa == Kind.group {
            guard case .relative(let directory)? = project.resolvedPath(of: group.id), !directory.isEmpty, seen.insert(directory).inserted else { continue }
            existing.append(directory)
        }
        existing = Array(existing.sorted().prefix(directories / 2))
        let all = existing + existing.map { $0 + "/Ungrouped" }
        guard let phase = project.targets.flatMap(\.buildPhases).compactMap(project.buildPhase).first(where: { $0.isa == "PBXSourcesBuildPhase" }) else {
            throw NoSourcesPhase()
        }
        for index in 0..<orphans {
            let hex = String(index, radix: 16, uppercase: true)
            let reference = ObjectID("FEEDFACE0000000000000000".dropLast(hex.count) + hex)
            let buildFile = ObjectID("BADF00D00000000000000000".dropLast(hex.count) + hex)
            let directory = all[index % all.count]
            let name = "Orphan\(index).swift"
            try project.createObject(reference, isa: Kind.fileReference, attributes: [
                NewEntry("lastKnownFileType", .string("sourcecode.swift")),
                NewEntry("name", .string(name)),
                NewEntry("path", .string(directory + "/" + name)),
                NewEntry("sourceTree", .string(Kind.sourceRootSourceTree)),
            ])
            try project.createObject(buildFile, isa: Kind.buildFile, attributes: [NewEntry("fileRef", project.reference(to: reference))])
            try project.addPhaseEntry(buildFile, to: phase.id)
        }
        return project.serialize()
    }
}
