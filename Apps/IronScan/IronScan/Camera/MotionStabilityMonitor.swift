@preconcurrency import CoreMotion
import Foundation

enum MotionStabilityStatus: Equatable, Sendable {
    case unavailable
    case stable
    case unstable
}

struct MotionStabilityReading: Equatable, Sendable {
    let status: MotionStabilityStatus
    let accelerationVariationG: Double

    static let unavailable = MotionStabilityReading(
        status: .unavailable,
        accelerationVariationG: 0
    )

    var allowsInference: Bool {
        status != .unstable
    }
}

struct MotionStabilityCalculator: Sendable {
    private struct Acceleration: Sendable {
        let x: Double
        let y: Double
        let z: Double
    }

    let thresholdG: Double
    let windowSize: Int
    let minimumSampleCount: Int
    private var samples = [Acceleration]()

    init(
        thresholdG: Double = 0.15,
        windowSize: Int = 12,
        minimumSampleCount: Int = 6
    ) {
        self.thresholdG = max(thresholdG, 0)
        self.windowSize = max(windowSize, 2)
        self.minimumSampleCount = min(max(minimumSampleCount, 2), max(windowSize, 2))
    }

    mutating func add(userAccelerationX: Double, y: Double, z: Double) -> MotionStabilityReading {
        samples.append(Acceleration(x: userAccelerationX, y: y, z: z))
        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }
        guard samples.count >= minimumSampleCount else {
            return MotionStabilityReading(status: .stable, accelerationVariationG: 0)
        }

        let count = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / count
        let meanY = samples.reduce(0) { $0 + $1.y } / count
        let meanZ = samples.reduce(0) { $0 + $1.z } / count
        let meanSquaredDeviation = samples.reduce(0) { partial, sample in
            let deltaX = sample.x - meanX
            let deltaY = sample.y - meanY
            let deltaZ = sample.z - meanZ
            return partial + deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ
        } / count
        let variation = sqrt(max(0, meanSquaredDeviation))
        return MotionStabilityReading(
            status: variation > thresholdG ? .unstable : .stable,
            accelerationVariationG: variation
        )
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}

protocol MotionStabilityMonitoring: Sendable {
    func eventStream() async -> AsyncStream<MotionStabilityReading>
    func start() async
    func stop() async
}

actor MotionStabilityMonitor: MotionStabilityMonitoring {
    private let motionManager: CMMotionManager
    private let updateQueue: OperationQueue
    private var calculator: MotionStabilityCalculator
    private var continuation: AsyncStream<MotionStabilityReading>.Continuation?

    init(
        thresholdG: Double = 0.15,
        updateInterval: TimeInterval = 1 / 30,
        motionManager: CMMotionManager = CMMotionManager()
    ) {
        self.motionManager = motionManager
        motionManager.deviceMotionUpdateInterval = updateInterval
        calculator = MotionStabilityCalculator(thresholdG: thresholdG)
        let queue = OperationQueue()
        queue.name = "org.ironscan.motion-stability"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
        updateQueue = queue
    }

    func eventStream() -> AsyncStream<MotionStabilityReading> {
        let streamPair = AsyncStream<MotionStabilityReading>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation?.finish()
        continuation = streamPair.continuation
        streamPair.continuation.yield(.unavailable)
        return streamPair.stream
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            continuation?.yield(.unavailable)
            return
        }
        guard !motionManager.isDeviceMotionActive else { return }
        calculator.reset()

        // Use an explicit @Sendable handler and capture self weakly to avoid
        // sending an actor-isolated `self` into an escaping callback.
        let handler: @Sendable (CMDeviceMotion?, Error?) -> Void = { [weak self] motion, error in
            guard error == nil, let acceleration = motion?.userAcceleration else {
                Task { [weak self] in
                    await self?.publishUnavailable()
                }
                return
            }

            let x = acceleration.x
            let y = acceleration.y
            let z = acceleration.z

            Task { [weak self] in
                await self?.record(x: x, y: y, z: z)
            }
        }

        motionManager.startDeviceMotionUpdates(to: updateQueue, withHandler: handler)
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        continuation?.finish()
        continuation = nil
    }

    private func record(x: Double, y: Double, z: Double) {
        continuation?.yield(calculator.add(userAccelerationX: x, y: y, z: z))
    }

    private func publishUnavailable() {
        continuation?.yield(.unavailable)
    }
}
