import Photos
import SwiftUI

struct ResultsView: View {
    @Bindable var model: ScanModel
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if model.groups.isEmpty {
                ContentUnavailableView {
                    Label("All clear", systemImage: "checkmark.circle")
                } description: {
                    Text("No similar photos left to sort through.")
                } actions: {
                    Button("New scan") { model.reset() }
                }
            } else {
                list
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New scan") { model.reset() }
            }
        }
        .navigationDestination(for: PhotoGroup.ID.self) { id in
            if let index = model.groups.firstIndex(where: { $0.id == id }) {
                GroupDetailView(group: $model.groups[index])
            }
        }
    }

    private var list: some View {
        List {
            Section {
                Text("Found \(model.groups.count) sets of similar photos. The ★ pick is kept; tap any photo to keep or discard it. When two shots are too close to call, both are kept so you can choose.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach($model.groups) { $group in
                Section {
                    GroupStrip(group: $group)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    if group.isCloseCall {
                        Label("Too close to call — both kept, you pick", systemImage: "equal.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    HStack {
                        if let date = group.date {
                            Text(date, format: .dateTime.month().day().hour().minute())
                        }
                        Text("· \(group.photos.count) photos")
                        Spacer()
                        NavigationLink(value: group.id) {
                            Text("Compare")
                        }
                        .font(.caption.bold())
                        .textCase(nil)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            let count = model.discarded.count
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete \(count) extra photo\(count == 1 ? "" : "s")", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(count == 0)
            .padding()
            .background(.bar)
        }
        .confirmationDialog(
            "Delete \(model.discarded.count) photos?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await model.deleteDiscarded() }
            }
        } message: {
            Text("They'll move to Recently Deleted, where you can recover them for 30 days.")
        }
    }
}

/// Horizontal strip of a group's photos. Tap to toggle keep/discard.
struct GroupStrip: View {
    @Binding var group: PhotoGroup

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(group.photos) { photo in
                    Button {
                        group.toggleKeep(photo)
                    } label: {
                        Thumbnail(photo: photo, isBest: photo.id == group.best.id, isKept: group.isKept(photo))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct Thumbnail: View {
    let photo: ScoredPhoto
    let isBest: Bool
    let isKept: Bool

    var body: some View {
        AssetImage(asset: photo.asset, pixelSize: 300)
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isKept ? Color.accentColor : .clear, lineWidth: 3)
            }
            .overlay(alignment: .topLeading) {
                if isBest {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .padding(5)
                        .background(Color.yellow, in: Circle())
                        .foregroundStyle(.black)
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: isKept ? "checkmark.circle.fill" : "trash.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, isKept ? Color.accentColor : .red)
                    .padding(5)
            }
            .opacity(isKept ? 1 : 0.55)
            .accessibilityLabel(isKept ? "Kept photo" : "Photo marked for deletion")
    }
}

struct AssetImage: View {
    let asset: PHAsset
    let pixelSize: CGFloat
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .task(id: asset.localIdentifier) {
            image = await PhotoLibrary.image(for: asset, maxDimension: pixelSize)
        }
    }
}
