@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import UIKit

actor LivePhotoGenerator {
    private let width = 1080
    private let height = 1920
    private let fps: Int32 = 30
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func generate(
        from image: UIImage,
        configuration: MotionConfiguration = .init(),
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> LivePhotoResources {
        let renderer = try StablePushRenderer(image: image, configuration: configuration)
        let frameCount = max(2, Int((configuration.duration * Double(fps)).rounded()))
        let identifier = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LivePhoto-\(identifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let photoURL = directory.appendingPathComponent("IMG-\(identifier).jpg")
        let movieURL = directory.appendingPathComponent("IMG-\(identifier).mov")
        do {
            try await writeMovie(
                renderer: renderer,
                frameCount: frameCount,
                identifier: identifier,
                outputURL: movieURL,
                progress: progress
            )
            try writePhoto(
                image: renderer.frame(progress: 0.5),
                identifier: identifier,
                outputURL: photoURL
            )
            return LivePhotoResources(
                photoURL: photoURL,
                movieURL: movieURL,
                identifier: identifier
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func writeMovie(
        renderer: StablePushRenderer,
        frameCount: Int,
        identifier: String,
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        writer.metadata = [contentIdentifier(identifier)]

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
        )
        guard writer.canAdd(videoInput) else { throw LivePhotoError.writerSetup }
        writer.add(videoInput)

        let (metadataInput, metadataAdaptor) = try stillImageMetadataInput()
        guard writer.canAdd(metadataInput) else { throw LivePhotoError.writerSetup }
        writer.add(metadataInput)

        guard writer.startWriting() else {
            throw LivePhotoError.writerFailed(writer.error?.localizedDescription ?? "无法开始")
        }
        writer.startSession(atSourceTime: .zero)

        let marker = AVMutableMetadataItem()
        marker.keySpace = .quickTimeMetadata
        marker.key = "com.apple.quicktime.still-image-time" as NSString
        marker.value = NSNumber(value: Int8(-1))
        marker.dataType = kCMMetadataBaseDataType_SInt8 as String
        let midpoint = CMTime(value: Int64(frameCount / 2), timescale: fps)
        let frameDuration = CMTime(value: 1, timescale: fps)
        guard metadataAdaptor.append(
            AVTimedMetadataGroup(
                items: [marker],
                timeRange: CMTimeRange(start: midpoint, duration: frameDuration)
            )
        ) else {
            throw LivePhotoError.metadata
        }
        metadataInput.markAsFinished()

        guard let pool = adaptor.pixelBufferPool else {
            throw LivePhotoError.pixelBuffer
        }
        let context = CIContext(options: [.cacheIntermediates: false])
        let renderBounds = CGRect(x: 0, y: 0, width: width, height: height)

        for index in 0..<frameCount {
            try Task.checkCancellation()
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }

            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
                  let buffer = optionalBuffer else {
                throw LivePhotoError.pixelBuffer
            }
            let u = Double(index) / Double(frameCount - 1)
            context.render(
                renderer.frame(progress: u),
                to: buffer,
                bounds: renderBounds,
                colorSpace: colorSpace
            )
            let time = CMTime(value: Int64(index), timescale: fps)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw LivePhotoError.writerFailed(writer.error?.localizedDescription ?? "写入视频帧失败")
            }
            progress(Double(index + 1) / Double(frameCount))
        }

        videoInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw LivePhotoError.writerFailed(writer.error?.localizedDescription ?? "未知错误")
        }
    }

    private func writePhoto(image: CIImage, identifier: String, outputURL: URL) throws {
        let context = CIContext(options: [.cacheIntermediates: false])
        let bounds = CGRect(origin: .zero, size: StablePushRenderer.outputSize)
        guard let cgImage = context.createCGImage(image, from: bounds),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                "public.jpeg" as CFString,
                1,
                nil
              ) else {
            throw LivePhotoError.imageWrite
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier],
            kCGImagePropertyOrientation: 1
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoError.imageWrite
        }
    }

    private func contentIdentifier(_ identifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = "com.apple.quicktime.content.identifier" as NSString
        item.value = identifier as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }

    private func stillImageMetadataInput() throws
        -> (AVAssetWriterInput, AVAssetWriterInputMetadataAdaptor) {
        let specification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                kCMMetadataBaseDataType_SInt8
        ]
        var description: CMFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray,
            formatDescriptionOut: &description
        )
        guard status == noErr, let description else {
            throw LivePhotoError.metadata
        }
        let input = AVAssetWriterInput(
            mediaType: .metadata,
            outputSettings: nil,
            sourceFormatHint: description
        )
        return (input, AVAssetWriterInputMetadataAdaptor(assetWriterInput: input))
    }
}
