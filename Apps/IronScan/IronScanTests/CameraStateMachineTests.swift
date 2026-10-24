import XCTest
@testable import IronScan

final class CameraStateMachineTests: XCTestCase {
    func testLensChangeCanRecoverFromStabilizationFailure() {
        var machine = CameraStateMachine()
        machine.handle(.failed(.stabilizationTimedOut))
        machine.handle(.cameraChanged)
        XCTAssertEqual(machine.state, .stabilizing)
        machine.handle(.stabilized)
        XCTAssertEqual(machine.state, .ready)
    }

    func testSuccessfulCaptureLifecycle() {
        var stateMachine = CameraStateMachine()

        stateMachine.handle(.requestPermission)
        XCTAssertEqual(stateMachine.state, .requestingPermission)
        stateMachine.handle(.permissionGranted)
        XCTAssertEqual(stateMachine.state, .configuring)
        stateMachine.handle(.configured)
        XCTAssertEqual(stateMachine.state, .stabilizing)
        XCTAssertTrue(stateMachine.torchShouldBeOn)
        stateMachine.handle(.stabilized)
        XCTAssertEqual(stateMachine.state, .ready)
        stateMachine.handle(.captureRequested)
        XCTAssertEqual(stateMachine.state, .capturing)
        stateMachine.handle(.captureCompleted)
        XCTAssertEqual(stateMachine.state, .completed)
        XCTAssertFalse(stateMachine.torchShouldBeOn)
        stateMachine.handle(.resetAfterCapture)
        XCTAssertEqual(stateMachine.state, .stabilizing)
        XCTAssertTrue(stateMachine.torchShouldBeOn)
        stateMachine.handle(.stabilized)
        XCTAssertEqual(stateMachine.state, .ready)
    }

    func testInterruptionReturnsToIdleForRestart() {
        var stateMachine = CameraStateMachine()
        stateMachine.handle(.requestPermission)
        stateMachine.handle(.permissionGranted)
        stateMachine.handle(.configured)
        stateMachine.handle(.interruptionBegan)

        XCTAssertEqual(stateMachine.state, .interrupted)
        XCTAssertFalse(stateMachine.torchShouldBeOn)

        stateMachine.handle(.interruptionEnded)

        XCTAssertEqual(stateMachine.state, .idle)
    }

    func testInvalidTransitionDoesNotChangeState() {
        var stateMachine = CameraStateMachine()

        stateMachine.handle(.captureRequested)
        stateMachine.handle(.interruptionBegan)

        XCTAssertEqual(stateMachine.state, .idle)
    }

    func testFailureDisablesTorch() {
        var stateMachine = CameraStateMachine()
        stateMachine.handle(.requestPermission)
        stateMachine.handle(.permissionGranted)
        stateMachine.handle(.configured)

        stateMachine.handle(.failed(.stabilizationTimedOut))

        XCTAssertEqual(stateMachine.state, .failed(.stabilizationTimedOut))
        XCTAssertFalse(stateMachine.torchShouldBeOn)
    }

    func testConfirmedAlignmentRestabilizesCamera() {
        var stateMachine = CameraStateMachine()
        stateMachine.handle(.requestPermission)
        stateMachine.handle(.permissionGranted)
        stateMachine.handle(.configured)
        stateMachine.handle(.stabilized)

        stateMachine.handle(.alignmentConfirmed)
        XCTAssertEqual(stateMachine.state, .stabilizing)

        stateMachine.handle(.stabilized)
        XCTAssertEqual(stateMachine.state, .ready)
    }

    func testCaptureIssueRestabilizesInsteadOfPermanentlyFailing() {
        var stateMachine = CameraStateMachine()
        stateMachine.handle(.requestPermission)
        stateMachine.handle(.permissionGranted)
        stateMachine.handle(.configured)
        stateMachine.handle(.stabilized)
        stateMachine.handle(.captureRequested)

        stateMachine.handle(.captureAborted)

        XCTAssertEqual(stateMachine.state, .stabilizing)
        XCTAssertTrue(stateMachine.torchShouldBeOn)
        stateMachine.handle(.stabilized)
        XCTAssertEqual(stateMachine.state, .ready)
    }
}
