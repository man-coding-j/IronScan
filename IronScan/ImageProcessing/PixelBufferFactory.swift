import Accelerate
import CoreGraphics
import CoreVideo
import Foundation

enum PixelBufferFactory {
    static func makeBuffer(
        from source: CVPixelBuffer,
        width: Int,
        height: Int,
        resize: ModelManifest.Resize
    ) throws -> CVPixelBuffer {
        guard width > 0, height > 0 else { throw InferenceError.invalidDimensions }
        guard resize.method == .scaleFill else {
            throw InferenceError.unsupportedResizeMethod(resize.method.rawValue)
        }
        guard resize.interpolation == "vImageHighQuality" else {
            throw InferenceError.unsupportedResizeMethod(resize.interpolation)
        }
        guard CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA else {
            throw InferenceError.unsupportedPixelFormat(fourCharacterCode(CVPixelBufferGetPixelFormatType(source)))
        }

        var destination: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height
        ]
        let creationStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &destination
        )
        guard creationStatus == kCVReturnSuccess, let destination else {
            throw InferenceError.pixelBufferAllocationFailed(creationStatus)
        }

        let sourceLockStatus = CVPixelBufferLockBaseAddress(source, .readOnly)
        guard sourceLockStatus == kCVReturnSuccess else {
            throw InferenceError.pixelBufferLockFailed(sourceLockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }

        let destinationLockStatus = CVPixelBufferLockBaseAddress(destination, [])
        guard destinationLockStatus == kCVReturnSuccess else {
            throw InferenceError.pixelBufferLockFailed(destinationLockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        guard let sourceData = CVPixelBufferGetBaseAddress(source),
              let destinationData = CVPixelBufferGetBaseAddress(destination) else {
            throw InferenceError.invalidDimensions
        }
        var sourceBuffer = vImage_Buffer(
            data: sourceData,
            height: vImagePixelCount(CVPixelBufferGetHeight(source)),
            width: vImagePixelCount(CVPixelBufferGetWidth(source)),
            rowBytes: CVPixelBufferGetBytesPerRow(source)
        )
        var destinationBuffer = vImage_Buffer(
            data: destinationData,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(destination)
        )
        let resizeStatus = vImageScale_ARGB8888(
            &sourceBuffer,
            &destinationBuffer,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )
        guard resizeStatus == kvImageNoError else {
            throw InferenceError.resizeFailed(resizeStatus)
        }
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            CVBufferSetAttachment(destination, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        }
        return destination
    }

    private static func fourCharacterCode(_ code: OSType) -> String {
        let scalars = [24, 16, 8, 0].compactMap { shift in
            UnicodeScalar(UInt8((code >> OSType(shift)) & 0xff))
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
