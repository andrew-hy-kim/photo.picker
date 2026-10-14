import Foundation
import Observation
import Photos
import UIKit

@MainActor
@Observable
final class ScanModel {
    enum Phase: Equatable {
        case idle
        case scanning(done: Int, total: Int)
        case grouping
        case results
        case failed(String)
    }

    var phase: Phase = .idle
    var groups: [PhotoGroup] = []

    private var scanTask: Task<Void, Never>?

    /// Photos the user is about to delete across all groups.
    var discarded: [PHAsset] { groups.flatMap(\.discarded) }

    func startScan(from start: Date, to end: Date, options: GroupingOptions, ranking: RankingOptions) {
        scanTask?.cancel()
        scanTask = Task { await scan(from: start, to: end, options: options, ranking: ranking) }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .idle
    }

    func reset() {
        groups = []
        phase = .idle
    }

    func deleteDiscarded() async {
        let assets = discarded
        guard !assets.isEmpty else { return }
        do {
            try await PhotoLibrary.delete(assets)
            let deletedIDs = Set(assets.map(\.localIdentifier))
            groups = groups.compactMap { group in
                var group = group
                group.photos.removeAll { deletedIDs.contains($0.id) }
                return group.photos.count > 1 ? group : nil
            }
        } catch {
            // The user tapping "Don't Allow" on the system prompt also lands here; nothing to do.
        }
    }

    private func scan(from start: Date, to end: Date, options: GroupingOptions, ranking: RankingOptions) async {
        let status = await PhotoLibrary.requestAccess()
        guard status == .authorized || status == .limited else {
            phase = .failed("Photo Picker needs access to your photos. You can allow it in Settings › Privacy & Security › Photos.")
            return
        }

        let assets = await Task.detached { PhotoLibrary.fetchPhotos(from: start, to: end) }.value
        guard !assets.isEmpty else {
            phase = .failed("No photos found in that date range.")
            return
        }

        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        phase = .scanning(done: 0, total: assets.count)
        var analyses = [PhotoAnalysis?](repeating: nil, count: assets.count)
        var done = 0

        await withTaskGroup(of: (Int, PhotoAnalysis?).self) { taskGroup in
            // Analyse a few photos at a time: fast, without loading the whole library into memory.
            let concurrency = 4
            var next = 0
            while next < min(concurrency, assets.count) {
                let index = next, asset = assets[index]
                taskGroup.addTask { (index, await PhotoAnalyzer.analyze(asset)) }
                next += 1
            }
            while let result = await taskGroup.next() {
                let (index, analysis) = result
                if Task.isCancelled {
                    taskGroup.cancelAll()
                    return
                }
                analyses[index] = analysis
                done += 1
                phase = .scanning(done: done, total: assets.count)
                if next < assets.count {
                    let index = next, asset = assets[index]
                    taskGroup.addTask { (index, await PhotoAnalyzer.analyze(asset)) }
                    next += 1
                }
            }
        }
        guard !Task.isCancelled else { return }

        phase = .grouping
        let found = analyses.compactMap { $0 }
        groups = await Task.detached {
            SimilarityGrouper.group(found, options: options).map { PhotoRanker.rank($0, options: ranking) }
        }.value
        phase = .results
    }
}
