import Foundation
import Photos
import Vision

/// Raw, per-photo measurements produced by `PhotoAnalyzer`.
struct PhotoAnalysis {
    let asset: PHAsset
    let featurePrint: VNFeaturePrintObservation?
    /// Log of the Laplacian variance. Higher = sharper.
    let sharpness: Double
    /// 0...1, penalises very dark/bright images and clipped highlights/shadows.
    let exposure: Double
    /// 0...1 face capture quality (eyes open, in focus, facing camera). nil when no faces.
    let faceQuality: Double?
    /// Apple's aesthetic score (-1...1). nil when unavailable (iOS < 18).
    let aesthetics: Double?

    var date: Date { asset.creationDate ?? .distantPast }
}

/// Per-metric scores normalised *within a group* to 0...1.
struct ScoreBreakdown {
    var sharpness: Double
    var exposure: Double
    var faces: Double?
    var aesthetics: Double?
}

struct ScoredPhoto: Identifiable {
    var id: String { asset.localIdentifier }
    let asset: PHAsset
    let score: Double
    let breakdown: ScoreBreakdown
    let reasons: [String]
}

struct PhotoGroup: Identifiable {
    let id = UUID()
    /// Sorted best-first.
    var photos: [ScoredPhoto]
    var keptIDs: Set<String>

    var best: ScoredPhoto { photos[0] }
    var date: Date? { photos.compactMap(\.asset.creationDate).min() }
    var discarded: [PHAsset] { photos.filter { !keptIDs.contains($0.id) }.map(\.asset) }

    func isKept(_ photo: ScoredPhoto) -> Bool { keptIDs.contains(photo.id) }

    mutating func toggleKeep(_ photo: ScoredPhoto) {
        if keptIDs.contains(photo.id) {
            keptIDs.remove(photo.id)
        } else {
            keptIDs.insert(photo.id)
        }
    }

    mutating func keepOnly(_ photo: ScoredPhoto) {
        keptIDs = [photo.id]
    }
}
