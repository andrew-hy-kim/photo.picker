import CoreGraphics
import Photos
import UIKit
import Vision

enum PhotoAnalyzer {
    /// Size of the image used for analysis. Big enough to judge focus, small enough to be fast.
    static let analysisSize: CGFloat = 768

    static func analyze(_ asset: PHAsset) async -> PhotoAnalysis? {
        guard let uiImage = await PhotoLibrary.image(for: asset, maxDimension: analysisSize, exact: true),
              let cgImage = upright(uiImage) else { return nil }

        let featureRequest = VNGenerateImageFeaturePrintRequest()
        featureRequest.revision = VNGenerateImageFeaturePrintRequestRevision2
        let faceRequest = VNDetectFaceCaptureQualityRequest()
        let animalRequest = VNRecognizeAnimalsRequest()
        let animalPoseRequest = VNDetectAnimalBodyPoseRequest()
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()

        // Run requests one at a time so one failing (e.g. unsupported in the Simulator)
        // doesn't throw away the others' results. The handler caches the decoded image.
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let requests: [VNRequest] = [featureRequest, faceRequest, animalRequest, animalPoseRequest, saliencyRequest]
        for request in requests {
            try? handler.perform([request])
        }

        let faces = faceRequest.results ?? []
        let faceScores = faces.compactMap { $0.faceCaptureQuality }.map(Double.init)
        var faceQuality: Double?
        if !faceScores.isEmpty {
            // Blend the worst face with the average so one person blinking drags the photo down.
            let mean = faceScores.reduce(0, +) / Double(faceScores.count)
            faceQuality = 0.5 * faceScores.min()! + 0.5 * mean
        }

        let animal = (animalRequest.results ?? [])
            .filter { $0.confidence > 0.5 }
            .max { area($0.boundingBox) < area($1.boundingBox) }
        var animalScore: Double?
        if let animal {
            animalScore = 0.6 * framingScore(animal.boundingBox) + 0.4 * eyesVisible(animalPoseRequest.results)
        }

        var aesthetics: Double?
        if #available(iOS 18.0, *) {
            let request = CalculateImageAestheticsScoresRequest()
            if let observation = try? await request.perform(on: cgImage) {
                aesthetics = Double(observation.overallScore)
            }
        }

        let subject = subjectRegion(
            faces: faces.map(\.boundingBox),
            animal: animal?.boundingBox,
            salient: saliencyRequest.results?.first?.salientObjects?.map(\.boundingBox) ?? []
        )
        let stats = pixelStats(cgImage, sharpnessRegion: subject)

        return PhotoAnalysis(
            asset: asset,
            featurePrint: featureRequest.results?.first,
            sharpness: stats.sharpness,
            exposure: stats.exposure,
            faceQuality: faceQuality,
            animalScore: animalScore,
            aesthetics: aesthetics
        )
    }

    /// Redraws the image with its orientation applied, so Vision's coordinates and our
    /// pixel buffer agree on which way is up.
    private static func upright(_ image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(at: .zero) }
            .cgImage
    }

    // MARK: - Subject

    /// Where focus matters: people's faces and/or the animal, else whatever draws the eye.
    /// Normalised Vision coordinates (origin bottom-left). nil = use the whole frame.
    private static func subjectRegion(faces: [CGRect], animal: CGRect?, salient: [CGRect]) -> CGRect? {
        // Grow face boxes so they include hair and jawline, where focus is easiest to judge.
        var boxes = faces.map { $0.insetBy(dx: -$0.width * 0.3, dy: -$0.height * 0.3) }
        if let animal { boxes.append(animal) }
        if boxes.isEmpty { boxes = salient }
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst()
            .reduce(first) { $0.union($1) }
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// 1 when the animal is fully in frame. Touching the top or sides usually means a
    /// cut-off head or body; touching the bottom (paws) matters much less.
    private static func framingScore(_ box: CGRect) -> Double {
        let edge: CGFloat = 0.015
        var score = 1.0
        if box.minX < edge { score -= 0.35 }
        if box.maxX > 1 - edge { score -= 0.35 }
        if box.maxY > 1 - edge { score -= 0.4 }
        if box.minY < edge { score -= 0.1 }
        return max(0, score)
    }

    /// Fraction of the animal's eyes that are visible: 1 = looking at the camera.
    private static func eyesVisible(_ poses: [VNAnimalBodyPoseObservation]?) -> Double {
        guard let pose = poses?.first else { return 0 }
        let eyes: [VNAnimalBodyPoseObservation.JointName] = [.leftEye, .rightEye]
        let visible = eyes.filter { joint in
            ((try? pose.recognizedPoint(joint))?.confidence ?? 0) > 0.3
        }
        return Double(visible.count) / Double(eyes.count)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    // MARK: - Pixels

    /// Sharpness (variance of the Laplacian) inside `sharpnessRegion`, and a simple exposure
    /// score over the whole frame, from a grayscale render.
    ///
    /// Measuring sharpness only on the subject matters: busy backgrounds (rooftops, foliage)
    /// have lots of fine detail and would otherwise beat a well-focused shot with more sky.
    private static func pixelStats(_ image: CGImage, sharpnessRegion: CGRect?) -> (sharpness: Double, exposure: Double) {
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

        // Pixel bounds for the Laplacian (row 0 of the buffer is the top of the image).
        var x0 = 1, x1 = w - 1, y0 = 1, y1 = h - 1
        if let r = sharpnessRegion {
            let rx0 = max(1, Int(r.minX * CGFloat(w)))
            let rx1 = min(w - 1, Int(r.maxX * CGFloat(w)))
            let ry0 = max(1, Int((1 - r.maxY) * CGFloat(h)))
            let ry1 = min(h - 1, Int((1 - r.minY) * CGFloat(h)))
            if rx1 - rx0 >= 32, ry1 - ry0 >= 32 {
                (x0, x1, y0, y1) = (rx0, rx1, ry0, ry1)
            }
        }

        var sum = 0.0, sumSquares = 0.0
        for y in y0..<y1 {
            let row = y * w
            for x in x0..<x1 {
                let i = row + x
                let lap = 4 * Double(pixels[i])
                    - Double(pixels[i - 1]) - Double(pixels[i + 1])
                    - Double(pixels[i - w]) - Double(pixels[i + w])
                sum += lap
                sumSquares += lap * lap
            }
        }
        let n = Double((x1 - x0) * (y1 - y0))
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
