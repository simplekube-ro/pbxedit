import XCTest
import PBXSyntax
import PBXModel
@testable import PBXOps

/// Task 3.3: directory → group, creating the chain when needed (design D5),
/// and the insertion position among a group's children.
final class GroupResolutionTests: XCTestCase {
    private func builder(_ fixture: String = "add/app.pbxproj") throws -> PlanBuilder {
        PlanBuilder(project: try loadProject(fixture), minter: IDMinter(generator: FixedGenerator()))
    }

    // Spec: Pathful groups.
    func testAPathfulChainIsFoundByResolvedPath() throws {
        var builder = try builder()
        let location = try builder.group(forDirectory: "App/Views", path: "App/Views/Bar.swift")
        XCTAssertEqual(location, GroupLocation(group: "AA0000000000000000000003", resolvesToDirectory: true))
        XCTAssertEqual(builder.build().steps, [], "nothing to create")
        XCTAssertEqual(try builder.group(forDirectory: "", path: "README.md"), GroupLocation(group: "AA0000000000000000000001", resolvesToDirectory: true),
                       "the source root is the main group, never a name-only group that also resolves to the root")
        XCTAssertEqual(try builder.group(forDirectory: "AppTests", path: "AppTests/X.swift").group, "AA0000000000000000000005",
                       "the pathful AppTests group wins over the name-only Views group beneath it, which also resolves to AppTests")
    }

    // Spec: Pathless groups.
    func testANameOnlyGroupUnderTheParentDirectoryIsReused() throws {
        var builder = try builder()
        let location = try builder.group(forDirectory: "AppTests/Views", path: "AppTests/Views/BarTests.swift")
        XCTAssertEqual(location, GroupLocation(group: "AA0000000000000000000011", resolvesToDirectory: false))
        XCTAssertEqual(builder.build().steps, [])
        XCTAssertEqual(builder.reference(for: "AppTests/Views/BarTests.swift", in: location),
                       ReferenceSpelling(path: "AppTests/Views/BarTests.swift", name: "BarTests.swift", sourceTree: "SOURCE_ROOT"))
        XCTAssertEqual(builder.reference(for: "App/Views/Bar.swift", in: GroupLocation(group: "AA0000000000000000000003", resolvesToDirectory: true)),
                       ReferenceSpelling(path: "Bar.swift", name: nil, sourceTree: "<group>"))
    }

    // Spec: Groups are created as needed.
    func testMissingGroupsAreCreatedUnderTheDeepestExistingAncestor() throws {
        var builder = try builder()
        let location = try builder.group(forDirectory: "App/Features/New", path: "App/Features/New/Thing.swift")
        let plan = builder.build()
        XCTAssertTrue(location.resolvesToDirectory)
        XCTAssertEqual(plan.steps.count, 4)
        guard case .createGroup(let features, let featuresName, let featuresPath, let featuresTree) = plan.steps[0],
              case .addChild(let child1, let parent1, let position1) = plan.steps[1],
              case .createGroup(let new, let newName, let newPath, let newTree) = plan.steps[2],
              case .addChild(let child2, let parent2, _) = plan.steps[3]
        else { return XCTFail("\(plan.steps)") }
        XCTAssertNil(featuresName)
        XCTAssertEqual(featuresPath, "Features")
        XCTAssertEqual(featuresTree, "<group>")
        XCTAssertEqual(child1, features)
        XCTAssertEqual(parent1, "AA0000000000000000000002", "under App")
        XCTAssertEqual(position1, .last, "App's children are not in name order")
        XCTAssertNil(newName)
        XCTAssertEqual(newPath, "New")
        XCTAssertEqual(newTree, "<group>")
        XCTAssertEqual(child2, new)
        XCTAssertEqual(parent2, features)
        XCTAssertEqual(location.group, new)
        XCTAssertEqual(plan.changes.map(\.action), [.createdGroup, .createdGroup])
        XCTAssertEqual(Set(plan.touched), [features, new, "AA0000000000000000000002"])
        // Asking again yields the planned group, not a second one.
        XCTAssertEqual(try builder.group(forDirectory: "App/Features/New", path: "App/Features/New/Other.swift").group, new)
        XCTAssertEqual(try builder.group(forDirectory: "App/Features", path: "App/Features/X.swift").group, features)
        XCTAssertEqual(builder.build().steps.count, 4)
        // The plan applies and the chain resolves.
        let result = try builder.build().apply(to: builder.project)
        XCTAssertEqual(result.resolvedPath(of: new), .relative("App/Features/New"))
        XCTAssertEqual(result.groups(at: "App/Features").map(\.id), [features])
        assertOperationClean(result, scope: plan.touched)
    }

    // Design D5: a chain created beneath a name-only group is spelled from the source root.
    func testAGroupCreatedUnderANameOnlyGroupIsSpelledFromTheSourceRoot() throws {
        var builder = try builder()
        let location = try builder.group(forDirectory: "AppTests/Views/Sub", path: "AppTests/Views/Sub/X.swift")
        let plan = builder.build()
        guard case .createGroup(let sub, let name, let path, let tree) = plan.steps.first,
              case .addChild(_, let parent, _) = plan.steps.last
        else { return XCTFail("\(plan.steps)") }
        XCTAssertEqual(name, "Sub")
        XCTAssertEqual(path, "AppTests/Views/Sub")
        XCTAssertEqual(tree, "SOURCE_ROOT")
        XCTAssertEqual(parent, "AA0000000000000000000011")
        XCTAssertEqual(location, GroupLocation(group: sub, resolvesToDirectory: true))
        let result = try plan.apply(to: builder.project)
        XCTAssertEqual(result.resolvedPath(of: sub), .relative("AppTests/Views/Sub"))
    }

    // Spec: Group children keep their order.
    func testChildrenAreInsertedInNameOrderOnlyWhenTheGroupIsSorted() throws {
        var builder = try builder()
        XCTAssertEqual(builder.childPosition(in: "AA0000000000000000000013", name: "New.swift"), .before("AA0000000000000000000230"),
                       "Services is sorted: New.swift goes before Rate.swift")
        XCTAssertEqual(builder.childPosition(in: "AA0000000000000000000013", name: "Zed.swift"), .last)
        XCTAssertEqual(builder.childPosition(in: "AA0000000000000000000013", name: "aardvark.swift"), .before("AA0000000000000000000232"),
                       "case-insensitively")
        XCTAssertEqual(builder.childPosition(in: "AA0000000000000000000002", name: "App.entitlements"), .last,
                       "App is not sorted: last")
        XCTAssertEqual(builder.childPosition(in: "AA0000000000000000000003", name: "Bar.swift"), .before("AA0000000000000000000120"),
                       "a single child counts as sorted")
        // Planned children take part: a new group starts empty and stays sorted.
        let location = try builder.group(forDirectory: "App/Features", path: "App/Features/B.swift")
        builder.addChild("0000000000000000000000B1", named: "B.swift", to: location.group)
        XCTAssertEqual(builder.childPosition(in: location.group, name: "A.swift"), .before("0000000000000000000000B1"))
        XCTAssertEqual(builder.childPosition(in: location.group, name: "C.swift"), .last)
    }
}

/// Yields 1, 2, 3, … so minted IDs are deterministic in tests.
struct FixedGenerator: RandomNumberGenerator {
    var counter: UInt64 = 0
    mutating func next() -> UInt64 {
        counter += 1
        return counter
    }
}
