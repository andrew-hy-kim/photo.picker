import CoreGraphics
import ImageIO
import Photos
import UIKit
import Vision

enum PhotoAnalyzer {
    /// Size of the image used for analysis. Big enough to judge focus, small enough to be fast.
    static let analysisSize: CGFloat = 768

    static func analyze(_ asset: PHAsset) async -> PhotoAnalysis? {
        guard let uiImage = await PhotoLibrary.image(for: asset, maxDimension: analysisSize, exact: true),
              let cgImage = uiImage.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)

        let featureRequest = VNGenerateImageFeaturePrintRequest()
        featureRequest.revision = VNGenerateImageFeaturePrintRequestRevision2
        let faceRequest = VNDetectFaceCaptureQualityRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try? handler.perform([featureRequest, faceRequest])

        let faceScores = (faceRequest.results ?? []).compactMap { $0.faceCaptureQuality }.map(Double.init)
        var faceQuality: Double?
        if !faceScores.isEmpty {
            // Blend the worst face with the average so one person blinking drags the photo down.
            let mean = faceScores.reduce(0, +) / Double(faceScores.count)
            faceQuality = 0.5 * faceScores.min()! + 0.5 * mean
        }

        var aesthetics: Double?
        if #available(iOS 18.0, *) {
            let request = CalculateImageAestheticsScoresRequest()
            if let observation = try? await request.perform(on: cgImage, orientation: orientation) {
                aesthetics = Double(observation.overallScore)
            }
        }

        let stats = pixelStats(cgImage)

        return PhotoAnalysis(
            asset: asset,
            featurePrint: featureRequest.results?.first,
            sharpness: stats.sharpness,
            exposure: stats.exposure,
            faceQuality: faceQuality,
            aesthetics: aesthetics
        )
    }

    /// Sharpness (variance of the Laplacian) and a simple exposure score from a grayscale render.
    private static func pixelStats(_ image: CGImage) -> (sharpness: Double, exposure: Double) {
        let w = image.width, h = image.height
        guard w > 2, h > 2 else { return (0, 0.5) }

        var pixels = [UInt8](repeating: 0, count: w * h)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard rendered else { return (0, 0.5) }

        var sum = 0.0, sumSquares = 0.0
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let i = row + x
                let lap = 4 * Double(pixels[i])
                    - Double(pixels[i - 1]) - Double(pixels[i + 1])
                    - Double(pixels[i - w]) - Double(pixels[i + w])
                sum += lap
                sumSquares += lap * lap
            }
        }
        let n = Double((w - 2) * (h - 2))
        let mean = sum / n
        let variance = max(0, sumSquares / n - mean * mean)

        var luminance = 0.0
        var clipped = 0
        for p in pixels {
            luminance += Double(p)
            if p < 6 || p > 249 { clipped += 1 }
        }
        let meanLuminance = luminance / Double(pixels.count) / 255
        let clippedFraction = Double(clipped) / Double(pixels.count)
        let exposure = max(0, 1 - abs(meanLuminance - 0.5) * 1.2 - clippedFraction * 1.5)

        return (log1p(variance), exposure)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
