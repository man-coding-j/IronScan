import CoreVideo
import Foundation

enum ImageQualityGatekeeper {
    enum Assessment: Sendable {
        case optimal
        case tooDark
        case tooBlurry
    }

    static func assess(
        _ pixelBuffer: CVPixelBuffer,
        darknessThreshold: Double = 0.28,
        blurThreshold: Double = 42
    ) -> Assessment {
        let averageBrightness = meanLuma(in: pixelBuffer)
        guard averageBrightness >= darknessThreshold else {
            return .tooDark
        }

        let blurVariance = laplacianVariance(in: pixelBuffer)
        guard blurVariance >= blurThreshold else {
            return .tooBlurry
        }

        return .optimal
    }

    private static func meanLuma(in pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        if CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
           let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

            let xStride = max(1, width / 96)
            let yStride = max(1, height / 96)
            var total = 0.0
            var samples = 0

            for y in stride(from: 0, to: height, by: yStride) {
                let row = buffer.advanced(by: y * bytesPerRow)
                for x in stride(from: 0, to: width, by: xStride) {
                    total += Double(row[x]) / 255.0
                    samples += 1
                }
            }

            return samples > 0 ? total / Double(samples) : 0
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 0
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = max(1, bytesPerRow / max(width, 1))
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        let xStride = max(1, width / 96)
        let yStride = max(1, height / 96)
        var total = 0.0
        var samples = 0

        for y in stride(from: 0, to: height, by: yStride) {
            let row = buffer.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: xStride) {
                let offset = x * bytesPerPixel
                let blue = Double(row[offset])
                let green = Double(row[offset + min(1, bytesPerPixel - 1)])
                let red = Double(row[offset + min(2, bytesPerPixel - 1)])
                total += ((0.299 * red) + (0.587 * green) + (0.114 * blue)) / 255.0
                samples += 1
            }
        }

        return samples > 0 ? total / Double(samples) : 0
    }

    private static func laplacianVariance(in pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width: Int
        let height: Int
        let bytesPerRow: Int
        let buffer: UnsafeMutablePointer<UInt8>

        if CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
           let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        } else if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            width = CVPixelBufferGetWidth(pixelBuffer)
            height = CVPixelBufferGetHeight(pixelBuffer)
            bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        } else {
            return 0
        }

        let step = max(1, min(width, height) / 160)
        guard width > step * 2, height > step * 2 else { return 0 }

        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0

        for y in stride(from: step, to: height - step, by: step) {
            for x in stride(from: step, to: width - step, by: step) {
                let center = Double(buffer[y * bytesPerRow + x])
                let left = Double(buffer[y * bytesPerRow + (x - step)])
                let right = Double(buffer[y * bytesPerRow + (x + step)])
                let top = Double(buffer[(y - step) * bytesPerRow + x])
                let bottom = Double(buffer[(y + step) * bytesPerRow + x])
                let laplacian = (4 * center) - left - right - top - bottom

                sum += laplacian
                sumOfSquares += laplacian * laplacian
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let mean = sum / count
        return max(0, (sumOfSquares / count) - (mean * mean))
    }
}
