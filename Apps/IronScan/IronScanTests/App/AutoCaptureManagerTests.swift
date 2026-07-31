import XCTest
@testable import IronScan

final class AutoCaptureManagerTests: XCTestCase {
    func testStableAlignmentHoldsThenCountsDownAndCapturesOnce() {
        let configuration = AutoCaptureConfiguration(
            alignmentHoldSeconds: 1,
            countdownSeconds: 3
        )
        var stateMachine = AutoCaptureStateMachine(configuration: configuration)

        XCTAssertEqual(
            stateMachine.update(isAligned: true, isStable: true, now: 10).phase,
            .holding(progress: 0)
        )
        XCTAssertEqual(
            stateMachine.update(isAligned: true, isStable: true, now: 11).phase,
            .countdown(secondsRemaining: 3, progress: 0)
        )
        XCTAssertEqual(
            stateMachine.update(isAligned: true, isStable: true, now: 12).phase,
            .countdown(secondsRemaining: 2, progress: 1.0 / 3.0)
        )

        let capture = stateMachine.update(isAligned: true, isStable: true, now: 14)
        XCTAssertEqual(capture.phase, .readyToCapture)
        XCTAssertTrue(capture.shouldCapture)

        let repeated = stateMachine.update(isAligned: true, isStable: true, now: 15)
        XCTAssertEqual(repeated.phase, .readyToCapture)
        XCTAssertFalse(repeated.shouldCapture)
    }

    func testLostAlignmentResetsCountdown() {
        var stateMachine = AutoCaptureStateMachine()
        _ = stateMachine.update(isAligned: true, isStable: true, now: 20)
        _ = stateMachine.update(isAligned: true, isStable: true, now: 21)
        _ = stateMachine.update(isAligned: true, isStable: true, now: 22)

        let reset = stateMachine.update(isAligned: false, isStable: true, now: 22.1)
        XCTAssertEqual(reset.phase, .reset(message: "Hold steady..."))
        XCTAssertFalse(reset.shouldCapture)

        XCTAssertEqual(
            stateMachine.update(isAligned: true, isStable: true, now: 23).phase,
            .holding(progress: 0)
        )
    }

    func testMotionResetsCountdown() {
        var stateMachine = AutoCaptureStateMachine()
        _ = stateMachine.update(isAligned: true, isStable: true, now: 30)
        _ = stateMachine.update(isAligned: true, isStable: true, now: 31)

        let reset = stateMachine.update(isAligned: true, isStable: false, now: 31.5)
        XCTAssertEqual(reset.phase, .reset(message: "Hold steady..."))
        XCTAssertFalse(reset.shouldCapture)
    }

    func testDisabledModeNeverCaptures() {
        var stateMachine = AutoCaptureStateMachine()
        XCTAssertEqual(stateMachine.setEnabled(false).phase, .disabled)

        let event = stateMachine.update(isAligned: true, isStable: true, now: 100)
        XCTAssertEqual(event.phase, .disabled)
        XCTAssertFalse(event.shouldCapture)
    }

    func testConfigurationUsesRequiredMotionThreshold() {
        XCTAssertEqual(AutoCaptureConfiguration().motionThresholdG, 0.12, accuracy: 0.000_001)
    }
}
