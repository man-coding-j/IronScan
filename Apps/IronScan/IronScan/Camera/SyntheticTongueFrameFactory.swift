import CoreGraphics
import CoreVideo
import Foundation

enum SyntheticTongueFrameFactory {
    static func makePixelBuffer(width: Int = 96, height: Int = 96, phase: Int = 0) throws -> CVPixelBuffer {
        guard width > 0, height > 0 else { throw CameraError.configurationFailed("Synthetic frame dimensions must be positive") }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw CameraError.configurationFailed("Synthetic frame allocation failed: \(status)")
        }
        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw CameraError.configurationFailed("Synthetic frame lock failed: \(lockStatus)")
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw CameraError.missingPixelBuffer
        }

        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let horizontalShift = sin(Double(phase) * 0.18) * Double(width) * 0.025
        let centerX = Double(width - 1) / 2 + horizontalShift
        let centerY = Double(height - 1) / 2

        for row in 0..<height {
            for column in 0..<width {
                let normalizedX = (Double(column) - centerX) / (Double(width) * 0.30)
                let normalizedY = (Double(row) - centerY) / (Double(height) * 0.40)
                let isTongue = normalizedX * normalizedX + normalizedY * normalizedY <= 1
                let offset = row * bytesPerRow + column * 4
                bytes[offset] = isTongue ? 112 : 38
                bytes[offset + 1] = isTongue ? 118 : 45
                bytes[offset + 2] = isTongue ? 202 : 58
                bytes[offset + 3] = 255
            }
        }

        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            CVBufferSetAttachment(pixelBuffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        }
        return pixelBuffer
    }
}
