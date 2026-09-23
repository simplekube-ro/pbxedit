import XCTest
import PBXModel
import PBXOps
@testable import pbxedit

/// Review finding: when the re-check failed and restoring the previous
/// bytes failed too, the error was only the restore's fragment.
final class MergeRendererTests: XCTestCase {
    private let failure = CheckResult(check: .A, problems: [CheckProblem(object: nil, subject: "the written file", message: "differs")])

    private func report() -> MergeReport {
        MergeEngine().run(base: Array("// !$*UTF8*$!\n{}\n".utf8), ours: [], theirs: [])
    }

    func testAFailedRecheckWhoseRestoreFailedNamesBoth() {
        let error = MergeRenderer.error(report(), writeFailure: failure, writeError: "and the previous file could not be restored: denied")
        XCTAssertEqual(error, "the file read back failed check A and the previous file could not be restored: denied")
    }

    func testAFailedRecheckThatWasRestored() {
        XCTAssertEqual(MergeRenderer.error(report(), writeFailure: failure, writeError: nil),
                       "the file read back failed check A; the previous bytes were restored")
    }

    func testAWriteErrorAlone() {
        XCTAssertEqual(MergeRenderer.error(report(), writeFailure: nil, writeError: "cannot write x: denied"), "cannot write x: denied")
    }
}
