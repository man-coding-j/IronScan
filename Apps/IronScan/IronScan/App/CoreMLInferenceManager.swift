import CoreImage
import CoreVideo
import Foundation
import ImageIO

struct PreparedCoreMLCapture: Sendable {
    let frame: CapturedFrame
    let previewImage: CGImage?
}

enum CoreMLInferenceManagerError: LocalizedError {
    case invalidFrame
    case renderFailed
    case pixelBufferAllocationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidFrame:
            "The captured frame was empty."
        case .renderFailed:
            "The image could not be normalized for analysis."
        case let .pixelBufferAllocationFailed(status):
            "The image buffer could not be allocated (\(status))."
        }
    }
}

struct CoreMLInferenceManager: Sendable {
    func prepareCapturedFrame(
        _ frame: CapturedFrame,
        tissue: TissueSite,
        lensPosition: CameraLensPosition,
        captureOrientation: CaptureOrientation
    ) throws -> PreparedCoreMLCapture {
        guard CVPixelBufferGetWidth(frame.pixelBuffer) > 0,
              CVPixelBufferGetHeight(frame.pixelBuffer) > 0 else {
            throw CoreMLInferenceManagerError.invalidFrame
        }

        guard tissue == .tongue, lensPosition == .front else {
            let image = try makePreviewImage(from: CIImage(cvPixelBuffer: frame.pixelBuffer))
            return PreparedCoreMLCapture(frame: frame, previewImage: image)
        }

        let orientation = normalizedOrientation(for: captureOrientation, lensPosition: lensPosition)
        let orientedImage = CIImage(cvPixelBuffer: frame.pixelBuffer).oriented(orientation)
        let normalizedBuffer = try renderPixelBuffer(from: orientedImage)
        let normalizedImage = try makePreviewImage(from: orientedImage)

        return PreparedCoreMLCapture(
            frame: CapturedFrame(
                pixelBuffer: normalizedBuffer,
                metadata: normalizedMetadata(
                    from: frame.metadata,
                    width: CVPixelBufferGetWidth(normalizedBuffer),
                    height: CVPixelBufferGetHeight(normalizedBuffer)
                ),
                quality: frame.quality
            ),
            previewImage: normalizedImage
        )
    }

    private func normalizedOrientation(
        for captureOrientation: CaptureOrientation,
        lensPosition: CameraLensPosition
    ) -> CGImagePropertyOrientation {
        switch (lensPosition, captureOrientation) {
        case (.front, .portrait):
            .leftMirrored
        case (.front, .portraitUpsideDown):
            .rightMirrored
        case (.front, .landscapeLeft):
            .downMirrored
        case (.front, .landscapeRight):
            .upMirrored
        case (.back, .portrait):
            .right
        case (.back, .portraitUpsideDown):
            .left
        case (.back, .landscapeLeft):
            .up
        case (.back, .landscapeRight):
            .down
        }
    }

    private func renderPixelBuffer(from image: CIImage) throws -> CVPixelBuffer {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else {
            throw CoreMLInferenceManagerError.renderFailed
        }

        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(extent.width),
            Int(extent.height),
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw CoreMLInferenceManagerError.pixelBufferAllocationFailed(status)
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        context.render(image, to: pixelBuffer)
        return pixelBuffer
    }

    private func makePreviewImage(from image: CIImage) throws -> CGImage {
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let previewImage = context.createCGImage(image, from: image.extent.integral) else {
            throw CoreMLInferenceManagerError.renderFailed
        }
        return previewImage
    }

    private func normalizedMetadata(
        from metadata: CaptureMetadata,
        width: Int,
        height: Int
    ) -> CaptureMetadata {
        CaptureMetadata(
            captureTimestamp: metadata.captureTimestamp,
            deviceModelIdentifier: metadata.deviceModelIdentifier,
            cameraDeviceType: metadata.cameraDeviceType,
            activeFormatWidth: metadata.activeFormatWidth,
            activeFormatHeight: metadata.activeFormatHeight,
            pixelFormat: metadata.pixelFormat,
            exposureDurationSeconds: metadata.exposureDurationSeconds,
            iso: metadata.iso,
            lensPosition: metadata.lensPosition,
            whiteBalanceGains: metadata.whiteBalanceGains,
            exposureTargetOffset: metadata.exposureTargetOffset,
            torchLevel: metadata.torchLevel,
            focusMode: metadata.focusMode,
            exposureMode: metadata.exposureMode,
            whiteBalanceMode: metadata.whiteBalanceMode,
            orientation: "up",
            focusWasLocked: metadata.focusWasLocked,
            exposureWasLocked: metadata.exposureWasLocked,
            whiteBalanceWasLocked: metadata.whiteBalanceWasLocked,
            sourceColorSpace: metadata.sourceColorSpace,
            photoWidth: width,
            photoHeight: height
        )
    }
}
