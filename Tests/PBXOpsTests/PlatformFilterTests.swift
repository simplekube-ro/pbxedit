import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// platform-filter-canonical-form tasks 1.1, 2.1, 3.1 and 3.3: how a build
/// file's platform filter is read, checked and written (design D1–D3),
/// against the Xcode 27 evidence under `Tests/Fixtures/xcode27/`.
final class PlatformFilterTests: XCTestCase {
    private static let saved = "xcode27/platform-filters-after-xcode27-save.pbxproj"
    private static let legacy = "xcode27/platform-filters-before.pbxproj"

    private func target(_ name: String, in project: Project) throws -> Target {
        try XCTUnwrap(project.targets.first { $0.name == name }, name)
    }

    private func filters(of path: String, in project: Project) -> [[String]] {
        MembershipReport(project: project, path: path).memberships.map(\.platformFilters)
    }

    // MARK: 1.1 — Both spellings are read as one value

    // Spec: Every spelling in the Xcode-saved probe is read.
    func testEverySpellingInTheXcodeSavedProbeIsRead() throws {
        let project = try loadProject(Self.saved)
        XCTAssertEqual(filters(of: "App/Filtered/F1.swift", in: project), [["ios"]])
        XCTAssertEqual(filters(of: "App/Filtered/F2.swift", in: project), [["maccatalyst"]])
        XCTAssertEqual(filters(of: "AppKit/Kit.swift", in: project), [["maccatalyst"]])
        XCTAssertEqual(filters(of: "App/Mixed/OnlyApp.swift", in: project), [["macos"]])
        XCTAssertEqual(filters(of: "App/Mixed/OnlyExt.swift", in: project), [["ios"]])
        XCTAssertEqual(filters(of: "App/iOS/Panel.swift", in: project), [["ios", "maccatalyst"]])
        XCTAssertEqual(filters(of: "App/Shared/Common.swift", in: project), [["ios", "tvos"]])
        XCTAssertEqual(filters(of: "App/tvOS/TV1.swift", in: project), [["tvos"]])
        XCTAssertEqual(filters(of: "App/Views/Foo.swift", in: project), [[]])
        let app = try XCTUnwrap(TargetMembers(project: project, target: "App"))
        XCTAssertEqual(app.members.first { $0.path == "App/Filtered/F1.swift" }?.platformFilters, ["ios"])
        XCTAssertEqual(app.members.first { $0.path == "App/Filtered/F2.swift" }?.platformFilters, ["maccatalyst"])
        let kit = try XCTUnwrap(TargetMembers(project: project, target: "AppKit"))
        XCTAssertEqual(kit.members.map(\.platformFilters), [[], ["maccatalyst"]], "AppKit.h in Headers, Kit.swift in Sources")
    }

    // Design D1: the one reading, with the plural key winning when both are present.
    func testTheReadRuleNormalisesBothKeys() throws {
        let source = """
            { objects = {
                P1 = {isa = PBXProject; mainGroup = G1; };
                G1 = {isa = PBXGroup; children = (F1, ); sourceTree = "<group>"; };
                F1 = {isa = PBXFileReference; path = x.c; sourceTree = "<group>"; };
                B1 = {isa = PBXBuildFile; fileRef = F1; platformFilter = ios; };
                B2 = {isa = PBXBuildFile; fileRef = F1; platformFilters = (ios, tvos, ); };
                B3 = {isa = PBXBuildFile; fileRef = F1; };
                B4 = {isa = PBXBuildFile; fileRef = F1; platformFilter = maccatalyst; platformFilters = (tvos, ); };
            }; rootObject = P1; }
            """
        let project = try Project.load(Array(source.utf8))
        XCTAssertEqual(PlatformFilters.read(from: try XCTUnwrap(project.buildFile("B1"))), ["ios"])
        XCTAssertEqual(PlatformFilters.read(from: try XCTUnwrap(project.buildFile("B2"))), ["ios", "tvos"])
        XCTAssertEqual(PlatformFilters.read(from: try XCTUnwrap(project.buildFile("B3"))), [])
        XCTAssertEqual(PlatformFilters.read(from: try XCTUnwrap(project.buildFile("B4"))), ["tvos"], "plural first, as the shipped readers did")
    }

    // Spec: The legacy spelling reads the same.
    func testTheLegacySpellingReadsTheSameAsTheXcodeSavedCopy() throws {
        let legacy = try loadProject(Self.legacy)
        let saved = try loadProject(Self.saved)
        var compared = 0
        for reference in legacy.fileReferences {
            guard case .relative(let path)? = legacy.resolvedPath(of: reference.id) else { continue }
            XCTAssertEqual(MembershipReport(project: legacy, path: path), MembershipReport(project: saved, path: path), path)
            compared += 1
        }
        XCTAssertGreaterThan(compared, 30)
        for target in legacy.targets.compactMap(\.name) {
            XCTAssertEqual(TargetMembers(project: legacy, target: target), TargetMembers(project: saved, target: target), target)
        }
        XCTAssertEqual(legacy.targets.compactMap(\.name).sorted(), ["App", "AppExtension", "AppKit", "AppSlowTests", "AppTests"])
        XCTAssertEqual(RuleSet.standard.evaluate(legacy).filter { $0.rule == .S4 }, [])
        XCTAssertEqual(RuleSet.standard.evaluate(saved).filter { $0.rule == .S4 }, [])
        // The two files differ only in the two probe lines and the synchronized group's layout.
        let diff = lineDiff(try Fixtures.text(Self.legacy), try Fixtures.text(Self.saved))
        XCTAssertEqual(diff.removed.filter { $0.contains("platformFilter") }.count, 2)
        XCTAssertEqual(diff.added.filter { $0.contains("platformFilter") }.count, 2)
    }

    // Spec: Inference reads the singular key.
    func testInferenceReadsTheSingularKey() throws {
        let project = try loadProject(Self.saved)
        let conventions = Conventions()
        let kit = try conventions.platformFilters(for: "AppKit/New.swift", kind: .source, target: try target("AppKit", in: project), in: project)
        XCTAssertEqual(kit.value, ["maccatalyst"])
        XCTAssertEqual(kit.source, .inferred(siblings: 1, directory: "AppKit"))
        let ext = try conventions.platformFilters(for: "App/Mixed/New.swift", kind: .source, target: try target("AppExtension", in: project), in: project)
        XCTAssertEqual(ext.value, ["ios"])
        XCTAssertEqual(ext.source, .inferred(siblings: 1, directory: "App/Mixed"))
        XCTAssertThrowsError(try conventions.platformFilters(for: "App/Filtered/New.swift", kind: .source, target: try target("App", in: project), in: project)) { error in
            guard case PlanError.ambiguousPlatformFilters(_, let targetName, let directory, let variants)? = error as? PlanError else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(targetName, "App")
            XCTAssertEqual(directory, "App/Filtered")
            XCTAssertEqual(variants, [PlanError.FilterVariant(filters: ["ios"], count: 1), PlanError.FilterVariant(filters: ["maccatalyst"], count: 1)])
        }
    }

    // MARK: 3.1 — Filters are written as Xcode writes them

    // Design D2: the spelling rule, the table from the Xcode 27 probe.
    func testTheSpellingRuleFollowsTheXcode27Table() {
        XCTAssertEqual(PlatformFilters.spelling(of: ["ios"]), .singular("ios"))
        XCTAssertEqual(PlatformFilters.spelling(of: ["maccatalyst"]), .singular("maccatalyst"))
        XCTAssertEqual(PlatformFilters.spelling(of: ["tvos"]), .plural(["tvos"]))
        XCTAssertEqual(PlatformFilters.spelling(of: ["macos"]), .plural(["macos"]))
        XCTAssertEqual(PlatformFilters.spelling(of: ["ios", "tvos"]), .plural(["ios", "tvos"]))
        XCTAssertEqual(PlatformFilters.spelling(of: ["ios", "maccatalyst"]), .plural(["ios", "maccatalyst"]))
        XCTAssertEqual(PlatformFilters.spelling(of: ["tvos", "ios"]), .plural(["tvos", "ios"]), "in the order given")
        XCTAssertEqual(PlatformFilters.spelling(of: []), .none)
        for name in PlatformFilters.known where !PlatformFilters.singularValues.contains(name) {
            XCTAssertEqual(PlatformFilters.spelling(of: [name]), .plural([name]), name)
        }
    }

    // Spec: Lone ios and lone maccatalyst are singular; Everything else is the array.
    func testCreateBuildFileWritesTheCanonicalSpelling() throws {
        let project = try loadProject("move/app.pbxproj")
        let views: ObjectID = "AA0000000000000000000003"
        let appSources: ObjectID = "CC0000000000000000000001"
        let ref: ObjectID = "0123456789ABCDEF01234567"
        let buildFile: ObjectID = "0123456789ABCDEF01234569"
        let expectations: [(filters: [String], line: String)] = [
            (["ios"], "platformFilter = ios; "),
            (["maccatalyst"], "platformFilter = maccatalyst; "),
            (["ios", "tvos"], "platformFilters = (ios, tvos, ); "),
            (["tvos"], "platformFilters = (tvos, ); "),
            (["ios", "maccatalyst"], "platformFilters = (ios, maccatalyst, ); "),
            ([], ""),
        ]
        for expectation in expectations {
            let plan = Plan(steps: [
                .createFileReference(id: ref, path: "Bar.swift", name: nil, sourceTree: "<group>", lastKnownFileType: "sourcecode.swift"),
                .addChild(ref, to: views, position: .last),
                .createBuildFile(id: buildFile, fileRef: ref, platformFilters: expectation.filters),
                .addPhaseEntry(buildFile, to: appSources, position: .last),
            ])
            let result = try plan.apply(to: project)
            let written = try XCTUnwrap(result.buildFile(buildFile))
            XCTAssertEqual(PlatformFilters.read(from: written), expectation.filters, "\(expectation.filters)")
            switch PlatformFilters.spelling(of: expectation.filters) {
            case .singular(let value):
                XCTAssertEqual(written.platformFilter, value)
                XCTAssertNil(written.platformFilters, "never both keys")
            case .plural(let values):
                XCTAssertEqual(written.platformFilters, values)
                XCTAssertNil(written.platformFilter, "never both keys")
            case .none:
                XCTAssertNil(written.platformFilter)
                XCTAssertNil(written.platformFilters)
            }
            let text = String(decoding: result.serialize(), as: UTF8.self)
            let line = "\t\t\(buildFile) /* Bar.swift in Sources */ = {isa = PBXBuildFile; fileRef = \(ref) /* Bar.swift */; \(expectation.line)};\n"
            XCTAssertTrue(text.contains(line), "\(expectation.filters): expected\n\(line)in\n\(text)")
            XCTAssertEqual(RuleSet.standard.evaluate(result, scope: [ref, buildFile]), [], "\(expectation.filters)")
            assertPlutilLints(result.serialize(), "\(expectation.filters)")
        }
    }

    // MARK: 3.3 — An unchanged filter is never re-spelled; a changed value replaces the spelling

    private func move(_ from: String, _ to: String, in project: Project, flags: Conventions.Flags = Conventions.Flags()) throws -> Plan {
        try MovePlanner.plan(from: from, to: to, in: project, conventions: Conventions(flags: flags), keepMembership: false,
                             disk: MemoryDisk([to]), exemptions: nil, minter: IDMinter(generator: FixedGenerator()))
    }

    private func attributeSteps(_ plan: Plan) -> [Step] {
        plan.steps.filter { if case .setAttribute = $0 { return true } else { return false } }
    }

    private func applied(_ plan: Plan, to project: Project) throws -> Project {
        let result = try plan.apply(to: project)
        assertOperationClean(result, scope: plan.touched)
        return result
    }

    private func definitionLine(of id: ObjectID, in project: Project) -> String? {
        String(decoding: project.serialize(), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            .first { $0.hasPrefix("\t\t\(id.rawValue) ") }.map(String.init)
    }

    // Spec: A move that keeps the value keeps the bytes.
    func testAMoveThatKeepsTheValueEmitsNoFilterStep() throws {
        let project = try loadProject(Self.saved)
        let f1: ObjectID = "BB0000000000000000000140"
        // F1's sibling F2 carries maccatalyst, so the flag keeps the value at ios.
        let plan = try move("App/Filtered/F1.swift", "App/Filtered/G1.swift", in: project, flags: Conventions.Flags(platformFilters: ["ios"]))
        XCTAssertEqual(attributeSteps(plan).map { if case .setAttribute(let key, _, _) = $0 { return key } else { return "" } }, ["path"])
        XCTAssertFalse(plan.changes.contains { $0.action == .setAttribute && $0.object == f1 })
        let result = try applied(plan, to: project)
        XCTAssertEqual(definitionLine(of: f1, in: result),
                       "\t\tBB0000000000000000000140 /* G1.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000260 /* G1.swift */; platformFilter = ios; };")
        // Likewise a plural spelling whose value the siblings confirm.
        let tv1: ObjectID = "BB0000000000000000000120"
        let plural = try move("App/tvOS/TV1.swift", "App/tvOS/TV3.swift", in: project)
        XCTAssertFalse(plural.changes.contains { $0.action == .setAttribute && $0.object == tv1 })
        XCTAssertEqual(definitionLine(of: tv1, in: try applied(plural, to: project)),
                       "\t\tBB0000000000000000000120 /* TV3.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000240 /* TV3.swift */; platformFilters = (tvos, ); };")
        // And the legacy spelling, whose value is unchanged, is left alone too.
        let legacy = try loadProject(Self.legacy)
        let kept = try move("App/Filtered/F1.swift", "App/Filtered/G1.swift", in: legacy, flags: Conventions.Flags(platformFilters: ["ios"]))
        XCTAssertFalse(kept.changes.contains { $0.action == .setAttribute && $0.object == f1 })
        XCTAssertEqual(definitionLine(of: f1, in: try applied(kept, to: legacy)),
                       "\t\tBB0000000000000000000140 /* G1.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000260 /* G1.swift */; platformFilters = (ios, ); };")
    }

    // Spec: The legacy spelling is replaced wholesale.
    func testAChangedValueReplacesTheLegacySpellingWholesale() throws {
        let legacy = try loadProject(Self.legacy)
        let f1: ObjectID = "BB0000000000000000000140"
        // Attached to AppKit, whose sibling has `platformFilter = maccatalyst;`: a new build file, singular.
        let attached = try move("App/Filtered/F1.swift", "AppKit/F1.swift", in: legacy, flags: Conventions.Flags(targets: ["AppKit"]))
        XCTAssertEqual(attached.decisions.first { $0.attribute == "platformFilters" }?.value, "AppKit: maccatalyst")
        XCTAssertEqual(attached.decisions.first { $0.attribute == "platformFilters" }?.source, .inferred(siblings: 1, directory: "AppKit"))
        let created = try XCTUnwrap(attached.changes.first { $0.action == .createdBuildFile }?.object)
        let attachedResult = try applied(attached, to: legacy)
        XCTAssertNil(attachedResult.buildFile(f1), "the App build file is gone")
        XCTAssertEqual(attachedResult.buildFile(created)?.platformFilter, "maccatalyst")
        XCTAssertNil(attachedResult.buildFile(created)?.platformFilters)
        // Retained in App with a new value: the singular key is set and the legacy plural key removed.
        let retained = try move("App/Filtered/F1.swift", "AppKit/F1.swift", in: legacy, flags: Conventions.Flags(targets: ["App"], platformFilters: ["maccatalyst"]))
        XCTAssertEqual(attributeSteps(retained).filter { if case .setAttribute(_, let id, _) = $0 { return id == f1 } else { return false } }, [
            .setAttribute(key: "platformFilter", of: f1, to: .string("maccatalyst")),
            .setAttribute(key: "platformFilters", of: f1, to: nil),
        ])
        XCTAssertEqual(retained.changes.filter { $0.action == .setAttribute && $0.object == f1 }.map(\.detail), ["platformFilters = maccatalyst (was ios)"])
        let retainedResult = try applied(retained, to: legacy)
        XCTAssertEqual(definitionLine(of: f1, in: retainedResult),
                       "\t\tBB0000000000000000000140 /* F1.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000260 /* F1.swift */; platformFilter = maccatalyst; };")
        XCTAssertEqual(MembershipReport(project: retainedResult, path: "AppKit/F1.swift").memberships.map(\.platformFilters), [["maccatalyst"]])
        // And a singular key growing to two values becomes the array, the singular key removed.
        let saved = try loadProject(Self.saved)
        let grown = try move("App/Filtered/F1.swift", "App/Filtered/G1.swift", in: saved, flags: Conventions.Flags(platformFilters: ["ios", "tvos"]))
        XCTAssertEqual(attributeSteps(grown).filter { if case .setAttribute(_, let id, _) = $0 { return id == f1 } else { return false } }, [
            .setAttribute(key: "platformFilters", of: f1, to: .array([.string("ios"), .string("tvos")])),
            .setAttribute(key: "platformFilter", of: f1, to: nil),
        ])
        XCTAssertEqual(definitionLine(of: f1, in: try applied(grown, to: saved)),
                       "\t\tBB0000000000000000000140 /* G1.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000260 /* G1.swift */; platformFilters = (ios, tvos, ); };")
    }

    /// Review cleanup: one wording for filters, shared by `move`'s decision
    /// line and the filter rewrite's change line.
    func testFiltersAreDescribedOneWay() {
        XCTAssertEqual(PlatformFilters.describe([]), "none")
        XCTAssertEqual(PlatformFilters.describe(["ios"]), "ios")
        XCTAssertEqual(PlatformFilters.describe(["ios", "macos"]), "ios, macos")
    }
}
