import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// merge-command tasks 5.5–5.6: hunks, their counterfactual builds,
/// governed sets, `both` eligibility and keys (design D7).
final class HunkTests: XCTestCase {
    private let a1: ObjectID = "1000000000000000000000A1"

    private func analyse(base: Project? = nil, ours: Project, theirs: Project) throws -> [AnalysedHunk] {
        let base = try base ?? MergeFixture.base()
        let merge = ThreeWay.merge(base: TextLines.split(base.serialize()), ours: TextLines.split(ours.serialize()),
                                   theirs: TextLines.split(theirs.serialize()))
        return try AnalysedHunk.analyse(merge, inputs: AnalysedHunk.Inputs(base: base, ours: ours, theirs: theirs))
    }

    // Spec: Conflicting setting values.
    func testConflictingSettingValues() throws {
        let base = try MergeFixture.base()
        let hunks = try analyse(ours: try MergeFixture.setting("SWIFT_VERSION", "5.10", in: a1, of: base),
                                theirs: try MergeFixture.setting("SWIFT_VERSION", "6.2", in: a1, of: base))
        XCTAssertEqual(hunks.count, 1)
        let hunk = try XCTUnwrap(hunks.first)
        XCTAssertEqual(hunk.governed.map(\.description), ["1000000000000000000000A1 buildSettings.SWIFT_VERSION"])
        let values = try XCTUnwrap(hunk.values.first)
        XCTAssertEqual(values.base, .string("6.0"))
        XCTAssertEqual(values.ours, .string("5.10"))
        XCTAssertEqual(values.theirs, .string("6.2"))
        XCTAssertEqual(hunk.choices, [.ours, .theirs])
        XCTAssertTrue(hunk.key.hasPrefix("h"))
        XCTAssertEqual(hunk.key.count, 13)
    }

    // Spec: Adjacent insertions.
    func testAdjacentInsertionsOfferBoth() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("OTHER_SWIFT_FLAGS", "-DOURS", in: a1, of: base)
        let theirs = try MergeFixture.setting("OTHER_LDFLAGS", "-ObjC", in: a1, of: base)
        let hunks = try analyse(ours: ours, theirs: theirs)
        XCTAssertEqual(hunks.count, 1)
        let hunk = try XCTUnwrap(hunks.first)
        XCTAssertEqual(hunk.choices, [.ours, .theirs, .both])
        XCTAssertEqual(Set(hunk.governed.map(\.description)),
                       ["1000000000000000000000A1 buildSettings.OTHER_SWIFT_FLAGS", "1000000000000000000000A1 buildSettings.OTHER_LDFLAGS"])
        XCTAssertEqual(hunk.resolution(.both), hunk.hunk.ours + hunk.hunk.theirs)
        let both = try Project.load(hunk.counterfactual(.both))
        let leaves = PlistLeaves(both)
        XCTAssertEqual(leaves[["objects", a1.rawValue, "buildSettings", "OTHER_SWIFT_FLAGS"]], .string("-DOURS"))
        XCTAssertEqual(leaves[["objects", a1.rawValue, "buildSettings", "OTHER_LDFLAGS"]], .string("-ObjC"))
    }

    // Spec: Identical hunks in two configurations have two keys.
    func testIdenticalHunksInTwoConfigurationsHaveTwoKeys() throws {
        let base = try MergeFixture.base()
        var ours = base
        var theirs = base
        for configuration: ObjectID in ["1000000000000000000000A2", "1000000000000000000000A3"] {
            ours = try MergeFixture.setting("SWIFT_VERSION", "5.10", in: configuration, of: ours)
            theirs = try MergeFixture.setting("SWIFT_VERSION", "6.2", in: configuration, of: theirs)
        }
        let hunks = try analyse(ours: ours, theirs: theirs)
        XCTAssertEqual(hunks.count, 2)
        XCTAssertEqual(hunks[0].hunk, hunks[1].hunk, "the same three texts")
        XCTAssertNotEqual(hunks[0].key, hunks[1].key)
        XCTAssertEqual(hunks[0].governed.map(\.description), ["1000000000000000000000A2 buildSettings.SWIFT_VERSION"])
        XCTAssertEqual(hunks[1].governed.map(\.description), ["1000000000000000000000A3 buildSettings.SWIFT_VERSION"])
    }

    func testAHunkWhoseTheirsDoesNotParseIsUnsupported() throws {
        let lines = TextLines.split(try MergeFixture.baseBytes())
        let index = try XCTUnwrap(lines.firstIndex { String(decoding: $0, as: UTF8.self).contains("SWIFT_VERSION = 6.0;") })
        let merge = ThreeWay.Merge(regions: [
            .stable(Array(lines[..<index])),
            .hunk(ThreeWay.Hunk(base: [lines[index]], ours: [Array("\t\t\t\tSWIFT_VERSION = 5.10;\n".utf8)],
                                theirs: [Array("\t\t\t\tSWIFT_VERSION = {\n".utf8)])),
            .stable(Array(lines[(index + 1)...])),
        ])
        let plain = try MergeFixture.base()
        let inputs = AnalysedHunk.Inputs(base: plain, ours: plain, theirs: plain)
        XCTAssertThrowsError(try AnalysedHunk.analyse(merge, inputs: inputs)) { error in
            guard case HunkError.unparseable(let hunk, let side, let message) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(hunk, 1)
            XCTAssertEqual(side, .theirs)
            XCTAssertTrue(message.hasPrefix("717:1: expected"), "the parser's line and column: \(message)")
        }
    }

    func testABothThatWouldDuplicateAKeyIsNotOffered() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.setting("OTHER_SWIFT_FLAGS", "-DOURS", in: a1, of: base)
        // Theirs appends a second SDKROOT with the value the first has: no leaf changes.
        let text = String(decoding: base.serialize(), as: UTF8.self)
            .replacingOccurrences(of: "SWIFT_VERSION = 6.0;\n", with: "SWIFT_VERSION = 6.0;\n\t\t\t\tSDKROOT = iphoneos;\n")
        let theirs = try Project.load(Array(text.utf8))
        XCTAssertEqual(PlistValue.duplicateKeyCount(in: theirs.tree.root), 1)
        let hunks = try analyse(ours: ours, theirs: theirs)
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks.first?.choices, [.ours, .theirs])
    }

    // MARK: Issue #13 — insertions into one unordered array

    private let project: ObjectID = "EE0000000000000000000001"
    private let zero = (id: "EF0000000000000000000001", url: "https://example.com/zero")

    /// The hunks governing `leaf`, which must be exactly one.
    private func hunk(governing leaf: LeafPath, in hunks: [AnalysedHunk], file: StaticString = #filePath, line: UInt = #line) throws -> AnalysedHunk {
        let governing = hunks.filter { $0.governed.contains(leaf) }
        XCTAssertEqual(governing.count, 1, "hunks: \(hunks.map(\.governed))", file: file, line: line)
        return try XCTUnwrap(governing.first, file: file, line: line)
    }

    // Spec: Different insertions into one unordered array.
    func testDifferentInsertionsIntoOneUnorderedArrayOfferBoth() throws {
        let base = try MergeFixture.base()
        let hunks = try analyse(ours: try MergeFixture.knownRegions(["de", "en", "Base"], of: base),
                                theirs: try MergeFixture.knownRegions(["fr", "en", "Base"], of: base))
        XCTAssertEqual(hunks.count, 1)
        let hunk = try XCTUnwrap(hunks.first)
        XCTAssertEqual(hunk.governed.map(\.description), ["EE0000000000000000000001 knownRegions"])
        XCTAssertEqual(hunk.choices, [.ours, .theirs, .both])
        let both = PlistLeaves(try Project.load(hunk.counterfactual(.both)))
        XCTAssertEqual(both[["objects", project.rawValue, "knownRegions"]], .array(["de", "fr", "en", "Base"].map { .string($0) }))
    }

    // Spec: Two packages added on both sides.
    func testTwoPackagesAddedOnBothSidesOfferBoth() throws {
        let plain = try MergeFixture.base()
        let hunks = try analyse(base: try MergeFixture.packages([zero], of: plain),
                                ours: try MergeFixture.packages([zero, ("EF0000000000000000000002", "https://example.com/a")], of: plain),
                                theirs: try MergeFixture.packages([zero, ("EF0000000000000000000003", "https://example.com/b")], of: plain))
        let hunk = try hunk(governing: ["objects", project.rawValue, "packageReferences"], in: hunks)
        XCTAssertEqual(hunk.choices, [.ours, .theirs, .both])
        let text = String(decoding: TextLines.join(hunk.resolution(.both)), as: UTF8.self)
        XCTAssertEqual(text, "\t\t\t\tEF0000000000000000000002 /* XCRemoteSwiftPackageReference */,\n"
                           + "\t\t\t\tEF0000000000000000000003 /* XCRemoteSwiftPackageReference */,\n")
    }

    // Spec: The same package under two IDs keeps ours and theirs.
    func testTheSamePackageUnderTwoIDsKeepsOursAndTheirs() throws {
        let plain = try MergeFixture.base()
        let hunks = try analyse(base: try MergeFixture.packages([zero], of: plain),
                                ours: try MergeFixture.packages([zero, ("EF0000000000000000000002", "https://example.com/a")], of: plain),
                                theirs: try MergeFixture.packages([zero, ("EF0000000000000000000003", "https://example.com/a")], of: plain))
        let hunk = try hunk(governing: ["objects", project.rawValue, "packageReferences"], in: hunks)
        XCTAssertEqual(hunk.choices, [.ours, .theirs])
    }

    // Spec: An array whose order matters keeps ours and theirs (LD_RUNPATH_SEARCH_PATHS).
    func testInsertionsIntoARunpathKeepOursAndTheirs() throws {
        let old = "\t\t\t\tSWIFT_VERSION = 6.0;\n"
        func runpath(_ paths: [String], _ project: Project) throws -> Project {
            let list = "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n" + paths.map { "\t\t\t\t\t\"\($0)\",\n" }.joined() + "\t\t\t\t);\n"
            return try MergeFixture.edit(project, replacing: old, with: old + list)
        }
        let plain = try MergeFixture.base()
        let hunks = try analyse(base: try runpath(["$(inherited)"], plain),
                                ours: try runpath(["@executable_path/Frameworks", "$(inherited)"], plain),
                                theirs: try runpath(["@loader_path/Frameworks", "$(inherited)"], plain))
        let hunk = try hunk(governing: ["objects", a1.rawValue, "buildSettings", "LD_RUNPATH_SEARCH_PATHS"], in: hunks)
        XCTAssertEqual(hunk.choices, [.ours, .theirs])
    }

    // MARK: Issue #21 — different links inserted into one Frameworks phase

    /// The `files` of `App`'s Frameworks phase, `CC0000000000000000000002`.
    private let frameworksFiles: LeafPath = ["objects", "CC0000000000000000000002", "files"]

    // Spec: Different links inserted into one Frameworks phase.
    func testInsertionsIntoAFrameworksPhaseOfferBoth() throws {
        let sides = try MergeFixture.frameworkLinks()
        let hunks = try analyse(ours: sides.ours, theirs: sides.theirs)
        XCTAssertEqual(try hunk(governing: frameworksFiles, in: hunks).choices, [.ours, .theirs, .both])
    }

    // Spec: A removal or a reorder in a Frameworks phase keeps ours and theirs.
    func testARemovalOrAReorderInAFrameworksPhaseKeepsOursAndTheirs() throws {
        let foundation = "\t\t\t\tBB0000000000000000000080 /* Foundation.framework in Frameworks */,\n"
        let ourLink = "\t\t\t\tAB0000000000000000000011 /* CoreHaptics.framework in Frameworks */,\n"
        let sides = try MergeFixture.frameworkLinks()
        // Each side replaces base's entry with its own link: base's array is no subsequence of either.
        let ourOnly = try MergeFixture.edit(sides.ours, replacing: foundation, with: "")
        let theirOnly = try MergeFixture.edit(sides.theirs, replacing: foundation, with: "")
        XCTAssertEqual(try hunk(governing: frameworksFiles, in: try analyse(ours: ourOnly, theirs: theirOnly)).choices, [.ours, .theirs])

        // A base that links two frameworks: ours swaps the two, theirs adds a third.
        let two = sides.ours
        let swapped = try MergeFixture.edit(two, replacing: foundation + ourLink, with: ourLink + foundation)
        let third = try MergeFixture.linking("GameController", reference: "AC0000000000000000000010", buildFile: "AC0000000000000000000011",
                                             in: two)
        XCTAssertEqual(try hunk(governing: frameworksFiles, in: try analyse(base: two, ours: swapped, theirs: third)).choices,
                       [.ours, .theirs])
    }

    // Spec: The same framework under two IDs keeps ours and theirs.
    func testTheSameFrameworkUnderTwoIDsKeepsOursAndTheirs() throws {
        let base = try MergeFixture.base()
        let ours = try MergeFixture.linking("GameController", reference: "AB0000000000000000000010", buildFile: "AB0000000000000000000011", in: base)
        let theirs = try MergeFixture.linking("GameController", reference: "AC0000000000000000000010", buildFile: "AC0000000000000000000011", in: base)
        XCTAssertEqual(try hunk(governing: frameworksFiles, in: try analyse(ours: ours, theirs: theirs)).choices, [.ours, .theirs])
    }

    func testARemovalBesideAnInsertionKeepsOursAndTheirs() throws {
        let base = try MergeFixture.base()
        // Each side replaces `en`: base's array is no subsequence of either.
        let hunks = try analyse(ours: try MergeFixture.knownRegions(["de", "Base"], of: base),
                                theirs: try MergeFixture.knownRegions(["fr", "Base"], of: base))
        let hunk = try hunk(governing: ["objects", project.rawValue, "knownRegions"], in: hunks)
        XCTAssertEqual(hunk.choices, [.ours, .theirs])
    }

    func testTheSameElementInsertedOnBothSidesKeepsOursAndTheirs() throws {
        let base = try MergeFixture.base()
        // Both insert `de`, among different neighbours: `both` would list it twice.
        let hunks = try analyse(ours: try MergeFixture.knownRegions(["de", "it", "en", "Base"], of: base),
                                theirs: try MergeFixture.knownRegions(["fr", "de", "en", "Base"], of: base))
        let hunk = try hunk(governing: ["objects", project.rawValue, "knownRegions"], in: hunks)
        XCTAssertEqual(hunk.choices, [.ours, .theirs])
    }

    // MARK: Issue #17 — multi-line objects both sides insert at one place

    private let ourPackage = (id: "EF0000000000000000000002", url: "https://example.com/a")
    private let theirPackage = (id: "EF0000000000000000000003", url: "https://example.com/b")

    /// The trimmed tail the two package objects share, which zealous
    /// trimming moves into the stable region after the hunk.
    private let requirementTail = "\t\t\trequirement = {\n\t\t\t\tkind = upToNextMajorVersion;\n"
        + "\t\t\t\tminimumVersion = 1.0.0;\n\t\t\t};\n\t\t};\n"

    private func packageLines(_ package: (id: String, url: String)) -> String {
        "\t\t\(package.id) /* XCRemoteSwiftPackageReference */ = {\n\t\t\tisa = XCRemoteSwiftPackageReference;\n"
            + "\t\t\trepositoryURL = \"\(package.url)\";\n"
    }

    // Spec: Two packages added on both sides keep their objects.
    func testTwoPackageObjectsAddedAtOnePlaceOfferBoth() throws {
        let plain = try MergeFixture.base()
        let hunks = try analyse(base: try MergeFixture.packages([zero], of: plain),
                                ours: try MergeFixture.packages([zero, ourPackage], of: plain),
                                theirs: try MergeFixture.packages([zero, theirPackage], of: plain))
        let hunk = try hunk(governing: ["objects", ourPackage.id, "repositoryURL"], in: hunks)
        XCTAssertEqual(Set(hunk.governed.map(\.description)),
                       [ourPackage.id, theirPackage.id].reduce(into: Set<String>()) { set, id in
                           for key in ["isa", "repositoryURL", "requirement.kind", "requirement.minimumVersion"] {
                               set.insert("\(id) \(key)")
                           }
                       })
        XCTAssertEqual(hunk.choices, [.ours, .theirs, .both])
        // Design D2: ours' untrimmed text, then theirs' — the shared tail once between them.
        XCTAssertEqual(String(decoding: TextLines.join(hunk.resolution(.both)), as: UTF8.self),
                       packageLines(ourPackage) + requirementTail + packageLines(theirPackage))
        let leaves = PlistLeaves(try Project.load(hunk.counterfactual(.both)))
        XCTAssertEqual(leaves[["objects", ourPackage.id, "repositoryURL"]], .string(ourPackage.url))
        XCTAssertEqual(leaves[["objects", theirPackage.id, "repositoryURL"]], .string(theirPackage.url))
        XCTAssertEqual(leaves[["objects", theirPackage.id, "requirement", "minimumVersion"]], .string("1.0.0"))
    }

    // Spec: A both that the trimmed form fits keeps its lines.
    func testATrimmedBothKeepsItsLines() throws {
        let base = try MergeFixture.base()
        let hunks = try analyse(ours: try MergeFixture.knownRegions(["de", "en", "Base"], of: base),
                                theirs: try MergeFixture.knownRegions(["fr", "en", "Base"], of: base))
        let hunk = try hunk(governing: ["objects", project.rawValue, "knownRegions"], in: hunks)
        XCTAssertEqual(hunk.resolution(.both), hunk.hunk.ours + hunk.hunk.theirs)
        XCTAssertEqual(String(decoding: TextLines.join(hunk.resolution(.both)), as: UTF8.self), "\t\t\t\tde,\n\t\t\t\tfr,\n")
    }

    // Spec: Two objects added under one ID keep ours and theirs.
    func testTwoObjectsAddedUnderOneIDKeepOursAndTheirs() throws {
        let plain = try MergeFixture.base()
        let one = (id: ourPackage.id, url: "https://example.com/a")
        let other = (id: ourPackage.id, url: "https://example.com/b")
        let hunks = try analyse(base: try MergeFixture.packages([zero], of: plain),
                                ours: try MergeFixture.packages([zero, one], of: plain),
                                theirs: try MergeFixture.packages([zero, other], of: plain))
        let hunk = try hunk(governing: ["objects", ourPackage.id, "repositoryURL"], in: hunks)
        XCTAssertEqual(hunk.choices, [.ours, .theirs])
    }
}
