import Foundation

struct FrameStrideThrottle: Sendable {
    private(set) var frameCount: UInt64 = 0
    let stride: UInt64

    init(stride: Int) {
        self.stride = UInt64(max(1, stride))
    }

    mutating func shouldProcessNextFrame() -> Bool {
        frameCount &+= 1
        return frameCount.isMultiple(of: stride)
    }
}
