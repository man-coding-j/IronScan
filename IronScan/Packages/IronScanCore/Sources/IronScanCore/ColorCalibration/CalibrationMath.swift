import Accelerate
import Foundation
import simd

enum CalibrationMathError: Error, Equatable, Sendable {
    case insufficientSamples
    case solveFailed(Int32)
    case eigenvalueFailed(Int32)
}

struct CalibrationMatrixSolution: Equatable, Sendable {
    let rowMajorValues: [Double]
    let conditionNumber: Double

    func applying(to value: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            value.x * rowMajorValues[0] + value.y * rowMajorValues[3] + value.z * rowMajorValues[6],
            value.x * rowMajorValues[1] + value.y * rowMajorValues[4] + value.z * rowMajorValues[7],
            value.x * rowMajorValues[2] + value.y * rowMajorValues[5] + value.z * rowMajorValues[8]
        )
    }
}

enum CalibrationMath {
    static func solveWeightedMatrix(
        observed: [SIMD3<Double>],
        target: [SIMD3<Double>],
        weights: [Double],
        lambda: Double
    ) throws -> CalibrationMatrixSolution {
        guard observed.count >= 3, observed.count == target.count, observed.count == weights.count else {
            throw CalibrationMathError.insufficientSamples
        }
        var normal = [Double](repeating: 0, count: 9)
        var rightHandSide = [Double](repeating: 0, count: 9)
        for index in observed.indices {
            let source = observed[index]
            let destination = target[index]
            let weight = max(0, weights[index])
            for row in 0..<3 {
                for column in 0..<3 {
                    normal[column * 3 + row] += weight * source[row] * source[column]
                    rightHandSide[column * 3 + row] += weight * source[row] * destination[column]
                }
            }
        }
        for diagonal in 0..<3 {
            normal[diagonal * 3 + diagonal] += lambda
            rightHandSide[diagonal * 3 + diagonal] += lambda
        }

        let conditionNumber = try symmetricConditionNumber(normal)
        var factor = normal
        var solution = rightHandSide
        var upper: Int8 = 85
        var dimension: __LAPACK_int = 3
        var rightHandSideCount: __LAPACK_int = 3
        var leadingDimension: __LAPACK_int = 3
        var rightHandSideLeadingDimension: __LAPACK_int = 3
        var info: __LAPACK_int = 0
        dposv_(
            &upper,
            &dimension,
            &rightHandSideCount,
            &factor,
            &leadingDimension,
            &solution,
            &rightHandSideLeadingDimension,
            &info
        )
        guard info == 0 else { throw CalibrationMathError.solveFailed(Int32(info)) }

        var rowMajor = [Double](repeating: 0, count: 9)
        for row in 0..<3 {
            for column in 0..<3 {
                rowMajor[row * 3 + column] = solution[column * 3 + row]
            }
        }
        return CalibrationMatrixSolution(rowMajorValues: rowMajor, conditionNumber: conditionNumber)
    }

    static func diagonalSolution(
        observed: SIMD3<Double>,
        target: SIMD3<Double>,
        gainRange: ClosedRange<Double>
    ) -> CalibrationMatrixSolution {
        var gains = target / simd_max(observed, SIMD3(repeating: 0.000_001))
        gains = simd_clamp(gains, SIMD3(repeating: gainRange.lowerBound), SIMD3(repeating: gainRange.upperBound))
        let observedLuminance = dot(observed, SIMD3(0.2126, 0.7152, 0.0722))
        let correctedLuminance = dot(observed * gains, SIMD3(0.2126, 0.7152, 0.0722))
        if correctedLuminance > 0 {
            let luminanceScale = observedLuminance / correctedLuminance
            gains = simd_clamp(gains * luminanceScale, SIMD3(repeating: gainRange.lowerBound), SIMD3(repeating: gainRange.upperBound))
        }
        return CalibrationMatrixSolution(
            rowMajorValues: [gains.x, 0, 0, 0, gains.y, 0, 0, 0, gains.z],
            conditionNumber: 1
        )
    }

    static func linearRGBToLab(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let clamped = simd_max(rgb, .zero)
        let xyz = SIMD3(
            0.4124564 * clamped.x + 0.3575761 * clamped.y + 0.1804375 * clamped.z,
            0.2126729 * clamped.x + 0.7151522 * clamped.y + 0.0721750 * clamped.z,
            0.0193339 * clamped.x + 0.1191920 * clamped.y + 0.9503041 * clamped.z
        )
        let white = SIMD3(0.95047, 1.0, 1.08883)
        let normalized = xyz / white
        let delta = 6.0 / 29.0
        let threshold = delta * delta * delta
        let transform: (Double) -> Double = { value in
            value > threshold ? pow(value, 1.0 / 3.0) : value / (3 * delta * delta) + 4.0 / 29.0
        }
        let fx = transform(normalized.x)
        let fy = transform(normalized.y)
        let fz = transform(normalized.z)
        return SIMD3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    static func deltaE(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        simd_distance(linearRGBToLab(first), linearRGBToLab(second))
    }

    private static func symmetricConditionNumber(_ matrix: [Double]) throws -> Double {
        var values = matrix
        var job: Int8 = 78
        var upper: Int8 = 85
        var dimension: __LAPACK_int = 3
        var leadingDimension: __LAPACK_int = 3
        var eigenvalues = [Double](repeating: 0, count: 3)
        var workspaceQuery = 0.0
        var workspaceLength: __LAPACK_int = -1
        var info: __LAPACK_int = 0
        dsyev_(&job, &upper, &dimension, &values, &leadingDimension, &eigenvalues, &workspaceQuery, &workspaceLength, &info)
        guard info == 0 else { throw CalibrationMathError.eigenvalueFailed(Int32(info)) }
        workspaceLength = __LAPACK_int(max(8, Int(workspaceQuery.rounded(.up))))
        var workspace = [Double](repeating: 0, count: Int(workspaceLength))
        values = matrix
        dsyev_(&job, &upper, &dimension, &values, &leadingDimension, &eigenvalues, &workspace, &workspaceLength, &info)
        guard info == 0 else { throw CalibrationMathError.eigenvalueFailed(Int32(info)) }
        guard let minimum = eigenvalues.first, let maximum = eigenvalues.last, minimum > 0 else {
            return .infinity
        }
        return sqrt(maximum / minimum)
    }
}
