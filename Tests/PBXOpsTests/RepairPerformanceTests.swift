import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// The closest substitute for the originating project (integrity-repair
/// design Evidence): `Alamofire.pbxproj`, the largest corpus file, plus
/// `orphans` `SOURCE_ROOT` references in no group, each built, spread over
/// `directories` directories — the first half ones existing groups resolve
/// to, the second half an `Ungrouped` directory beneath each of those, which
/// no group represents. The originating project itself is private and never
/// committed; `PBXEDIT_EXTRA_CORPUS` is not used here because the synthesis
/// needs a project whose groups are known to be sound.
enum OrphanedCorpus {
    static let orphans = 655
    static let directories = 30

    struct Synthesis {
        let bytes: [UInt8]
        let existingDirectories: [String]
        let newDirectories: [String]
    }

    struct NoSourcesPhase: Error {}

    static func alamofire() throws -> Synthesis {
        var project = try Project.load(try Fixtures.load("corpus/Alamofire-Alamofire/Alamofire.pbxproj"))
        var seen: Set<String> = []
        var existing: [String] = []
        for group in project.groups where group.isa == Kind.group {
            guard case .relative(let directory)? = project.resolvedPath(of: group.id), !directory.isEmpty, seen.insert(directory).inserted else { continue }
            existing.append(directory)
        }
        existing = Array(existing.sorted().prefix(directories / 2))
        let new = existing.map { $0 + "/Ungrouped" }
        let all = existing + new
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
        return Synthesis(bytes: project.serialize(), existingDirectories: existing, newDirectories: new)
    }
}

/// Tasks 8.1 and 8.2: the reference workload on the substitute, through
/// `OperationRunner` in a temporary `.xcodeproj`, measured. The class name
/// matches CI's release-mode `--filter PerformanceTests`.
final class RepairPerformanceTests: XCTestCase {
    /// TODO § 9's budget, in a release build.
    static let releaseLimit: TimeInterval = 2.0
    /// Debug builds only guard against a blow-up.
    static let debugLimit: TimeInterval = 30

    func testSixHundredFiftyFiveOrphansAreRepairedInOneWrite() throws {
        let synthesis = try OrphanedCorpus.alamofire()
        XCTAssertEqual(synthesis.existingDirectories.count, OrphanedCorpus.directories / 2, "\(synthesis.existingDirectories)")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pbxedit-workload-\(UUID().uuidString)")
        let xcodeproj = root.appendingPathComponent("Alamofire.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pbxproj = xcodeproj.appendingPathComponent("project.pbxproj")
        try Data(synthesis.bytes).write(to: pbxproj)

        let started = Date()
        let runner = try OperationRunner(projectFile: pbxproj)
        let loaded = Date()
        let before = RuleSet.standard.evaluate(runner.project)
        let evaluated = Date()
        XCTAssertEqual(before.filter { $0.rule == .M3 }.count, OrphanedCorpus.orphans)
        XCTAssertEqual(before.filter { $0.severity == .error && $0.rule != .M3 }, [], "the corpus file is clean apart from the damage")
        let repair = RepairPlanner.plan(before, in: runner.project)
        let planned = Date()
        XCTAssertEqual(repair.repaired.count, OrphanedCorpus.orphans)
        XCTAssertEqual(repair.notFixable, [])
        let applyStarted = Date()
        let applied = try repair.plan.apply(to: runner.project)
        let applyFinished = Date()
        let runStarted = Date()
        let result = runner.run(repair.plan, dryRun: false, verification: .wholeProject(before: before, selected: repair.repaired))
        let runFinished = Date()
        XCTAssertEqual(result.outcome, .ok, "\(result.findings.prefix(5))")
        XCTAssertTrue(result.modified)

        // One write: the bytes on disk are the plan's result, nothing is left beside the file.
        let onDisk = Array(try Data(contentsOf: pbxproj))
        XCTAssertEqual(onDisk, applied.serialize())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: xcodeproj.path), ["project.pbxproj"])

        // The diff: nothing removed; every added line is a children entry or a line of a new PBXGroup definition.
        let diff = lineDiff(String(decoding: synthesis.bytes, as: UTF8.self), String(decoding: onDisk, as: UTF8.self))
        XCTAssertEqual(diff.removed, [])
        let childLine = try NSRegularExpression(pattern: "^\t\t\t\t[0-9A-F]{24} /\\* [^\n]+ \\*/,\n$")
        let groupLines: [NSRegularExpression] = try [
            "^\t\t[0-9A-F]{24} /\\* Ungrouped \\*/ = \\{\n$", "^\t\t\tisa = PBXGroup;\n$", "^\t\t\tchildren = \\(\n$", "^\t\t\t\\);\n$",
            "^\t\t\tpath = Ungrouped;\n$", "^\t\t\tsourceTree = \"<group>\";\n$", "^\t\t\\};\n$",
        ].map { try NSRegularExpression(pattern: $0) }
        func matches(_ line: String, _ expression: NSRegularExpression) -> Bool {
            expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        var children = 0
        var definition = 0
        for line in diff.added {
            if matches(line, childLine) {
                children += 1
            } else if groupLines.contains(where: { matches(line, $0) }) {
                definition += 1
            } else {
                XCTFail("unexpected added line: \(line.debugDescription)")
            }
        }
        let newGroups = synthesis.newDirectories.count
        XCTAssertEqual(children, OrphanedCorpus.orphans + newGroups, "one children line per orphan, plus each new group in its parent")
        XCTAssertEqual(definition, newGroups * 7)

        // Zero M3 afterwards, nothing new, the census.
        let reloaded = try Project.load(onDisk)
        let after = RuleSet.standard.evaluate(reloaded)
        XCTAssertEqual(after.filter { $0.rule == .M3 }, [])
        let known = Set(before.map(\.identity))
        XCTAssertEqual(after.filter { !known.contains($0.identity) }, [])
        XCTAssertEqual(reloaded.fileReferences.count, runner.project.fileReferences.count)
        XCTAssertEqual(reloaded.buildFiles.count, runner.project.buildFiles.count)
        XCTAssertEqual(reloaded.groups.count, runner.project.groups.count + newGroups)
        for directory in synthesis.newDirectories { XCTAssertEqual(reloaded.groups(at: directory).count, 1, directory) }
        assertPlutilLints(onDisk)

        #if DEBUG
        let configuration = "debug"
        let limit = RepairPerformanceTests.debugLimit
        #else
        let configuration = "release"
        let limit = RepairPerformanceTests.releaseLimit
        #endif
        let seconds = { (from: Date, to: Date) in String(format: "%.3f", to.timeIntervalSince(from)) }
        print("SCALE \(configuration) Alamofire.pbxproj+\(OrphanedCorpus.orphans) bytes=\(synthesis.bytes.count) objects=\(runner.project.objects.count) "
            + "orphans=\(OrphanedCorpus.orphans) directories=\(OrphanedCorpus.directories) newGroups=\(newGroups) "
            + "load=\(seconds(started, loaded))s evaluate=\(seconds(loaded, evaluated))s plan=\(seconds(evaluated, planned))s "
            + "apply=\(seconds(applyStarted, applyFinished))s run=\(seconds(runStarted, runFinished))s "
            + "total=\(seconds(started, runFinished))s")
        XCTAssertLessThan(runFinished.timeIntervalSince(started), limit, "load, evaluate, plan, apply and the verified write (\(configuration) build)")
    }
}
