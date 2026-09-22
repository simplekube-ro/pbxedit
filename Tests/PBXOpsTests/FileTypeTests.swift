import XCTest
@testable import PBXOps

/// Task 3.1: the file-type table (design D6).
final class FileTypeTests: XCTestCase {
    func testSourcesResourcesHeadersAndProjectOnlyFiles() {
        XCTAssertEqual(FileTypes.type(of: "App/Views/Foo.swift"), FileType(kind: .source, lastKnownFileType: "sourcecode.swift"))
        XCTAssertEqual(FileTypes.type(of: "Foo.m"), FileType(kind: .source, lastKnownFileType: "sourcecode.c.objc"))
        XCTAssertEqual(FileTypes.type(of: "App/Resources/Localizable.xcstrings"), FileType(kind: .resource, lastKnownFileType: "text.json.xcstrings"))
        XCTAssertEqual(FileTypes.type(of: "Assets.xcassets"), FileType(kind: .resource, lastKnownFileType: "folder.assetcatalog"))
        XCTAssertEqual(FileTypes.type(of: "AppKit/AppKit.h"), FileType(kind: .header, lastKnownFileType: "sourcecode.c.h"))
        XCTAssertEqual(FileTypes.type(of: "App/App.entitlements"), FileType(kind: .projectOnly, lastKnownFileType: "text.plist.entitlements"))
        XCTAssertEqual(FileTypes.type(of: "Info.plist")?.kind, .projectOnly)
        XCTAssertEqual(FileTypes.type(of: "Debug.xcconfig")?.kind, .projectOnly)
        XCTAssertEqual(FileTypes.type(of: "README.md")?.kind, .projectOnly)
        XCTAssertEqual(FileTypes.type(of: "Foo.SWIFT")?.kind, .source, "extensions are matched case-insensitively")
    }

    func testAnUnknownExtensionHasNoType() {
        XCTAssertNil(FileTypes.type(of: "data.bin"))
        XCTAssertNil(FileTypes.type(of: "Makefile"))
        XCTAssertNil(FileTypes.type(of: "App/.hidden"))
    }

    func testTheKindDecidesThePhase() {
        XCTAssertEqual(PhaseChoice(kind: .source), .sources)
        XCTAssertEqual(PhaseChoice(kind: .resource), .resources)
        XCTAssertEqual(PhaseChoice(kind: .header), .headers)
        XCTAssertEqual(PhaseChoice(kind: .projectOnly), .notBuilt)
        XCTAssertEqual(PhaseChoice.sources.isa, "PBXSourcesBuildPhase")
        XCTAssertEqual(PhaseChoice.resources.isa, "PBXResourcesBuildPhase")
        XCTAssertEqual(PhaseChoice.headers.isa, "PBXHeadersBuildPhase")
        XCTAssertNil(PhaseChoice.notBuilt.isa)
        XCTAssertEqual(PhaseChoice(rawValue: "sources"), .sources)
        XCTAssertEqual(PhaseChoice(rawValue: "none"), .notBuilt, "spelled none on the command line")
        let optional: PhaseChoice? = .notBuilt
        XCTAssertNotNil(optional, "the no-phase case must not read as Optional.none")
    }
}
