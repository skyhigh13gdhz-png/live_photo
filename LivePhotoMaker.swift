import Foundation
import AVFoundation
import ImageIO
import Photos

enum MakerError: LocalizedError {
    case usage
    case imageRead
    case imageWrite
    case noVideoTrack
    case readerSetup
    case writerSetup
    case conversion(String)
    case photosDenied
    case photosImport(String)

    var errorDescription: String? {
        switch self {
        case .usage: return "用法：LivePhotoMaker <静态图> <MP4/MOV> <输出目录> [--import]"
        case .imageRead: return "无法读取静态图片。"
        case .imageWrite: return "无法写入带配对标识的 JPEG。"
        case .noVideoTrack: return "视频中没有可用的视频轨道。"
        case .readerSetup: return "无法创建视频读取器。"
        case .writerSetup: return "无法创建 Live Photo MOV 写入器。"
        case .conversion(let message): return "MOV 转换失败：\(message)"
        case .photosDenied: return "没有获得照片图库权限。"
        case .photosImport(let message): return "导入照片图库失败：\(message)"
        }
    }
}

func writePairedJPEG(sourceURL: URL, outputURL: URL, assetID: String) throws {
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw MakerError.imageRead
    }

    var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    var makerApple = (properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]) ?? [:]
    makerApple["17"] = assetID
    properties[kCGImagePropertyMakerAppleDictionary] = makerApple
    properties[kCGImagePropertyOrientation] = 1

    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        "public.jpeg" as CFString,
        1,
        nil
    ) else { throw MakerError.imageWrite }

    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw MakerError.imageWrite }
}

func contentIdentifierMetadata(_ assetID: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.keySpace = .quickTimeMetadata
    item.key = "com.apple.quicktime.content.identifier" as NSString
    item.value = assetID as NSString
    item.dataType = kCMMetadataBaseDataType_UTF8 as String
    return item
}

func stillImageMetadataInput() throws -> (AVAssetWriterInput, AVAssetWriterInputMetadataAdaptor) {
    let specification: [String: Any] = [
        kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
            "mdta/com.apple.quicktime.still-image-time",
        kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
            kCMMetadataBaseDataType_SInt8
    ]
    var formatDescription: CMFormatDescription?
    let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
        allocator: kCFAllocatorDefault,
        metadataType: kCMMetadataFormatType_Boxed,
        metadataSpecifications: [specification] as CFArray,
        formatDescriptionOut: &formatDescription
    )
    guard status == noErr, let description = formatDescription else {
        throw MakerError.writerSetup
    }
    let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
    let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
    return (input, adaptor)
}

func writePairedMovie(sourceURL: URL, outputURL: URL, assetID: String) throws {
    let asset = AVURLAsset(url: sourceURL)
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
        throw MakerError.noVideoTrack
    }

    let reader: AVAssetReader
    let writer: AVAssetWriter
    do {
        reader = try AVAssetReader(asset: asset)
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    } catch {
        throw MakerError.conversion(error.localizedDescription)
    }

    let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
    readerOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(readerOutput) else { throw MakerError.readerSetup }
    reader.add(readerOutput)

    // Passthrough copy: the compressed format is supplied by incoming sample buffers.
    // Supplying formatDescriptions here breaks compilation with newer Swift SDKs,
    // which reject conditional casts involving Core Foundation types.
    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
    writerInput.transform = videoTrack.preferredTransform
    guard writer.canAdd(writerInput) else { throw MakerError.writerSetup }
    writer.add(writerInput)

    let (metadataInput, metadataAdaptor) = try stillImageMetadataInput()
    guard writer.canAdd(metadataInput) else { throw MakerError.writerSetup }
    writer.add(metadataInput)
    writer.metadata = [contentIdentifierMetadata(assetID)]

    guard writer.startWriting(), reader.startReading() else {
        throw MakerError.conversion(writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "无法开始读写")
    }
    writer.startSession(atSourceTime: .zero)

    let duration = asset.duration
    let midpoint = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)
    let marker = AVMutableMetadataItem()
    marker.keySpace = .quickTimeMetadata
    marker.key = "com.apple.quicktime.still-image-time" as NSString
    marker.value = NSNumber(value: Int8(-1))
    marker.dataType = kCMMetadataBaseDataType_SInt8 as String
    metadataAdaptor.append(AVTimedMetadataGroup(items: [marker], timeRange: CMTimeRange(start: midpoint, duration: CMTime(value: 1, timescale: 30))))
    metadataInput.markAsFinished()

    let semaphore = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "live-photo.video-copy")
    writerInput.requestMediaDataWhenReady(on: queue) {
        while writerInput.isReadyForMoreMediaData {
            if let sample = readerOutput.copyNextSampleBuffer() {
                if !writerInput.append(sample) {
                    reader.cancelReading()
                    writerInput.markAsFinished()
                    semaphore.signal()
                    return
                }
            } else {
                writerInput.markAsFinished()
                semaphore.signal()
                return
            }
        }
    }
    semaphore.wait()

    let finishSemaphore = DispatchSemaphore(value: 0)
    writer.finishWriting { finishSemaphore.signal() }
    finishSemaphore.wait()

    guard writer.status == .completed, reader.status == .completed else {
        throw MakerError.conversion(writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "未知错误")
    }
}

func importIntoPhotos(photoURL: URL, movieURL: URL) throws {
    let authorization = DispatchSemaphore(value: 0)
    var status: PHAuthorizationStatus = .notDetermined
    PHPhotoLibrary.requestAuthorization(for: .readWrite) {
        status = $0
        authorization.signal()
    }
    authorization.wait()
    guard status == .authorized || status == .limited else { throw MakerError.photosDenied }

    let completion = DispatchSemaphore(value: 0)
    var importError: Error?
    var imported = false
    PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, fileURL: photoURL, options: nil)
        request.addResource(with: .pairedVideo, fileURL: movieURL, options: nil)
    }) { success, error in
        imported = success
        importError = error
        completion.signal()
    }
    completion.wait()
    guard imported else {
        throw MakerError.photosImport(importError?.localizedDescription ?? "未知错误")
    }
}

do {
    guard CommandLine.arguments.count >= 4 else { throw MakerError.usage }
    let sourcePhoto = URL(fileURLWithPath: CommandLine.arguments[1])
    let sourceMovie = URL(fileURLWithPath: CommandLine.arguments[2])
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    let shouldImport = CommandLine.arguments.contains("--import")

    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let base = sourcePhoto.deletingPathExtension().lastPathComponent
    let assetID = UUID().uuidString
    let photoOutput = outputDirectory.appendingPathComponent("\(base)-LIVE.jpg")
    let movieOutput = outputDirectory.appendingPathComponent("\(base)-LIVE.mov")
    try? FileManager.default.removeItem(at: photoOutput)
    try? FileManager.default.removeItem(at: movieOutput)

    try writePairedJPEG(sourceURL: sourcePhoto, outputURL: photoOutput, assetID: assetID)
    try writePairedMovie(sourceURL: sourceMovie, outputURL: movieOutput, assetID: assetID)
    if shouldImport {
        try importIntoPhotos(photoURL: photoOutput, movieURL: movieOutput)
    }

    print("PHOTO=\(photoOutput.path)")
    print("MOVIE=\(movieOutput.path)")
    print("IMPORTED=\(shouldImport ? 1 : 0)")
} catch {
    fputs("ERROR=\(error.localizedDescription)\n", stderr)
    exit(1)
}
