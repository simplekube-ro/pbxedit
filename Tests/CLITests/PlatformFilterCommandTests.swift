import Foundation
import XCTest

/// platform-filter-canonical-form tasks 4.2 and 4.3: the spelling the
/// binary writes (capability `platform-filters`) and the regression for
/// issue #6 against the Xcode 27 evidence under `Tests/Fixtures/xcode27/`.
final class PlatformFilterCommandTests: XCTestCase {
    private static let probe = "xcode27/platform-filters-after-xcode27-save.pbxproj"

    private func lines(_ bytes: [UInt8]) -> [String] {
        String(decoding: bytes, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// The definition line of the build file annotated `<name> in Sources`.
    private func buildFileLine(_ bytes: [UInt8], _ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        try XCTUnwrap(lines(bytes).first { $0.contains("/* \(name) in Sources */ = {isa = PBXBuildFile;") }, "no build file for \(name)", file: file, line: line)
    }

    /// The S4 findings `lint --json` reports, whatever the exit status.
    private func s4Findings(_ project: TemporaryProject) throws -> [[String: Any]] {
        let result = try pbxedit(["lint", "--json", "--project", project.xcodeproj.lastPathComponent], in: project.root)
        XCTAssertTrue([0, 1].contains(result.status), result.stderr)
        let findings = try XCTUnwrap(try jsonObject(result)["findings"] as? [[String: Any]])
        return findings.filter { $0["rule"] as? String == "S4" }
    }

    // Spec: Lone ios and lone maccatalyst are singular; Everything else is the array.
    func testAddWritesTheSpellingXcodeWrites() throws {
        let table: [(platform: String, spelled: String)] = [
            ("ios", "platformFilter = ios; "),
            ("maccatalyst", "platformFilter = maccatalyst; "),
            ("ios,tvos", "platformFilters = (ios, tvos, ); "),
            ("tvos", "platformFilters = (tvos, ); "),
            ("ios,maccatalyst", "platformFilters = (ios, maccatalyst, ); "),
            ("none", ""),
        ]
        // Canonical.swift: a basename the fixture does not have anywhere (it holds AppTests/Foo/Bar.swift).
        for row in table {
            let project = try TemporaryProject(fixture: "move/app.pbxproj")
            try project.touch("App/Views/Canonical.swift")
            let result = try pbxedit(["add", "App/Views/Canonical.swift", "--platform", row.platform, "--project", "App.xcodeproj"], in: project.root)
            XCTAssertEqual(result.status, 0, "\(row.platform): \(result.stderr)")
            XCTAssertTrue(result.stdout.contains("  platformFilters: App: \(row.platform == "none" ? "none" : row.platform.replacingOccurrences(of: ",", with: ", ")) (flag)\n"), "\(row.platform): \(result.stdout)")
            let line = try buildFileLine(try project.bytes(), "Canonical.swift")
            XCTAssertTrue(line.hasSuffix(" /* Canonical.swift */; \(row.spelled)};"), "\(row.platform): \(line)")
            XCTAssertEqual(line.components(separatedBy: "platformFilter").count - 1, row.spelled.isEmpty ? 0 : 1, "one key at most: \(line)")
            XCTAssertEqual(try s4Findings(project).count, 0, row.platform)
            let plutil = Process()
            plutil.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
            plutil.arguments = ["-lint", project.pbxproj.path]
            plutil.standardOutput = Pipe()
            try plutil.run()
            plutil.waitUntilExit()
            XCTAssertEqual(plutil.terminationStatus, 0, "\(row.platform): plutil -lint rejects the output")
        }
    }

    // Spec: JSON is unchanged by the spelling (The command surface names the attribute, not the key).
    func testTheJSONVocabularyIsUnchangedByTheSpelling() throws {
        let project = try TemporaryProject(fixture: "move/app.pbxproj")
        try project.touch("App/Views/Canonical.swift")
        let result = try pbxedit(["add", "--json", "App/Views/Canonical.swift", "--platform", "ios", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        let object = try jsonObject(result)
        let decisions = try XCTUnwrap(object["decisions"] as? [[String: Any]])
        XCTAssertEqual(decisions.map { $0["attribute"] as? String }, ["phase", "location", "targets", "platformFilters"])
        XCTAssertEqual(decisions[3]["value"] as? String, "App: ios")
        XCTAssertEqual((decisions[3]["source"] as? [String: Any])?["kind"] as? String, "flag")
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])
        let memberships = try XCTUnwrap(results.first?["memberships"] as? [[String: Any]])
        XCTAssertEqual(memberships.map { $0["platformFilters"] as? [String] }, [["ios"]])
        XCTAssertTrue(try buildFileLine(try project.bytes(), "Canonical.swift").hasSuffix(" /* Canonical.swift */; platformFilter = ios; };"))
        // query reads it back the same way, in both forms.
        let query = try pbxedit(["query", "--json", "App/Views/Canonical.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(query.status, 0, query.stderr)
        let queried = try XCTUnwrap((try jsonObject(query)["results"] as? [[String: Any]])?.first?["memberships"] as? [[String: Any]])
        XCTAssertEqual(queried.map { $0["platformFilters"] as? [String] }, [["ios"]])
        let text = try pbxedit(["query", "App/Views/Canonical.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertTrue(text.stdout.contains(", platforms: ios\n"), text.stdout)
    }

    // Spec: An inferred lone ios is singular too; Singular key reported as the same array (query).
    func testAnInferredLoneIosIsWrittenSingularAndQueryReadsTheProbe() throws {
        let project = try TemporaryProject(fixture: Self.probe)
        try project.touch("App/Mixed/New.swift")
        let result = try pbxedit(["add", "App/Mixed/New.swift", "--target", "AppExtension", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("  platformFilters: AppExtension: ios (inferred, 1 sibling in App/Mixed)\n"), result.stdout)
        XCTAssertTrue(try buildFileLine(try project.bytes(), "New.swift").hasSuffix(" /* New.swift */; platformFilter = ios; };"))
        XCTAssertEqual(try s4Findings(project).count, 0)
        let f1 = try pbxedit(["query", "App/Filtered/F1.swift", "AppKit/Kit.swift", "--project", "App.xcodeproj"], in: project.root)
        XCTAssertEqual(f1.status, 0, f1.stderr)
        XCTAssertTrue(f1.stdout.contains("target: App, phase: Sources, build file: BB0000000000000000000140, platforms: ios\n"), f1.stdout)
        XCTAssertTrue(f1.stdout.contains("target: AppKit, phase: Sources, build file: BB0000000000000000000151, platforms: maccatalyst\n"), f1.stdout)
    }

    // Spec: Regression for issue #6 (The Xcode-saved projects show no filter difference).
    func testTheReleaseCheckLeavesNoPlatformFilterDifferenceAgainstXcodesSave() throws {
        // Replays docs/RELEASING.md § 2 as it ran for v1.0.0, then compares
        // only the platform-filter lines with what Xcode 27.0 saved. The two
        // other kinds of difference in `xcode27/xcode27-save.diff` are
        // deliberately NOT compared here: Xcode lays the hand-written
        // one-line PBXFileSystemSynchronizedRootGroup out over several
        // lines, and in the repair project Xcode deletes the damage
        // `lint --fix` reports as not fixable (dangling children, a build
        // file in two phases, references no group reaches). Both are
        // handled in the release procedure, not by this change.
        let ops = try TemporaryProject(fixture: "move/app.pbxproj")
        try ops.touch("App/Views/Bar.swift")
        try ops.touch("App/Features/Foo.swift")
        for invocation in [
            ["add", "App/Views/Bar.swift"],
            ["move", "App/Views/Foo.swift", "App/Features/Foo.swift"],
            ["remove", "App/Services/Rate.swift"],
        ] {
            let result = try pbxedit(invocation + ["--project", "App.xcodeproj"], in: ops.root)
            XCTAssertEqual(result.status, 0, "\(invocation): \(result.stderr)")
            XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: modified\n"), result.stdout)
        }
        try assertFilterLinesMatch(ops, "xcode27/move-app-after-xcode27-save.pbxproj")

        let repair = try TemporaryProject(fixture: "repair/app.pbxproj")
        let fixed = try pbxedit(["lint", "--fix", "--project", "App.xcodeproj"], in: repair.root)
        XCTAssertEqual(fixed.status, 1, "unfixable damage remains: \(fixed.stderr)")
        XCTAssertTrue(fixed.stdout.hasSuffix("project.pbxproj: modified\n"), fixed.stdout)
        try assertFilterLinesMatch(repair, "xcode27/repair-app-after-xcode27-save.pbxproj")
    }

    private func assertFilterLinesMatch(_ project: TemporaryProject, _ saved: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let ours = lines(try project.bytes()).filter { $0.contains("platformFilter") }.sorted()
        let xcodes = lines(try Fixtures.load(saved)).filter { $0.contains("platformFilter") }.sorted()
        XCTAssertEqual(xcodes.count, 5, "the evidence carries five filtered build files", file: file, line: line)
        XCTAssertEqual(ours, xcodes, saved, file: file, line: line)
        XCTAssertEqual(try s4Findings(project).count, 0, saved, file: file, line: line)
    }
}
