import Photos

enum PhotoLibrarySaver {
    static func save(_ resources: LivePhotoResources) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw LivePhotoError.photosDenied
        }

        let resourceTypes = [
            NSNumber(value: PHAssetResourceType.photo.rawValue),
            NSNumber(value: PHAssetResourceType.pairedVideo.rawValue)
        ]
        guard PHAssetCreationRequest.supportsAssetResourceTypes(resourceTypes) else {
            throw LivePhotoError.photosSave("系统不支持当前 Live Photo 资源组合")
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()

                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.originalFilename = resources.photoURL.lastPathComponent
                request.addResource(
                    with: .photo,
                    fileURL: resources.photoURL,
                    options: photoOptions
                )

                let movieOptions = PHAssetResourceCreationOptions()
                movieOptions.originalFilename = resources.movieURL.lastPathComponent
                movieOptions.shouldMoveFile = true
                request.addResource(
                    with: .pairedVideo,
                    fileURL: resources.movieURL,
                    options: movieOptions
                )
            }
            try? FileManager.default.removeItem(
                at: resources.photoURL.deletingLastPathComponent()
            )
        } catch {
            throw LivePhotoError.photosSave(error.localizedDescription)
        }
    }
}
