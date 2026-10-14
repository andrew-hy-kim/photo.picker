import Foundation

/// Ranks photos within a group of near-duplicates. Every metric is normalised relative to
/// the rest of the group, so we only ask "which of these is best", never "is this good".
enum PhotoRanker {
    private enum Weight {
        static let sharpness = 0.35
        static let faces = 0.30
        static let aesthetics = 0.20
        static let exposure = 0.15
        static let favoriteBonus = 0.15
    }

    static func rank(_ group: [PhotoAnalysis]) -> PhotoGroup {
        let sharpness = normalize(group.map(\.sharpness), minSpread: 0.15)
        let exposure = normalize(group.map(\.exposure), minSpread: 0.05)

        // Only score faces when someone is in the shot; a frame where faces vanished
        // (turned away, cut off) then scores 0 against the others.
        let hasFaces = group.contains { $0.faceQuality != nil }
        let faces = hasFaces ? normalize(group.map { $0.faceQuality ?? 0 }, minSpread: 0.05) : nil

        let hasAesthetics = group.allSatisfy { $0.aesthetics != nil }
        let aesthetics = hasAesthetics ? normalize(group.map { $0.aesthetics! }, minSpread: 0.05) : nil

        var scored: [ScoredPhoto] = []
        for (i, photo) in group.enumerated() {
            var total = Weight.sharpness * sharpness[i] + Weight.exposure * exposure[i]
            var weights = Weight.sharpness + Weight.exposure
            if let faces {
                total += Weight.faces * faces[i]
                weights += Weight.faces
            }
            if let aesthetics {
                total += Weight.aesthetics * aesthetics[i]
                weights += Weight.aesthetics
            }
            var score = total / weights
            if photo.asset.isFavorite { score += Weight.favoriteBonus }

            let breakdown = ScoreBreakdown(
                sharpness: sharpness[i],
                exposure: exposure[i],
                faces: faces?[i],
                aesthetics: aesthetics?[i]
            )
            var reasons: [String] = []
            if photo.asset.isFavorite { reasons.append("Favorited") }
            if let faces, isTop(faces, i) { reasons.append("Best faces") }
            if isTop(sharpness, i) { reasons.append("Sharpest") }
            if let aesthetics, isTop(aesthetics, i) { reasons.append("Best composition") }
            if isTop(exposure, i) { reasons.append("Best exposure") }

            scored.append(ScoredPhoto(asset: photo.asset, score: score, breakdown: breakdown, reasons: reasons))
        }

        scored.sort { $0.score > $1.score }
        return PhotoGroup(photos: scored, keptIDs: [scored[0].id])
    }

    /// Min-max normalisation. If the values are all within `minSpread` of each other the
    /// differences are noise, so everyone gets full marks for that metric.
    private static func normalize(_ values: [Double], minSpread: Double) -> [Double] {
        guard let lo = values.min(), let hi = values.max(), hi - lo >= minSpread else {
            return values.map { _ in 1 }
        }
        return values.map { ($0 - lo) / (hi - lo) }
    }

    /// True when photo `i` is the stand-out for a metric that actually varied across the group.
    private static func isTop(_ normalized: [Double], _ i: Int) -> Bool {
        normalized[i] == 1 && normalized.contains { $0 < 1 }
    }
}
