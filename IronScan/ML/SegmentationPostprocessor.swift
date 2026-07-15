import Foundation

struct SegmentationPostprocessor: Sendable {
    func process(
        probabilities: [Float],
        width: Int,
        height: Int,
        threshold: Double,
        configuration: ModelManifest.Postprocessing
    ) throws -> (mask: [UInt8], statistics: SegmentationConfidenceStatistics) {
        guard width > 0, height > 0, probabilities.count == width * height else {
            throw InferenceError.invalidOutputShape("probability_mask")
        }
        var mask = probabilities.map { $0 >= Float(threshold) ? UInt8(1) : UInt8(0) }
        if configuration.largestConnectedComponent {
            mask = keepLargestComponent(mask, width: width, height: height)
        }
        mask = fillSmallHoles(
            mask,
            width: width,
            height: height,
            maximumArea: configuration.maximumHoleAreaPixels
        )
        mask = erode(
            dilate(mask, width: width, height: height, iterations: configuration.closingRadiusPixels),
            width: width,
            height: height,
            iterations: configuration.closingRadiusPixels
        )
        mask = removeSmallComponents(
            mask,
            width: width,
            height: height,
            minimumArea: configuration.minimumComponentAreaPixels
        )
        let boundaryIterations = Int(ceil(Double(min(width, height)) * configuration.boundaryErosionPercentage))
        mask = erode(mask, width: width, height: height, iterations: boundaryIterations)

        let foregroundIndices = mask.indices.filter { mask[$0] == 1 }
        let foregroundProbabilities = foregroundIndices.map { Double(probabilities[$0]) }
        let count = foregroundIndices.count
        let statistics = SegmentationConfidenceStatistics(
            meanForegroundProbability: foregroundProbabilities.isEmpty
                ? 0
                : foregroundProbabilities.reduce(0, +) / Double(foregroundProbabilities.count),
            minimumForegroundProbability: foregroundProbabilities.min() ?? 0,
            maximumForegroundProbability: foregroundProbabilities.max() ?? 0,
            foregroundPixelCount: count,
            areaRatio: Double(count) / Double(width * height)
        )
        return (mask, statistics)
    }

    private func keepLargestComponent(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        let components = components(in: mask, matching: 1, width: width, height: height)
        guard let largest = components.max(by: { $0.indices.count < $1.indices.count }) else {
            return mask
        }
        var result = [UInt8](repeating: 0, count: mask.count)
        for index in largest.indices {
            result[index] = 1
        }
        return result
    }

    private func removeSmallComponents(
        _ mask: [UInt8],
        width: Int,
        height: Int,
        minimumArea: Int
    ) -> [UInt8] {
        var result = mask
        for component in components(in: mask, matching: 1, width: width, height: height)
        where component.indices.count < minimumArea {
            for index in component.indices {
                result[index] = 0
            }
        }
        return result
    }

    private func fillSmallHoles(
        _ mask: [UInt8],
        width: Int,
        height: Int,
        maximumArea: Int
    ) -> [UInt8] {
        var result = mask
        for component in components(in: mask, matching: 0, width: width, height: height)
        where !component.touchesBoundary && component.indices.count <= maximumArea {
            for index in component.indices {
                result[index] = 1
            }
        }
        return result
    }

    private func dilate(_ mask: [UInt8], width: Int, height: Int, iterations: Int) -> [UInt8] {
        guard iterations > 0 else { return mask }
        var current = mask
        for _ in 0..<iterations {
            var next = current
            for row in 0..<height {
                for column in 0..<width where current[row * width + column] == 0 {
                    if neighbors(of: row * width + column, width: width, height: height)
                        .contains(where: { current[$0] == 1 }) {
                        next[row * width + column] = 1
                    }
                }
            }
            current = next
        }
        return current
    }

    private func erode(_ mask: [UInt8], width: Int, height: Int, iterations: Int) -> [UInt8] {
        guard iterations > 0 else { return mask }
        var current = mask
        for _ in 0..<iterations {
            var next = current
            for row in 0..<height {
                for column in 0..<width where current[row * width + column] == 1 {
                    let index = row * width + column
                    let isBoundary = row == 0 || column == 0 || row == height - 1 || column == width - 1
                    if isBoundary || neighbors(of: index, width: width, height: height).contains(where: { current[$0] == 0 }) {
                        next[index] = 0
                    }
                }
            }
            current = next
        }
        return current
    }

    private struct Component {
        let indices: [Int]
        let touchesBoundary: Bool
    }

    private func components(in mask: [UInt8], matching value: UInt8, width: Int, height: Int) -> [Component] {
        var visited = [Bool](repeating: false, count: mask.count)
        var result = [Component]()
        for start in mask.indices where mask[start] == value && !visited[start] {
            var queue = [start]
            var cursor = 0
            var indices = [Int]()
            var touchesBoundary = false
            visited[start] = true
            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                indices.append(index)
                let row = index / width
                let column = index % width
                touchesBoundary = touchesBoundary || row == 0 || column == 0 || row == height - 1 || column == width - 1
                for neighbor in neighbors(of: index, width: width, height: height)
                where mask[neighbor] == value && !visited[neighbor] {
                    visited[neighbor] = true
                    queue.append(neighbor)
                }
            }
            result.append(Component(indices: indices, touchesBoundary: touchesBoundary))
        }
        return result
    }

    private func neighbors(of index: Int, width: Int, height: Int) -> [Int] {
        let row = index / width
        let column = index % width
        var result = [Int]()
        if row > 0 { result.append(index - width) }
        if row + 1 < height { result.append(index + width) }
        if column > 0 { result.append(index - 1) }
        if column + 1 < width { result.append(index + 1) }
        return result
    }
}
