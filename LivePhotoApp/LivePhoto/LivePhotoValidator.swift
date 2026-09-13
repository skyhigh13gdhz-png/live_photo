@preconcurrency import AVFoundation
import ImageIO

enum LivePhotoValidator {
    static func validate(_ resources: LivePhotoResources) async throws {
        try validateFiles(resources)
        try validatePhoto(resources)
        try await validateMovie(resources)
    }

    private static func validateFiles(_ resources: LivePhotoResources) throws {
        for url in [resources.photoURL, resources.movieURL] {
            guard FileManager.default.fileExists(atPath: url.path),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value > 0 else {
                throw LivePhotoError.validation("\(url.lastPathComponent) 不存在或为空")
            }
        }
    }

    private static func validatePhoto(_ resources: LivePhotoResources) throws {
        guard let source = CGImageSourceCreateWithURL(resources.photoURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue == 1080,
              height.intValue == 1920 else {
            throw LivePhotoError.validation("JPEG 尺寸不是 1080 × 1920")
        }

        guard let maker = properties[kCGImagePropertyMakerAppleDictionary]
                as? [String: Any],
              let identifier = maker["17"] as? String,
              identifier == resources.identifier else {
            throw LivePhotoError.validation("JPEG 配对标识缺失或不一致")
        }
    }

    private static func validateMovie(_ resources: LivePhotoResources) async throws {
        let asset = AVURLAsset(url: resources.movieURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw LivePhotoError.validation("MOV 缺少视频轨")
        }

        let size = try await videoTrack.load(.naturalSize)
        guard abs(size.width) == 1080, abs(size.height) == 1920 else {
            throw LivePhotoError.validation("MOV 尺寸不是 1080 × 1920")
        }

        let metadata = try await asset.load(.metadata)
        var movieIdentifier: String?
        for item in metadata where
            (item.key as? String) == "com.apple.quicktime.content.identifier" {
            movieIdentifier = try await item.load(.stringValue)
            break
        }
        guard movieIdentifier == resources.identifier else {
            throw LivePhotoError.validation("MOV 配对标识缺失或不一致")
        }

        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        guard !metadataTracks.isEmpty else {
            throw LivePhotoError.validation("MOV 缺少静态帧时间元数据轨")
        }
    }
}
