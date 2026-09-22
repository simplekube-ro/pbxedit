import Foundation
import XCTest

/// The oracle lane (add-command task 7.1, remove-command task 6.3,
/// move-command task 6.3, lint-fix task 8.3): `xcodebuild -list -json
/// -project` reads every post-operation project. Skipped cleanly where
/// `xcodebuild` is absent — unless `ORACLE_REQUIRED` is set, in which case
/// the absence is a failure (release-distribution task 3.1, design D3), so
/// the CI job that is meant to run this lane cannot go green without it.
final class OracleTests: XCTestCase {
    private static let xcodebuild = URL(fileURLWithPath: "/usr/bin/xcodebuild")

    /// The environment variable that turns a missing `xcodebuild` from a skip
    /// into a failure: any non-empty value counts.
    static let requiredVariable = "ORACLE_REQUIRED"

    enum Gate: Equatable {
        case run
        case skip
        case fail
    }

    /// The lane's decision, a pure function of the two facts it depends on.
    static func gate(xcodebuildAvailable: Bool, required: String?) -> Gate {
        if xcodebuildAvailable { return .run }
        if let required, !required.isEmpty { return .fail }
        return .skip
    }

    /// Each entry: a fixture, the files to create (for `move`, the
    /// destinations, as the user's own move leaves them), and the
    /// invocations (subcommand first) to run on it before the oracle reads it.
    private static let scenarios: [(name: String, fixture: String, files: [String], invocations: [[String]])] = [
        // The rules fixtures have no build configuration lists, which xcodebuild refuses
        // whatever their membership looks like, so the repair scenarios use repair/ and the substitute.
        ("lint --fix: mixed damage", "repair/app.pbxproj", [], [["lint", "--fix"]]),
        ("move: within a target", "move/app.pbxproj", ["App/Features/Foo.swift"], [["move", "App/Views/Foo.swift", "App/Features/Foo.swift"]]),
        ("move: groups created", "move/app.pbxproj", ["App/Features/Modern/Foo.swift"], [["move", "App/Views/Foo.swift", "App/Features/Modern/Foo.swift"]]),
        ("move: source-root reference into a name-only group", "move/app.pbxproj", ["AppTests/State/FooTests.swift"],
         [["move", "AppTests/Views/FooTests.swift", "AppTests/State/FooTests.swift"]]),
        ("move: source-root reference respelled", "move/app.pbxproj", ["AppTests/Services/StateTests.swift"],
         [["move", "AppTests/State/StateTests.swift", "AppTests/Services/StateTests.swift"]]),
        ("move: rename in place", "move/app.pbxproj", ["App/New.swift"], [["move", "App/Old.swift", "App/New.swift"]]),
        ("move: rename changing the extension", "move/app.pbxproj", ["App/Old.m"], [["move", "App/Old.swift", "App/Old.m"]]),
        ("move: cross-target", "move/app.pbxproj", ["AppSlowTests/Services/RateTests.swift"],
         [["move", "AppTests/Services/RateTests.swift", "AppSlowTests/Services/RateTests.swift"]]),
        ("move: cross-target with --keep-membership", "move/app.pbxproj", ["AppSlowTests/Services/RateTests.swift"],
         [["move", "AppTests/Services/RateTests.swift", "AppSlowTests/Services/RateTests.swift", "--keep-membership"]]),
        ("move: platform filters dropped", "move/app.pbxproj", ["App/Shared/Panel.swift"], [["move", "App/iOS/Panel.swift", "App/Shared/Panel.swift"]]),
        ("move: --target and --platform", "move/app.pbxproj", ["App/Mixed/Foo.swift"],
         [["move", "App/Views/Foo.swift", "App/Mixed/Foo.swift", "--target", "AppExtension", "--platform", "ios"]]),
        ("move: into a synchronized folder", "move/app.pbxproj", ["App/Generated/User.swift"], [["move", "App/Models/User.swift", "App/Generated/User.swift"]]),
        ("move: directory rename", "move/app.pbxproj",
         ["App/Views/Modern/Top.swift", "App/Views/Modern/A/A1.swift", "App/Views/Modern/A/A2.swift", "App/Views/Modern/B/B1.swift", "App/Views/Modern/B/B2.swift"],
         [["move", "App/Views/Legacy", "App/Views/Modern"]]),
        ("move then add then remove", "move/app.pbxproj", ["App/Features/Foo.swift", "App/Views/Bar.swift"],
         [["move", "App/Views/Foo.swift", "App/Features/Foo.swift"], ["add", "App/Views/Bar.swift"], ["remove", "App/Features/Foo.swift"]]),
        ("add: new file", "add/app.pbxproj", ["App/Views/Bar.swift"], [["add", "App/Views/Bar.swift"]]),
        ("add: groups created", "add/app.pbxproj", ["App/Features/New/Thing.swift"], [["add", "App/Features/New/Thing.swift"]]),
        ("add: second target", "add/app.pbxproj", ["App/Services/Rate.swift"], [["add", "App/Services/Rate.swift", "--target", "AppExtension"]]),
        ("add: resource and header", "add/app.pbxproj", ["App/Resources/Localizable.xcstrings", "AppKit/Extra.h"],
         [["add", "App/Resources/Localizable.xcstrings", "AppKit/Extra.h"]]),
        ("add: project-only", "add/app.pbxproj", ["App/App.entitlements"], [["add", "App/App.entitlements"]]),
        ("add: pathless group", "add/app.pbxproj", ["AppTests/Views/BarTests.swift"], [["add", "AppTests/Views/BarTests.swift"]]),
        ("add: platform filters", "add/app.pbxproj", ["App/tvOS/TV3.swift", "App/Filtered/New.swift"],
         [["add", "App/tvOS/TV3.swift"], ["add", "App/Filtered/New.swift", "--platform", "ios,tvos"]]),
        ("add: unknown type with --phase", "add/app.pbxproj", ["App/data.bin"], [["add", "App/data.bin", "--phase", "resources", "--target", "App"]]),
        ("add: partial membership completed", "add/partial.pbxproj", ["AppTests/Views/FooTests.swift"],
         [["add", "AppTests/Views/FooTests.swift", "--target", "App"]]),
        ("remove: ordinary file", "remove/app.pbxproj", [], [["remove", "App/Services/Rate.swift"]]),
        ("remove: --all", "remove/app.pbxproj", [], [["remove", "App/Services/Cache.swift", "--all"]]),
        ("remove: --target", "remove/app.pbxproj", [], [["remove", "App/Services/Cache.swift", "--target", "AppExtension"]]),
        ("remove: last target detached", "remove/app.pbxproj", [], [["remove", "App/Services/Rate.swift", "--target", "App"]]),
        ("remove: project-only file", "remove/app.pbxproj", [], [["remove", "App/App.entitlements"]]),
        ("remove: chain pruned", "remove/app.pbxproj", [], [["remove", "App/Features/New/Thing.swift"]]),
        ("remove: a directory's files", "remove/app.pbxproj", [], [["remove", "App/tvOS/TV1.swift", "App/tvOS/TV2.swift", "App/Shared.swift", "--all"]]),
        ("remove: damaged membership", "add/partial.pbxproj", [], [["remove", "AppTests/Views/FooTests.swift"]]),
        ("add then remove", "add/app.pbxproj", ["App/Features/New/Thing.swift"],
         [["add", "App/Features/New/Thing.swift"], ["remove", "App/Features/New/Thing.swift"]]),
    ]

    func testXcodebuildReadsEveryPostOperationProject() throws {
        try Self.skipWithoutXcodebuild()
        for scenario in Self.scenarios {
            let project = try TemporaryProject(fixture: scenario.fixture)
            for file in scenario.files { try project.touch(file) }
            try Self.runAndList(scenario.name, project: project, invocations: scenario.invocations)
        }
    }

    /// Task 8.3: the repaired reference-workload substitute. The originating
    /// project is private; this is the same synthesis `RepairPerformanceTests`
    /// measures, repaired through the binary.
    func testXcodebuildReadsTheRepairedWorkloadSubstitute() throws {
        try Self.skipWithoutXcodebuild()
        let project = try TemporaryProject(try OrphanedCorpus.alamofire(), name: "Alamofire")
        let before = try pbxedit(["lint", "--json", "--project", "Alamofire.xcodeproj"], in: project.root)
        XCTAssertEqual(before.status, 1)
        XCTAssertEqual((try jsonObject(before)["summary"] as? [String: Int])?["errors"], OrphanedCorpus.orphans)
        try Self.runAndList("lint --fix: workload substitute", project: project, invocations: [["lint", "--fix"]])
        let after = try pbxedit(["lint", "--json", "--project", "Alamofire.xcodeproj"], in: project.root)
        XCTAssertEqual(after.status, 0, after.stdout)
        XCTAssertEqual((try jsonObject(after)["summary"] as? [String: Int])?["errors"], 0)
    }

    private struct XcodebuildMissing: Error, CustomStringConvertible {
        var description: String {
            "xcodebuild is not available and \(requiredVariable) is set; the oracle lane must run on macOS with Xcode installed"
        }
    }

    private static func skipWithoutXcodebuild() throws {
        let available = try FileManager.default.isExecutableFile(atPath: xcodebuild.path) && developerDirectoryIsSet()
        switch gate(xcodebuildAvailable: available, required: ProcessInfo.processInfo.environment[requiredVariable]) {
        case .run:
            return
        case .skip:
            throw XCTSkip("xcodebuild is not available; the oracle lane runs on macOS with Xcode installed")
        case .fail:
            throw XcodebuildMissing()
        }
    }

    /// Runs the invocations — each must write, and exit 0 unless it is a
    /// `lint --fix` that leaves errors, which exits 1 as `lint` does — then
    /// has `xcodebuild -list` read the result.
    private static func runAndList(_ name: String, project: TemporaryProject, invocations: [[String]]) throws {
        for invocation in invocations {
            let result = try pbxedit(invocation + ["--project", project.xcodeproj.lastPathComponent], in: project.root)
            let expected: [Int32] = invocation.first == "lint" ? [0, 1] : [0]
            XCTAssertTrue(expected.contains(result.status), "\(name): \(invocation): \(result.stderr)\(result.stdout)")
            XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: modified\n"), "\(name): \(invocation): \(result.stdout)")
        }
        let listing = try list(project.xcodeproj)
        XCTAssertEqual(listing.status, 0, "\(name): xcodebuild -list failed:\n\(listing.output)")
        let object = try XCTUnwrap(try? JSONSerialization.jsonObject(with: Data(listing.output.utf8)) as? [String: Any], "\(name): \(listing.output)")
        let targets = (object["project"] as? [String: Any])?["targets"] as? [String]
        XCTAssertEqual(targets?.isEmpty, false, "\(name): \(listing.output)")
    }

    private static func developerDirectoryIsSet() throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func list(_ xcodeproj: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = xcodebuild
        process.arguments = ["-list", "-json", "-project", xcodeproj.path]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: stdout, as: UTF8.self)
        return (process.terminationStatus, process.terminationStatus == 0 ? output : output + String(decoding: stderr, as: UTF8.self))
    }
}
