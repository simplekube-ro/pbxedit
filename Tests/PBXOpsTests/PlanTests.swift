import Foundation
import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Task 1.1: every `Step` kind applied in memory (design D1), and the
/// guarantee that a failing plan leaves the caller's `Project` untouched.
final class PlanTests: XCTestCase {
    private let views: ObjectID = "AA0000000000000000000003"
    private let appSources: ObjectID = "CC0000000000000000000001"
    private let newRef: ObjectID = "0123456789ABCDEF01234567"
    private let newGroup: ObjectID = "0123456789ABCDEF01234568"
    private let newBuildFile: ObjectID = "0123456789ABCDEF01234569"

    func testEveryCreatingStepYieldsTheExpectedModelState() throws {
        let project = try loadProject("add/app.pbxproj")
        let plan = Plan(steps: [
            .createGroup(id: newGroup, name: nil, path: "Sub", sourceTree: "<group>"),
            .addChild(newGroup, to: views, position: .last),
            .createFileReference(id: newRef, path: "Bar.swift", name: nil, sourceTree: "<group>", lastKnownFileType: "sourcecode.swift"),
            .addChild(newRef, to: newGroup, position: .first),
            .createBuildFile(id: newBuildFile, fileRef: newRef, platformFilters: ["tvos"]),
            .addPhaseEntry(newBuildFile, to: appSources, position: .last),
        ])
        let result = try plan.apply(to: project)
        XCTAssertEqual(result.group(newGroup)?.path, "Sub")
        XCTAssertEqual(result.resolvedPath(of: newGroup), .relative("App/Views/Sub"))
        XCTAssertEqual(result.fileReference(newRef)?.lastKnownFileType, "sourcecode.swift")
        XCTAssertEqual(result.resolvedPath(of: newRef), .relative("App/Views/Sub/Bar.swift"))
        XCTAssertEqual(result.parents(of: newRef).map(\.id), [newGroup])
        XCTAssertEqual(result.buildFile(newBuildFile)?.fileRef, newRef)
        XCTAssertEqual(result.buildFile(newBuildFile)?.platformFilters, ["tvos"])
        XCTAssertEqual(result.membership(of: newRef).targets.map(\.name), ["App"])
        XCTAssertEqual(RuleSet.standard.evaluate(result, scope: [newRef, newGroup, newBuildFile]), [])
        let text = String(decoding: result.serialize(), as: UTF8.self)
        XCTAssertTrue(text.contains("\t\t\(newBuildFile) /* Bar.swift in Sources */ = {isa = PBXBuildFile; fileRef = \(newRef) /* Bar.swift */; platformFilters = (tvos, ); };\n"), text)
        XCTAssertTrue(text.contains("\t\t\(newRef) /* Bar.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Bar.swift; sourceTree = \"<group>\"; };\n"), text)
        XCTAssertTrue(text.contains("\t\t\(newGroup) /* Sub */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t\(newRef) /* Bar.swift */,\n\t\t\t);\n\t\t\tpath = Sub;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n"), text)
        assertPlutilLints(result.serialize())
    }

    func testEveryRemovingAndAttributeStepYieldsTheExpectedModelState() throws {
        let project = try loadProject("add/app.pbxproj")
        let foo: ObjectID = "AA0000000000000000000120"
        let fooBuildFile: ObjectID = "BB0000000000000000000020"
        let plan = Plan(steps: [
            .removePhaseEntry(fooBuildFile, from: appSources),
            .deleteObject(fooBuildFile),
            .removeChild(foo, from: views),
            .setAttribute(key: "name", of: foo, to: .string("Renamed.swift")),
            .refreshAnnotations(foo),
            .setAttribute(key: "lastKnownFileType", of: foo, to: nil),
        ])
        let result = try plan.apply(to: project)
        XCTAssertNil(result.buildFile(fooBuildFile))
        XCTAssertFalse(result.buildPhase(appSources)?.files.contains(fooBuildFile) ?? true)
        XCTAssertEqual(result.parents(of: foo), [])
        XCTAssertEqual(result.fileReference(foo)?.name, "Renamed.swift")
        XCTAssertNil(result.fileReference(foo)?.lastKnownFileType)
        let text = String(decoding: result.serialize(), as: UTF8.self)
        XCTAssertTrue(text.contains("\(foo) /* Renamed.swift */ = {isa = PBXFileReference; name = Renamed.swift; path = Foo.swift;"), text)
        assertPlutilLints(result.serialize())
    }

    // Design D1: a failure discards the copy; the caller's value — its bytes
    // and its indexes — is exactly as before.
    func testAFailingStepLeavesTheOriginalUnchanged() throws {
        let project = try loadProject("add/app.pbxproj")
        let bytes = project.serialize()
        let plan = Plan(steps: [
            .createFileReference(id: newRef, path: "Bar.swift", name: nil, sourceTree: "<group>", lastKnownFileType: "sourcecode.swift"),
            .addChild(newRef, to: views, position: .last),
            .addChild(newRef, to: "NOPE", position: .last),
        ])
        XCTAssertThrowsError(try plan.apply(to: project)) { error in
            guard let failure = error as? PlanExecutionError else { return XCTFail("\(error)") }
            XCTAssertEqual(failure.stepIndex, 2)
        }
        XCTAssertEqual(project.serialize(), bytes)
        XCTAssertFalse(project.contains(newRef))
        XCTAssertEqual(project.fileReferences(at: "App/Views/Bar.swift"), [])
        XCTAssertEqual(project.group(views)?.children, ["AA0000000000000000000120"])
        XCTAssertEqual(project.parents(of: newRef), [])
        // The original's section map must not know the copy's object: a
        // later insertion into the same section would otherwise be placed
        // after an entry that is not there.
        var original = project
        XCTAssertNoThrow(try original.createObject("FFFFFFFFFFFFFFFFFFFFFFFF", isa: "PBXFileReference", attributes: [
            NewEntry("path", .string("Z.swift")), NewEntry("sourceTree", .string("<group>")),
        ]))
        XCTAssertNoThrow(try original.createObject(newRef, isa: "PBXFileReference", attributes: [
            NewEntry("path", .string("Bar.swift")), NewEntry("sourceTree", .string("<group>")),
        ]), "the ID the copy used is free again in the original")
    }

    func testAnEmptyPlanIsANoOp() throws {
        let project = try loadProject("add/app.pbxproj")
        XCTAssertTrue(Plan().isNoOp)
        XCTAssertEqual(try Plan().apply(to: project).serialize(), project.serialize())
    }
}
