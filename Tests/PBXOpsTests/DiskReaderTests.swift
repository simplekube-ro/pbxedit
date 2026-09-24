import Foundation
import XCTest
@testable import PBXOps

/// Task 1.1 of `move-case-only-rename`: `FileSystemDiskReader` against a real
/// temporary directory (design D2).
final class DiskReaderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pbxedit-disk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Root/App/Views"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Shared"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("Root/App/Views/foo.swift"))
        try Data().write(to: root.appendingPathComponent("Shared/Common.swift"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Whether the volume holding the temporary directory folds case.
    private var caseInsensitive: Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("Root/App/Views/FOO.swift").path)
    }

    func testExistsAsSpelledChecksEveryComponentAgainstItsListing() throws {
        let disk = FileSystemDiskReader(sourceRoot: root.appendingPathComponent("Root"))
        XCTAssertTrue(disk.existsAsSpelled("App/Views/foo.swift"))
        XCTAssertTrue(disk.existsAsSpelled("App/Views"))
        XCTAssertFalse(disk.existsAsSpelled("App/Views/Foo.swift"), "the file's case differs")
        XCTAssertFalse(disk.existsAsSpelled("App/views/foo.swift"), "a directory component's case differs")
        XCTAssertFalse(disk.existsAsSpelled("App/Views/Bar.swift"))
        XCTAssertTrue(disk.existsAsSpelled("../Shared/Common.swift"), "a leading .. is followed")
        XCTAssertFalse(disk.existsAsSpelled("../Shared/common.swift"))
        XCTAssertTrue(disk.existsAsSpelled(root.appendingPathComponent("Shared/Common.swift").path), "an absolute path")
        // `exists` folds case exactly when the volume does; recorded, not assumed.
        XCTAssertEqual(disk.exists("App/Views/Foo.swift"), caseInsensitive)
        XCTAssertEqual(disk.exists("App/views/foo.swift"), caseInsensitive)
    }
}
