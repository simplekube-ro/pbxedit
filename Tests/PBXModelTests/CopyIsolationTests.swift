import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// Found by `add-command` task 1.1: a `Project` is a value, so a mutation on
/// a copy must not change what the original answers — including through the
/// index cache the two once shared.
final class CopyIsolationTests: XCTestCase {
    func testMutatingACopyLeavesTheOriginalsIndexesHonest() throws {
        let original = try loadProject("model/app.pbxproj")
        _ = original.fileReferences(at: "App/Views/Foo.swift")  // warm every index
        _ = original.membership(of: "AA0000000000000000000120")
        var copy = original
        try copy.createObject("AA0000000000000000000125", isa: "PBXFileReference", attributes: [
            NewEntry("path", .string("New.swift")), NewEntry("sourceTree", .string("<group>")),
        ])
        try copy.addChild("AA0000000000000000000125", to: "AA0000000000000000000003")
        try copy.createObject("BB0000000000000000000025", isa: "PBXBuildFile", attributes: [
            NewEntry("fileRef", copy.reference(to: "AA0000000000000000000125")),
        ])
        try copy.addPhaseEntry("BB0000000000000000000025", to: "CC0000000000000000000001")

        XCTAssertFalse(original.contains("AA0000000000000000000125"))
        XCTAssertEqual(original.fileReferences(at: "App/Views/New.swift"), [])
        XCTAssertEqual(original.parents(of: "AA0000000000000000000125"), [])
        XCTAssertEqual(original.buildFiles(for: "AA0000000000000000000125"), [])
        XCTAssertEqual(original.group("AA0000000000000000000003")?.children, ["AA0000000000000000000120"])
        // The section map: a new object after the copy's ID must still be placeable.
        var later = original
        XCTAssertNoThrow(try later.createObject("AA0000000000000000000126", isa: "PBXFileReference", attributes: [
            NewEntry("path", .string("Later.swift")), NewEntry("sourceTree", .string("<group>")),
        ]))
        XCTAssertEqual(later.objects.filter { $0.isa == "PBXFileReference" }.count, original.fileReferences.count + 1)
        XCTAssertEqual(copy.fileReferences(at: "App/Views/New.swift").map(\.id), ["AA0000000000000000000125"])
    }
}
