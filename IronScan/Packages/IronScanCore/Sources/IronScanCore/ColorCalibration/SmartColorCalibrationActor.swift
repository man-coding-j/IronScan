import Accelerate
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import simd

actor SmartColorCalibrationActor {
    private let context: CIContext

    init(context: CIContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])) {
        self.context = context
    }

    func calibrate(
        capture: CVPixelBuffer,
        metadata: CalibrationCaptureMetadata,
        segmentation: SegmentationResult,
        configuration: ColorCalibrationConfiguration
    ) throws -> CalibratedTongueSample {
        let start = ContinuousClock.now
        try Task.checkCancellation()
        let linearImage = try makeLinearImage(from: capture, orientation: metadata.orientation)
        let width = linearImage.width
        let height = linearImage.height
        let tongueMask = try resizeMask(
            segmentation.binaryMask,
            sourceWidth: segmentation.width,
            sourceHeight: segmentation.height,
            destinationWidth: width,
            destinationHeight: height
        )
        var rejectionReasons = validateMetadata(metadata)
        rejectionReasons.append(contentsOf: validateMask(
            tongueMask,
            width: width,
            height: height,
            configuration: configuration
        ))

        var observed = [SIMD3<Double>]()
        var targets = [SIMD3<Double>]()
        var weights = [Double]()
        var clippedPatchDetected = false
        for patch in configuration.patches {
            let statistics = robustPatchStatistic(
                patch,
                pixels: linearImage.pixels,
                width: width,
                height: height,
                configuration: configuration
            )
            clippedPatchDetected = clippedPatchDetected || statistics.clipped
            if let median = statistics.median {
                observed.append(median)
                targets.append(patch.targetLinearRGB)
                weights.append(patch.weight)
            }
        }
        if clippedPatchDetected {
            rejectionReasons.append(.clippedReferencePatch)
        }

        let selected = try selectCalibration(
            observed: observed,
            targets: targets,
            weights: weights,
            pixels: linearImage.pixels,
            width: width,
            height: height,
            configuration: configuration
        )
        if selected.usablePatchCount < configuration.minimumUsablePatchCount,
           selected.mode != .teethPseudoReference,
           selected.mode != .neutralPatchReference {
            rejectionReasons.append(.insufficientReferencePatches)
        }
        if selected.solution.conditionNumber > configuration.maximumConditionNumber {
            rejectionReasons.append(.unstableMatrix)
        }

        let residuals = zip(observed, targets).map {
            CalibrationMath.deltaE(selected.solution.applying(to: $0.0), $0.1)
        }.sorted()
        let usesPseudoReference = selected.mode == .neutralPatchReference || selected.mode == .teethPseudoReference
        let medianResidual = median(residuals) ?? (usesPseudoReference ? 0 : .infinity)
        let maximumResidual = residuals.last ?? (usesPseudoReference ? 0 : .infinity)
        if medianResidual > configuration.maximumMedianDeltaE {
            rejectionReasons.append(.excessiveMedianResidual)
        }
        if maximumResidual > configuration.maximumDeltaE {
            rejectionReasons.append(.excessiveMaximumResidual)
        }

        let tongueLuminances = maskedLuminances(
            pixels: linearImage.pixels,
            mask: tongueMask,
            width: width,
            height: height,
            solution: selected.solution
        )
        let exposureScale = boundedExposureScale(luminances: tongueLuminances, configuration: configuration)
        let shadowUniformity = relativeSpread(tongueLuminances)
        if shadowUniformity > configuration.maximumShadowUniformity {
            rejectionReasons.append(.excessiveShadowGradient)
        }

        var specularMask = [UInt8](repeating: 0, count: width * height)
        var correctedPixels = [SIMD3<Double>](repeating: .zero, count: width * height)
        var specularCount = 0
        var tongueCount = 0
        for row in 0..<height {
            for column in 0..<width {
                let index = row * width + column
                let corrected = simd_clamp(
                    selected.solution.applying(to: linearImage.pixels[index]) * exposureScale,
                    SIMD3(repeating: 0),
                    SIMD3(repeating: 1)
                )
                correctedPixels[index] = corrected
                guard tongueMask[index] != 0 else { continue }
                tongueCount += 1
                let maximum = max(corrected.x, max(corrected.y, corrected.z))
                let minimum = min(corrected.x, min(corrected.y, corrected.z))
                if maximum >= configuration.specularValueThreshold,
                   maximum - minimum <= configuration.specularChromaThreshold {
                    specularMask[index] = 1
                    specularCount += 1
                }
            }
        }
        let specularFraction = tongueCount == 0 ? 1 : Double(specularCount) / Double(tongueCount)
        if specularFraction > configuration.maximumSpecularFraction {
            rejectionReasons.append(.excessiveSpecularFraction)
        }

        var centralMask = erode(
            tongueMask,
            width: width,
            height: height,
            iterations: configuration.centralROIErosionIterations
        )
        for index in centralMask.indices where specularMask[index] != 0 {
            centralMask[index] = 0
        }
        let diagnostics = diagnosticFeatures(pixels: correctedPixels, mask: centralMask)
        let outputBuffer = try makeEncodedSRGBBuffer(pixels: correctedPixels, width: width, height: height)
        let uniqueRejections = Array(Set(rejectionReasons)).sorted { $0.rawValue < $1.rawValue }
        let accepted = uniqueRejections.isEmpty
        let calibrationConfidence = accepted ? confidence(for: selected.mode) : 0
        let areaRatio = Double(tongueCount) / Double(max(1, width * height))
        let qualitySummary = InferenceQualitySummary(
            segmentationAreaRatio: areaRatio,
            segmentationMeanConfidence: segmentation.confidenceStatistics.meanForegroundProbability,
            calibrationResidual: medianResidual.isFinite ? medianResidual : 0,
            captureQualityScore: calibrationConfidence * max(0, 1 - specularFraction - min(1, shadowUniformity))
        )
        return CalibratedTongueSample(
            calibratedPixelBuffer: outputBuffer,
            tongueMask: tongueMask,
            centralROIMask: centralMask,
            maskWidth: width,
            maskHeight: height,
            calibrationMode: accepted ? selected.mode : .uncalibratedRejected,
            calibrationMatrix: selected.solution.rowMajorValues,
            exposureScale: exposureScale,
            usablePatchCount: selected.usablePatchCount,
            medianReferenceDeltaE: medianResidual,
            maximumReferenceDeltaE: maximumResidual,
            matrixConditionNumber: selected.solution.conditionNumber,
            specularFraction: specularFraction,
            shadowUniformity: shadowUniformity,
            segmentationConfidence: segmentation.confidenceStatistics.meanForegroundProbability,
            calibrationConfidence: calibrationConfidence,
            accepted: accepted,
            rejectionReasons: uniqueRejections,
            preprocessingVersion: configuration.preprocessingVersion,
            calibrationDurationMs: start.duration(to: .now).milliseconds,
            qualitySummary: qualitySummary,
            diagnosticFeatures: diagnostics
        )
    }

    private func confidence(for mode: CalibrationMode) -> Double {
        switch mode {
        case .multiPatchReference: 1
        case .neutralPatchReference: 0.7
        case .teethPseudoReference: 0.5
        case .uncalibratedRejected: 0
        }
    }

    private struct LinearImage {
        let pixels: [SIMD3<Double>]
        let width: Int
        let height: Int
    }

    private func makeLinearImage(from source: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> LinearImage {
        guard CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA else {
            throw InferenceError.unsupportedPixelFormat("Calibration requires 32BGRA")
        }
        let oriented = CIImage(cvPixelBuffer: source).oriented(orientation)
        let translated = oriented.transformed(by: CGAffineTransform(
            translationX: -oriented.extent.origin.x,
            y: -oriented.extent.origin.y
        ))
        let width = Int(translated.extent.width.rounded())
        let height = Int(translated.extent.height.rounded())
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw InferenceError.unsupportedPixelFormat("sRGB is unavailable")
        }
        let normalized: CVPixelBuffer
        if orientation == .up {
            normalized = source
        } else {
            normalized = try allocatePixelBuffer(width: width, height: height, pixelFormat: kCVPixelFormatType_32BGRA)
            context.render(
                translated,
                to: normalized,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                colorSpace: colorSpace
            )
        }
        let lockStatus = CVPixelBufferLockBaseAddress(normalized, .readOnly)
        guard lockStatus == kCVReturnSuccess, let baseAddress = CVPixelBufferGetBaseAddress(normalized) else {
            throw InferenceError.pixelBufferLockFailed(lockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(normalized, .readOnly) }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(normalized)
        var pixels = [SIMD3<Double>]()
        pixels.reserveCapacity(width * height)
        for row in 0..<height {
            for column in 0..<width {
                let offset = row * bytesPerRow + column * 4
                pixels.append(SIMD3(
                    decodeSRGB(bytes[offset + 2]),
                    decodeSRGB(bytes[offset + 1]),
                    decodeSRGB(bytes[offset])
                ))
            }
        }
        return LinearImage(pixels: pixels, width: width, height: height)
    }

    private func resizeMask(
        _ source: [UInt8],
        sourceWidth: Int,
        sourceHeight: Int,
        destinationWidth: Int,
        destinationHeight: Int
    ) throws -> [UInt8] {
        guard source.count == sourceWidth * sourceHeight else { throw InferenceError.invalidDimensions }
        let normalizedSource = source.map { $0 == 0 ? UInt8(0) : UInt8(255) }
        var destination = [UInt8](repeating: 0, count: destinationWidth * destinationHeight)
        let error = normalizedSource.withUnsafeBytes { sourceBytes in
            destination.withUnsafeMutableBytes { destinationBytes in
                var sourceBuffer = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: sourceBytes.baseAddress),
                    height: vImagePixelCount(sourceHeight),
                    width: vImagePixelCount(sourceWidth),
                    rowBytes: sourceWidth
                )
                var destinationBuffer = vImage_Buffer(
                    data: destinationBytes.baseAddress,
                    height: vImagePixelCount(destinationHeight),
                    width: vImagePixelCount(destinationWidth),
                    rowBytes: destinationWidth
                )
                return vImageScale_Planar8(
                    &sourceBuffer,
                    &destinationBuffer,
                    nil,
                    vImage_Flags(kvImageHighQualityResampling)
                )
            }
        }
        guard error == kvImageNoError else { throw InferenceError.resizeFailed(error) }
        for index in destination.indices { destination[index] = destination[index] >= 128 ? 1 : 0 }
        return destination
    }

    private func validateMetadata(_ metadata: CalibrationCaptureMetadata) -> [CalibrationRejectionReason] {
        let stable = metadata.focusWasLocked
            && metadata.exposureWasLocked
            && metadata.whiteBalanceWasLocked
            && abs(metadata.exposureTargetOffset) <= 0.35
            && metadata.sourceColorSpaceName != "unknown"
        return stable ? [] : [.invalidCaptureMetadata]
    }

    private func validateMask(
        _ mask: [UInt8],
        width: Int,
        height: Int,
        configuration: ColorCalibrationConfiguration
    ) -> [CalibrationRejectionReason] {
        var reasons = [CalibrationRejectionReason]()
        let count = mask.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
        if Double(count) / Double(max(1, mask.count)) < configuration.minimumTongueAreaRatio {
            reasons.append(.tongueMaskTooSmall)
        }
        let margin = max(0, configuration.boundaryMarginPixels)
        if margin > 0 {
            for row in 0..<height {
                for column in 0..<width where row < margin || column < margin || row >= height - margin || column >= width - margin {
                    if mask[row * width + column] != 0 {
                        reasons.append(.tongueMaskTouchesBoundary)
                        return reasons
                    }
                }
            }
        }
        return reasons
    }

    private struct PatchStatistic {
        let median: SIMD3<Double>?
        let clipped: Bool
    }

    private func robustPatchStatistic(
        _ patch: CalibrationPatch,
        pixels: [SIMD3<Double>],
        width: Int,
        height: Int,
        configuration: ColorCalibrationConfiguration
    ) -> PatchStatistic {
        let raw = pixelRect(patch.normalizedRect, width: width, height: height)
        let insetX = Int(Double(raw.width) * configuration.patchBorderFraction)
        let insetY = Int(Double(raw.height) * configuration.patchBorderFraction)
        let rect = raw.insetBy(dx: insetX, dy: insetY)
        guard rect.width > 1, rect.height > 1 else { return PatchStatistic(median: nil, clipped: false) }
        var candidates = [SIMD3<Double>]()
        var saturated = 0
        for row in rect.minY..<rect.maxY {
            for column in rect.minX..<rect.maxX {
                let value = pixels[row * width + column]
                if max(value.x, max(value.y, value.z)) >= configuration.saturationThreshold {
                    saturated += 1
                    continue
                }
                if dot(value, SIMD3(0.2126, 0.7152, 0.0722)) <= configuration.shadowThreshold { continue }
                candidates.append(value)
            }
        }
        let total = max(1, rect.width * rect.height)
        guard let initial = channelMedian(candidates) else {
            return PatchStatistic(median: nil, clipped: Double(saturated) / Double(total) > 0.1)
        }
        let filtered = candidates.filter { simd_distance($0, initial) <= configuration.outlierDistanceThreshold }
        return PatchStatistic(
            median: channelMedian(filtered),
            clipped: Double(saturated) / Double(total) > 0.1
        )
    }

    private struct SelectedCalibration {
        let mode: CalibrationMode
        let solution: CalibrationMatrixSolution
        let usablePatchCount: Int
    }

    private func selectCalibration(
        observed: [SIMD3<Double>],
        targets: [SIMD3<Double>],
        weights: [Double],
        pixels: [SIMD3<Double>],
        width: Int,
        height: Int,
        configuration: ColorCalibrationConfiguration
    ) throws -> SelectedCalibration {
        if observed.count >= configuration.minimumUsablePatchCount {
            return SelectedCalibration(
                mode: .multiPatchReference,
                solution: try CalibrationMath.solveWeightedMatrix(
                    observed: observed,
                    target: targets,
                    weights: weights,
                    lambda: configuration.regularizationLambda
                ),
                usablePatchCount: observed.count
            )
        }
        if configuration.patches.count == 1,
           configuration.patches[0].isNeutral,
           let neutralObserved = observed.first,
           let neutralTarget = targets.first {
            return SelectedCalibration(
                mode: .neutralPatchReference,
                solution: CalibrationMath.diagonalSolution(
                    observed: neutralObserved,
                    target: neutralTarget,
                    gainRange: configuration.teethGainRange
                ),
                usablePatchCount: observed.count
            )
        }
        if let teethPatch = configuration.teethPatch {
            let statistic = robustPatchStatistic(
                teethPatch,
                pixels: pixels,
                width: width,
                height: height,
                configuration: configuration
            )
            if let teeth = statistic.median {
                return SelectedCalibration(
                    mode: .teethPseudoReference,
                    solution: CalibrationMath.diagonalSolution(
                        observed: teeth,
                        target: teethPatch.targetLinearRGB,
                        gainRange: configuration.teethGainRange
                    ),
                    usablePatchCount: 1
                )
            }
        }
        return SelectedCalibration(
            mode: .uncalibratedRejected,
            solution: CalibrationMatrixSolution(
                rowMajorValues: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                conditionNumber: .infinity
            ),
            usablePatchCount: observed.count
        )
    }

    private func maskedLuminances(
        pixels: [SIMD3<Double>],
        mask: [UInt8],
        width: Int,
        height: Int,
        solution: CalibrationMatrixSolution
    ) -> [Double] {
        var values = [Double]()
        values.reserveCapacity(mask.count / 2)
        for row in 0..<height {
            for column in 0..<width where mask[row * width + column] != 0 {
                let corrected = solution.applying(to: pixels[row * width + column])
                values.append(dot(corrected, SIMD3(0.2126, 0.7152, 0.0722)))
            }
        }
        return values
    }

    private func boundedExposureScale(luminances: [Double], configuration: ColorCalibrationConfiguration) -> Double {
        guard let target = configuration.targetTongueMedianLuminance,
              let observed = median(luminances), observed > 0 else { return 1 }
        return min(max(target / observed, configuration.exposureScaleRange.lowerBound), configuration.exposureScaleRange.upperBound)
    }

    private func relativeSpread(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty, let center = median(sorted), center > 0 else { return 1 }
        let lower = sorted[Int(Double(sorted.count - 1) * 0.1)]
        let upper = sorted[Int(Double(sorted.count - 1) * 0.9)]
        return max(0, upper - lower) / center
    }

    private func erode(_ source: [UInt8], width: Int, height: Int, iterations: Int) -> [UInt8] {
        var current = source
        guard width > 2, height > 2 else { return current }
        for _ in 0..<max(0, iterations) {
            var next = [UInt8](repeating: 0, count: current.count)
            for row in 1..<(height - 1) {
                for column in 1..<(width - 1) {
                    var keep = true
                    for neighborRow in (row - 1)...(row + 1) {
                        for neighborColumn in (column - 1)...(column + 1) where current[neighborRow * width + neighborColumn] == 0 {
                            keep = false
                        }
                    }
                    next[row * width + column] = keep ? 1 : 0
                }
            }
            current = next
        }
        return current
    }

    private func diagnosticFeatures(pixels: [SIMD3<Double>], mask: [UInt8]) -> CalibrationDiagnosticFeatures {
        let accepted = pixels.indices.filter { mask[$0] != 0 }.map { pixels[$0] }
        let medianRGB = channelMedian(accepted) ?? .zero
        let labValues = accepted.map(CalibrationMath.linearRGBToLab)
        let count = Double(max(1, labValues.count))
        let totalLab = labValues.reduce(SIMD3<Double>.zero, +)
        return CalibrationDiagnosticFeatures(
            meanLabL: totalLab.x / count,
            meanLabA: totalLab.y / count,
            meanLabB: totalLab.z / count,
            medianLinearRed: medianRGB.x,
            medianLinearGreen: medianRGB.y,
            medianLinearBlue: medianRGB.z,
            acceptedPixelCount: accepted.count
        )
    }

    private func makeEncodedSRGBBuffer(pixels: [SIMD3<Double>], width: Int, height: Int) throws -> CVPixelBuffer {
        let buffer = try allocatePixelBuffer(width: width, height: height, pixelFormat: kCVPixelFormatType_32BGRA)
        let status = CVPixelBufferLockBaseAddress(buffer, [])
        guard status == kCVReturnSuccess, let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw InferenceError.pixelBufferLockFailed(status)
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            for column in 0..<width {
                let rgb = pixels[row * width + column]
                let offset = row * bytesPerRow + column * 4
                bytes[offset] = encodeSRGB(rgb.z)
                bytes[offset + 1] = encodeSRGB(rgb.y)
                bytes[offset + 2] = encodeSRGB(rgb.x)
                bytes[offset + 3] = 255
            }
        }
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        }
        return buffer
    }

    private func allocatePixelBuffer(width: Int, height: Int, pixelFormat: OSType) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw InferenceError.pixelBufferAllocationFailed(status)
        }
        return buffer
    }

    private func pixelRect(_ normalized: CGRect, width: Int, height: Int) -> PixelRect {
        let minimumX = min(max(0, Int((normalized.minX * Double(width)).rounded(.down))), width)
        let minimumY = min(max(0, Int((normalized.minY * Double(height)).rounded(.down))), height)
        let maximumX = min(max(minimumX, Int((normalized.maxX * Double(width)).rounded(.up))), width)
        let maximumY = min(max(minimumY, Int((normalized.maxY * Double(height)).rounded(.up))), height)
        return PixelRect(minX: minimumX, minY: minimumY, maxX: maximumX, maxY: maximumY)
    }

    private func channelMedian(_ values: [SIMD3<Double>]) -> SIMD3<Double>? {
        guard !values.isEmpty else { return nil }
        return SIMD3(
            median(values.map(\.x)) ?? 0,
            median(values.map(\.y)) ?? 0,
            median(values.map(\.z)) ?? 0
        )
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private func encodeSRGB(_ value: Double) -> UInt8 {
        let clamped = min(max(value, 0), 1)
        let encoded = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        return UInt8(min(255, max(0, Int((encoded * 255).rounded()))))
    }

    private func decodeSRGB(_ value: UInt8) -> Double {
        let encoded = Double(value) / 255
        return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }
}

private struct PixelRect {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
    var width: Int { maxX - minX }
    var height: Int { maxY - minY }

    func insetBy(dx: Int, dy: Int) -> PixelRect {
        PixelRect(minX: minX + dx, minY: minY + dy, maxX: maxX - dx, maxY: maxY - dy)
    }
}
