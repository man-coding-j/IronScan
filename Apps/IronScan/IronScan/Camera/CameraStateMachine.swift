import Foundation

struct CameraStateMachine: Sendable {
    enum Event: Equatable, Sendable {
        case requestPermission
        case permissionGranted
        case configured
        case stabilized
        case alignmentConfirmed
        case cameraChanged
        case captureRequested
        case captureCompleted
        case captureAborted
        case resetAfterCapture
        case interruptionBegan
        case interruptionEnded
        case stopped
        case failed(CameraError)
    }

    private(set) var state: CameraState = .idle
    private(set) var torchShouldBeOn = false

    mutating func handle(_ event: Event) {
        switch event {
        case .requestPermission where state == .idle:
            state = .requestingPermission
        case .permissionGranted where state == .requestingPermission:
            state = .configuring
        case .configured where state == .configuring:
            state = .stabilizing
            torchShouldBeOn = true
        case .stabilized where state == .stabilizing:
            state = .ready
        case .alignmentConfirmed where state == .ready:
            state = .stabilizing
        case .cameraChanged where state != .idle && state != .capturing:
            state = .stabilizing
            torchShouldBeOn = false
        case .captureRequested where state == .ready:
            state = .capturing
        case .captureCompleted where state == .capturing:
            state = .completed
            torchShouldBeOn = false
        case .captureAborted where state == .capturing:
            state = .stabilizing
            torchShouldBeOn = true
        case .resetAfterCapture where state == .completed:
            state = .stabilizing
            torchShouldBeOn = true
        case .interruptionBegan where state != .idle && state != .completed && !isFailed:
            state = .interrupted
            torchShouldBeOn = false
        case .interruptionEnded where state == .interrupted:
            state = .idle
        case .stopped:
            state = .idle
            torchShouldBeOn = false
        case let .failed(error):
            state = .failed(error)
            torchShouldBeOn = false
        default:
            break
        }
    }

    private var isFailed: Bool {
        if case .failed = state {
            return true
        }
        return false
    }
}
