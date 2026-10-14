import Photos
import UIKit

enum PhotoLibrary {
    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Still photos (no screenshots) taken in the given range, oldest first.
    static func fetchPhotos(from start: Date, to end: Date) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue, start as NSDate, end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            if !asset.mediaSubtypes.contains(.photoScreenshot) {
                assets.append(asset)
            }
        }
        return assets
    }

    /// Loads an image whose longest side is about `maxDimension` pixels.
    /// `exact` gives consistently sized images, which keeps sharpness scores comparable.
    static func image(for asset: PHAsset, maxDimension: CGFloat, exact: Bool = false) async -> UIImage? {
        let options = PHImageRequestOptions()
        // highQualityFormat guarantees the handler is called exactly once.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = exact ? .exact : .fast
        options.isNetworkAccessAllowed = true

        let size = CGSize(width: maxDimension, height: maxDimension)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: size, contentMode: .aspectFit, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Moves the assets to "Recently Deleted". iOS shows its own confirmation prompt.
    static func delete(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }
}
