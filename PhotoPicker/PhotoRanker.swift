import Foundation

struct RankingOptions {
    /// When a group has both portrait and landscape shots, also keep the best of the other orientation.
    var keepBestOfEachOrientation = false
    /// If the runner-up scores within this much of the winner, keep both and let the user decide.
    var closeCallMargin = 0.05
}

/// Ranks photos within a group of near-duplicates. Every metric is normalised relative to
/// the rest of the group, so we only ask "which of these is best", never "is this good".
enum PhotoRanker {
    private enum Weight {
        static let sharpness = 0.35
        static let faces = 0.30
        static let animals = 0.30
        static let aesthetics = 0.20
        static let exposure = 0.15
        static let favoriteBonus = 0.15
    }

    static func rank(_ group: [PhotoAnalysis], options: RankingOptions) -> PhotoGroup {
        let sharpness = normalize(group.map(\.sharpness), minSpread: 0.15)
        let exposure = normalize(group.map(\.exposure), minSpread: 0.05)

        // Only score faces/animals when they're in the shot; a frame where they vanished
        // (turned away, cut off) then scores 0 against the others.
        let hasFaces = group.contains { $0.faceQuality != nil }
        let faces = hasFaces ? normalize(group.map { $0.faceQuality ?? 0 }, minSpread: 0.05) : nil

        let hasAnimals = group.contains { $0.animalScore != nil }
        let animals = hasAnimals ? normalize(group.map { $0.animalScore ?? 0 }, minSpread: 0.1) : nil

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
            if let animals {
                total += Weight.animals * animals[i]
                weights += Weight.animals
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
                animals: animals?[i],
                aesthetics: aesthetics?[i]
            )
            var reasons: [String] = []
            if photo.asset.isFavorite { reasons.append("Favorited") }
            if let faces, isTop(faces, i) { reasons.append("Best faces") }
            if let animals, isTop(animals, i) { reasons.append("Best pet shot") }
            if isTop(sharpness, i) { reasons.append("Sharpest") }
            if let aesthetics, isTop(aesthetics, i) { reasons.append("Best composition") }
            if isTop(exposure, i) { reasons.append("Best exposure") }

            scored.append(ScoredPhoto(asset: photo.asset, score: score, breakdown: breakdown, reasons: reasons))
        }

        // Exact ties go to the later shot: usually the one taken after fixing the pose.
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.date > $1.date }

        var kept: Set<String> = [scored[0].id]

        let isCloseCall = scored[0].score - scored[1].score < options.closeCallMargin
        if isCloseCall {
            kept.insert(scored[1].id)
        }

        if options.keepBestOfEachOrientation,
           let index = scored.firstIndex(where: { $0.isLandscape != scored[0].isLandscape }) {
            kept.insert(scored[index].id)
            scored[index].reasons.insert(scored[index].isLandscape ? "Best landscape" : "Best portrait", at: 0)
        }

        return PhotoGroup(photos: scored, keptIDs: kept, isCloseCall: isCloseCall)
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
