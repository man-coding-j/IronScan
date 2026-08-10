import CoreMedia
import Foundation

struct FrameStrideThrottle: Sendable {
    private let minimumIntervalSeconds: Double
    private var lastProcessedTimestampSeconds: Double?

    init(maximumRate: Double) {
        minimumIntervalSeconds = 1 / max(maximumRate, 0.1)
    }

    mutating func shouldProcessNextFrame(timestamp: CMTime) -> Bool {
        let timestampSeconds = timestamp.seconds
        guard timestampSeconds.isFinite else {
            lastProcessedTimestampSeconds = nil
            return true
        }
        guard let lastProcessedTimestampSeconds else {
            self.lastProcessedTimestampSeconds = timestampSeconds
            return true
        }
        guard timestampSeconds - lastProcessedTimestampSeconds >= minimumIntervalSeconds else {
            return false
        }
        self.lastProcessedTimestampSeconds = timestampSeconds
        return true
    }
}
