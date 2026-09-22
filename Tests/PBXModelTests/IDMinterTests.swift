import Foundation
import XCTest
import PBXSyntax
@testable import PBXModel

/// A generator that plays a script, then counts up so that it never repeats.
struct ScriptedGenerator: RandomNumberGenerator {
    var script: [UInt64]
    var fallback: UInt64 = 0x1000_0000_0000_0000

    mutating func next() -> UInt64 {
        if !script.isEmpty { return script.removeFirst() }
        fallback += 1
        return fallback
    }
}

/// Task 5.5: minted IDs (design D7).
final class IDMinterTests: XCTestCase {
    // Spec: Minted IDs are well-formed and unique — Collision.
    func testACollidingIDIsDiscardedAndAFreshOneReturned() throws {
        let project = try loadProject("model/app.pbxproj")
        XCTAssertTrue(project.contains("BB0000000000000000000010"))
        var minter = IDMinter(generator: ScriptedGenerator(script: [
            0xBB00_0000_0000_0000, 0x0000_0000_0000_0010,  // BB0000000000000000000010: taken
            0xCAFE_0000_0000_0000, 0x0000_0000_0000_BEEF,  // fresh
            0xCAFE_0000_0000_0000, 0x0000_0000_0000_BEEF,  // minted a moment ago: taken
            0x0123_4567_89AB_CDEF, 0xFFFF_FFFF_0000_0001,  // fresh; only the low four bytes are used
        ]))
        XCTAssertEqual(minter.mint(for: project), "CAFE0000000000000000BEEF")
        XCTAssertEqual(minter.mint(for: project), "0123456789ABCDEF00000001")
    }

    func testMintedIDsAreTwentyFourUppercaseHexCharactersAndUnique() throws {
        let project = try loadProject("model/app.pbxproj")
        var minter = IDMinter()
        var seen: Set<ObjectID> = []
        for _ in 0..<1_000 {
            let id = minter.mint(for: project)
            XCTAssertEqual(id.rawValue.utf8.count, 24)
            XCTAssertTrue(id.rawValue.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x46) }, id.rawValue)
            XCTAssertFalse(project.contains(id))
            XCTAssertTrue(seen.insert(id).inserted, "\(id) minted twice")
        }
    }

    func testASeededGeneratorMakesMintingDeterministic() throws {
        let project = try loadProject("model/broken.pbxproj")
        var first = IDMinter(generator: ScriptedGenerator(script: []))
        var second = IDMinter(generator: ScriptedGenerator(script: []))
        XCTAssertEqual(first.mint(for: project), second.mint(for: project))
        XCTAssertEqual(second.mintedIDs, ["100000000000000100000002"])
        XCTAssertEqual(first.mint(for: project), "100000000000000300000004")
    }
}
