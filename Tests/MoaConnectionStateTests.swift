#if !MOA_TESTING
import XCTest
@testable import Moa

final class MoaConnectionStateTests: XCTestCase {
    func testEditingInvalidatesAnInFlightTestAndOldCompletionCannotFinishRetry() {
        var state = MoaConnectionTestState()
        let first = state.begin()
        XCTAssertTrue(state.isTesting)

        state.invalidate()
        XCTAssertFalse(state.isTesting)
        let retry = state.begin()
        XCTAssertFalse(state.finish(first))
        XCTAssertTrue(state.isTesting)
        XCTAssertTrue(state.finish(retry))
        XCTAssertFalse(state.isTesting)
        XCTAssertFalse(state.finish(retry))
    }
}
#endif
