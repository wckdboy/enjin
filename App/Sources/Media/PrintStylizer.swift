import CoreImage
import EnjinKit
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// Applies the "Enjin print" Metal kernel (EnjinPrint.metal) to every picture
/// before it's saved, so photos and illustrations share one look.
struct PrintStylizer: ImageStylizer {
    /// Longest side of stored pictures: plenty for a card or banner, keeps notebooks small.
    static let maxSide: CGFloat = 960

    private static let kernel: CIKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CIKernel(functionName: "enjinPrint", fromMetalLibraryData: data)
    }()
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let log = Logger(subsystem: "cc.wckd.enjin", category: "stylize")

    func stylize(_ image: FoundImage) async -> FoundImage {
        guard let kernel = Self.kernel, let input = CIImage(data: image.data, options: [.applyOrientationProperty: true]) else {
            Self.log.error("stylize skipped (no kernel or undecodable image)")
            return image
        }
        let scale = min(1, Self.maxSide / max(input.extent.width, input.extent.height))
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = scaled.extent
        // The kernel's palette is sRGB: run it on sRGB-encoded values.
        let srgb = scaled.applyingFilter("CILinearToSRGBToneCurve").clampedToExtent()
        guard let styled = kernel.apply(extent: extent, roiCallback: { _, r in r.insetBy(dx: -3, dy: -3) },
                                        arguments: [srgb, Float(6), Float(0.9), Float(0.5), Float(0.035)])?
            .applyingFilter("CISRGBToneCurveToLinear").cropped(to: extent),
              let cg = Self.context.createCGImage(styled, from: extent) else { return image }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return image }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return image }
        var result = image
        result.data = out as Data
        result.mimeType = "image/jpeg"
        result.width = cg.width
        result.height = cg.height
        return result
    }
}
