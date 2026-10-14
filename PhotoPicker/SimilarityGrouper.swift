import Foundation
import Vision

struct GroupingOptions {
    /// Photos further apart in time than this are never grouped together.
    var maxTimeGap: TimeInterval = 300
    /// Max Vision feature-print distance for two photos to count as "the same shot".
    /// Lower = stricter (only near-identical frames); higher = looser.
    var similarityThreshold: Float = 0.55
}

enum SimilarityGrouper {
    /// Groups near-duplicate photos. Input must be sorted oldest first.
    /// Only groups with two or more photos are returned.
    static func group(_ photos: [PhotoAnalysis], options: GroupingOptions) -> [[PhotoAnalysis]] {
        var closed: [[PhotoAnalysis]] = []
        // Groups whose last photo is still within `maxTimeGap`. Keeping several open lets
        // interleaved shots (A, B, A, B) still land in the right groups.
        var open: [[PhotoAnalysis]] = []

        for photo in photos {
            let (stillOpen, expired) = open.partitioned { photo.date.timeIntervalSince($0.last!.date) <= options.maxTimeGap }
            closed += expired
            open = stillOpen

            var bestIndex: Int?
            var bestDistance = Float.greatestFiniteMagnitude
            for (index, group) in open.enumerated() {
                // Compare with the most recent few members; framing drifts within a burst.
                for member in group.suffix(3) {
                    if let d = distance(photo, member), d <= options.similarityThreshold, d < bestDistance {
                        bestDistance = d
                        bestIndex = index
                    }
                }
            }

            if let bestIndex {
                open[bestIndex].append(photo)
            } else {
                open.append([photo])
            }
        }
        closed += open

        return closed
            .filter { $0.count > 1 }
            .sorted { $0[0].date < $1[0].date }
    }

    private static func distance(_ a: PhotoAnalysis, _ b: PhotoAnalysis) -> Float? {
        guard let fa = a.featurePrint, let fb = b.featurePrint else { return nil }
        var d: Float = 0
        do {
            try fa.computeDistance(&d, to: fb)
            return d
        } catch {
            return nil
        }
    }
}

private extension Array {
    func partitioned(by belongsInFirst: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = [], second: [Element] = []
        for element in self {
            if belongsInFirst(element) { first.append(element) } else { second.append(element) }
        }
        return (first, second)
    }
}
