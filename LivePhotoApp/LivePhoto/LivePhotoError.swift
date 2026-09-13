import Foundation

enum LivePhotoError: LocalizedError {
    case imageRead
    case imageWrite
    case pixelBuffer
    case writerSetup
    case writerFailed(String)
    case metadata
    case validation(String)
    case photosDenied
    case photosSave(String)

    var errorDescription: String? {
        switch self {
        case .imageRead: "无法读取所选照片。"
        case .imageWrite: "无法生成 Live Photo 封面。"
        case .pixelBuffer: "无法创建视频帧缓冲区。"
        case .writerSetup: "无法配置视频编码器。"
        case .writerFailed(let reason): "视频编码失败：\(reason)"
        case .metadata: "无法写入 Live Photo 配对元数据。"
        case .validation(let reason): "Live Photo 校验失败：\(reason)"
        case .photosDenied: "没有保存到照片的权限。"
        case .photosSave(let reason): "照片保存失败：\(reason)"
        }
    }
}

struct LivePhotoResources: Sendable {
    let photoURL: URL
    let movieURL: URL
    let identifier: String
}
