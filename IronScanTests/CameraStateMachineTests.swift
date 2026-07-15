import XCTest
@testable import IronScan

final class CameraStateMachineTests: XCTestCase {
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
}
