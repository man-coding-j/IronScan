import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

struct SaliencyHeatmapGenerator {
    static func generateHeatmap(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try VisionComputeSafety.requireCPU(for: request)
            try handler.perform([request])
            guard let observation = request.results?.first as? VNSaliencyImageObservation else { return nil }
            
            let pixelBuffer = observation.pixelBuffer
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            // Scale the saliency map up to the original image bounds
            let scaleX = CGFloat(cgImage.width) / ciImage.extent.width
            let scaleY = CGFloat(cgImage.height) / ciImage.extent.height
            let scaledCIImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            // Tint the heatmap with a red gradient
            let colorizeFilter = CIFilter.falseColor()
            colorizeFilter.inputImage = scaledCIImage
            colorizeFilter.color0 = CIColor(color: .red) // High attention area
            colorizeFilter.color1 = CIColor(color: .clear) // Low attention area
            
            guard let outputImage = colorizeFilter.outputImage else { return nil }
            
            // Blend the red glowing mask over the original image
            let originalCI = CIImage(cgImage: cgImage)
            let blendFilter = CIFilter.sourceOverCompositing()
            blendFilter.inputImage = outputImage
            blendFilter.backgroundImage = originalCI
            
            guard let blendedOutput = blendFilter.outputImage else { return nil }
            
            let context = CIContext()
            guard let finalCGImage = context.createCGImage(blendedOutput, from: originalCI.extent) else { return nil }
            
            return UIImage(cgImage: finalCGImage)
        } catch {
            print("Failed to generate heatmap: \(error)")
            return nil
        }
    }
}
