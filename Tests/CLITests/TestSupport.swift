import Foundation
import XCTest

enum Fixtures {
    static let directory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CLITests
        .deletingLastPathComponent()  // Tests
        .appendingPathComponent("Fixtures")

    static func load(_ relativePath: String) throws -> [UInt8] {
        Array(try Data(contentsOf: directory.appendingPathComponent(relativePath)))
    }
}

/// The `pbxedit` binary SwiftPM built next to this test bundle.
enum Binary {
    static let url: URL = {
        let bundle = Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") } ?? Bundle.main
        return bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("pbxedit")
    }()
}

struct RunResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// Runs the built binary with `arguments` in `directory`.
func pbxedit(_ arguments: [String], in directory: URL? = nil) throws -> RunResult {
    let process = Process()
    process.executableURL = Binary.url
    process.arguments = arguments
    if let directory { process.currentDirectoryURL = directory }
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    let stdout = out.fileHandleForReading.readDataToEndOfFile()
    let stderr = err.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return RunResult(
        status: process.terminationStatus,
        stdout: String(decoding: stdout, as: UTF8.self),
        stderr: String(decoding: stderr, as: UTF8.self))
}

/// A temporary directory holding `<name>.xcodeproj/project.pbxproj` with the
/// given bytes; removed when the value is released.
final class TemporaryProject {
    let root: URL
    let xcodeproj: URL
    var pbxproj: URL { xcodeproj.appendingPathComponent("project.pbxproj") }

    init(_ bytes: [UInt8], name: String = "App") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pbxedit-cli-\(UUID().uuidString)")
        xcodeproj = root.appendingPathComponent("\(name).xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        try Data(bytes).write(to: pbxproj)
    }

    convenience init(fixture: String, name: String = "App") throws {
        try self.init(try Fixtures.load(fixture), name: name)
    }

    /// Adds a second project directory beside the first.
    func addProject(named name: String, _ bytes: [UInt8]) throws -> URL {
        let directory = root.appendingPathComponent("\(name).xcodeproj")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(bytes).write(to: directory.appendingPathComponent("project.pbxproj"))
        return directory
    }

    func bytes() throws -> [UInt8] { Array(try Data(contentsOf: pbxproj)) }

    deinit { try? FileManager.default.removeItem(at: root) }
}
