import Accelerate
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

enum PixelBufferFactory {
    static func makeCrop(from source: CVPixelBuffer, normalizedRect: CGRect) throws -> CVPixelBuffer {
        guard normalizedRect.minX >= 0,
              normalizedRect.minY >= 0,
              normalizedRect.maxX <= 1,
              normalizedRect.maxY <= 1,
              normalizedRect.width > 0,
              normalizedRect.height > 0 else {
            throw InferenceError.invalidDimensions
        }
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw InferenceError.invalidDimensions
        }
        let pixelRect = CGRect(
            x: normalizedRect.minX * CGFloat(sourceWidth),
            y: normalizedRect.minY * CGFloat(sourceHeight),
            width: normalizedRect.width * CGFloat(sourceWidth),
            height: normalizedRect.height * CGFloat(sourceHeight)
        ).integral.intersection(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        guard pixelRect.width >= 4, pixelRect.height >= 4 else {
            throw InferenceError.invalidDimensions
        }

        var destination: CVPixelBuffer?
        let creationStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(pixelRect.width),
            Int(pixelRect.height),
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: Int(pixelRect.width),
                kCVPixelBufferHeightKey: Int(pixelRect.height),
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ] as CFDictionary,
            &destination
        )
        guard creationStatus == kCVReturnSuccess, let destination else {
            throw InferenceError.pixelBufferAllocationFailed(creationStatus)
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw InferenceError.unsupportedPixelFormat("sRGB")
        }
        let image = CIImage(cvPixelBuffer: source)
            .cropped(to: pixelRect)
            .transformed(by: CGAffineTransform(
                translationX: -pixelRect.minX,
                y: -pixelRect.minY
            ))
        CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace
        ]).render(
            image,
            to: destination,
            bounds: CGRect(origin: .zero, size: pixelRect.size),
            colorSpace: colorSpace
        )
        CVBufferSetAttachment(destination, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        return destination
    }

    static func makeBGRA(from source: CVPixelBuffer) throws -> CVPixelBuffer {
        if CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA {
            return source
        }

        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width > 0, height > 0 else { throw InferenceError.invalidDimensions }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var destination: CVPixelBuffer?
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
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw InferenceError.unsupportedPixelFormat("sRGB")
        }
        let context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace
        ])
        context.render(
            CIImage(cvPixelBuffer: source),
            to: destination,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: colorSpace
        )
        CVBufferSetAttachment(destination, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        return destination
    }

    static func makeBuffer(
        from source: CVPixelBuffer,
        width: Int,
        height: Int,
        resize: ModelManifest.Resize
    ) throws -> CVPixelBuffer {
        guard width > 0, height > 0 else { throw InferenceError.invalidDimensions }
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
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        let sourceRowBytes = CVPixelBufferGetBytesPerRow(source)
        let crop = cropRectangle(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: width,
            targetHeight: height,
            method: resize.method
        )
        let croppedData = sourceData.advanced(by: crop.originY * sourceRowBytes + crop.originX * 4)
        var sourceBuffer = vImage_Buffer(
            data: croppedData,
            height: vImagePixelCount(crop.height),
            width: vImagePixelCount(crop.width),
            rowBytes: sourceRowBytes
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

    private static func cropRectangle(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        method: ModelManifest.Resize.Method
    ) -> (originX: Int, originY: Int, width: Int, height: Int) {
        guard method == .centerCrop else {
            return (0, 0, sourceWidth, sourceHeight)
        }
        let sourceAspect = Double(sourceWidth) / Double(sourceHeight)
        let targetAspect = Double(targetWidth) / Double(targetHeight)
        if sourceAspect > targetAspect {
            let cropWidth = max(1, Int((Double(sourceHeight) * targetAspect).rounded(.down)))
            return ((sourceWidth - cropWidth) / 2, 0, cropWidth, sourceHeight)
        }
        let cropHeight = max(1, Int((Double(sourceWidth) / targetAspect).rounded(.down)))
        return (0, (sourceHeight - cropHeight) / 2, sourceWidth, cropHeight)
    }

    private static func fourCharacterCode(_ code: OSType) -> String {
        let scalars = [24, 16, 8, 0].compactMap { shift in
            UnicodeScalar(UInt8((code >> OSType(shift)) & 0xff))
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
