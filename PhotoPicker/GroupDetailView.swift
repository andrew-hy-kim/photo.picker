import SwiftUI

/// Full-screen, swipeable comparison of one group.
struct GroupDetailView: View {
    @Binding var group: PhotoGroup
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(Array(group.photos.enumerated()), id: \.element.id) { rank, photo in
                    page(photo, rank: rank)
                        .tag(Optional(photo.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            GroupStrip(group: $group)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .navigationTitle("Compare \(group.photos.count)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selection = selection ?? group.best.id }
    }

    private func page(_ photo: ScoredPhoto, rank: Int) -> some View {
        VStack(spacing: 12) {
            AssetImage(asset: photo.asset, pixelSize: 1600, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(rank == 0 ? "★ Best pick" : "#\(rank + 1)")
                        .font(.headline)
                    Spacer()
                    Text("Score \(Int((photo.score * 100).rounded()))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if !photo.reasons.isEmpty {
                    Text(photo.reasons.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                MetricRow(name: "Sharpness", value: photo.breakdown.sharpness)
                if let faces = photo.breakdown.faces {
                    MetricRow(name: "Faces", value: faces)
                }
                if let animals = photo.breakdown.animals {
                    MetricRow(name: "Pet framing", value: animals)
                }
                if let aesthetics = photo.breakdown.aesthetics {
                    MetricRow(name: "Composition", value: aesthetics)
                }
                MetricRow(name: "Exposure", value: photo.breakdown.exposure)

                HStack {
                    Toggle("Keep", isOn: Binding(
                        get: { group.isKept(photo) },
                        set: { _ in group.toggleKeep(photo) }
                    ))
                    .fixedSize()
                    Spacer()
                    Button("Keep only this") { group.keepOnly(photo) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 36)
        }
    }
}

private struct MetricRow: View {
    let name: String
    let value: Double

    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
                .frame(width: 90, alignment: .leading)
            ProgressView(value: value)
        }
    }
}
