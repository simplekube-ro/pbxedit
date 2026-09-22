import Foundation
import XCTest

/// Task 7.1 — the oracle lane: `xcodebuild -list -json -project` reads every
/// post-add project. Skipped cleanly where `xcodebuild` is absent.
final class OracleTests: XCTestCase {
    private static let xcodebuild = URL(fileURLWithPath: "/usr/bin/xcodebuild")

    /// Each entry: a fixture, the files to create, and the `add` invocations
    /// to run on it before the oracle reads it.
    private static let scenarios: [(name: String, fixture: String, files: [String], invocations: [[String]])] = [
        ("new file", "add/app.pbxproj", ["App/Views/Bar.swift"], [["App/Views/Bar.swift"]]),
        ("groups created", "add/app.pbxproj", ["App/Features/New/Thing.swift"], [["App/Features/New/Thing.swift"]]),
        ("second target", "add/app.pbxproj", ["App/Services/Rate.swift"], [["App/Services/Rate.swift", "--target", "AppExtension"]]),
        ("resource and header", "add/app.pbxproj", ["App/Resources/Localizable.xcstrings", "AppKit/Extra.h"],
         [["App/Resources/Localizable.xcstrings", "AppKit/Extra.h"]]),
        ("project-only", "add/app.pbxproj", ["App/App.entitlements"], [["App/App.entitlements"]]),
        ("pathless group", "add/app.pbxproj", ["AppTests/Views/BarTests.swift"], [["AppTests/Views/BarTests.swift"]]),
        ("platform filters", "add/app.pbxproj", ["App/tvOS/TV3.swift", "App/Filtered/New.swift"],
         [["App/tvOS/TV3.swift"], ["App/Filtered/New.swift", "--platform", "ios,tvos"]]),
        ("unknown type with --phase", "add/app.pbxproj", ["App/data.bin"], [["App/data.bin", "--phase", "resources", "--target", "App"]]),
        ("partial membership completed", "add/partial.pbxproj", ["AppTests/Views/FooTests.swift"],
         [["AppTests/Views/FooTests.swift", "--target", "App"]]),
    ]

    func testXcodebuildReadsEveryPostAddProject() throws {
        guard FileManager.default.isExecutableFile(atPath: Self.xcodebuild.path), try Self.developerDirectoryIsSet() else {
            throw XCTSkip("xcodebuild is not available; the oracle lane runs on macOS with Xcode installed")
        }
        for scenario in Self.scenarios {
            let project = try TemporaryProject(fixture: scenario.fixture)
            for file in scenario.files { try project.touch(file) }
            for invocation in scenario.invocations {
                let result = try pbxedit(["add"] + invocation + ["--project", "App.xcodeproj"], in: project.root)
                XCTAssertEqual(result.status, 0, "\(scenario.name): \(invocation): \(result.stderr)\(result.stdout)")
                XCTAssertTrue(result.stdout.hasSuffix("project.pbxproj: modified\n"), "\(scenario.name): \(invocation): \(result.stdout)")
            }
            let listing = try Self.list(project.xcodeproj)
            XCTAssertEqual(listing.status, 0, "\(scenario.name): xcodebuild -list failed:\n\(listing.output)")
            let object = try XCTUnwrap(try? JSONSerialization.jsonObject(with: Data(listing.output.utf8)) as? [String: Any], "\(scenario.name): \(listing.output)")
            let targets = (object["project"] as? [String: Any])?["targets"] as? [String]
            XCTAssertEqual(targets?.isEmpty, false, "\(scenario.name): \(listing.output)")
        }
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
