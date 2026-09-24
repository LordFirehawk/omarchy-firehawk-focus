import XCTest
@testable import FirehawkFocus

final class StatusItemContentTests: XCTestCase {
    func testTitleAndSymbolFollowStatusAndPhase() {
        XCTAssertEqual(StatusItemContent(phase: .focus, status: .ready, clockText: "25:00").title, "")
        XCTAssertEqual(StatusItemContent(phase: .focus, status: .running, clockText: "24:59").title, "24:59")
        XCTAssertEqual(StatusItemContent(phase: .focus, status: .paused, clockText: "12:00").title, "12:00 ⏸")
        XCTAssertEqual(StatusItemContent(phase: .longBreak, status: .complete, clockText: "0:00").title, "Done")

        XCTAssertEqual(StatusItemContent(phase: .focus, status: .running, clockText: "1:00").symbolName, "flame.fill")
        XCTAssertEqual(StatusItemContent(phase: .shortBreak, status: .running, clockText: "1:00").symbolName, "cup.and.saucer.fill")
        XCTAssertEqual(StatusItemContent(phase: .longBreak, status: .running, clockText: "1:00").symbolName, "sparkles")
    }

    // Engine ticks republish unchanged values; the status item must only update when the clock text changes.
    func testRepeatedTicksProduceEqualContent() {
        let tick = StatusItemContent(phase: .focus, status: .running, clockText: "24:59")
        XCTAssertEqual(tick, StatusItemContent(phase: .focus, status: .running, clockText: "24:59"))
        XCTAssertNotEqual(tick, StatusItemContent(phase: .focus, status: .running, clockText: "24:58"))

        // While idle the clock is not shown, so clock changes must not trigger updates
        XCTAssertEqual(
            StatusItemContent(phase: .focus, status: .ready, clockText: "25:00"),
            StatusItemContent(phase: .focus, status: .ready, clockText: "30:00")
        )
    }
}
