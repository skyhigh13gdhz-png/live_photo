import PhotosUI
import SwiftUI

@MainActor
final class ComposerModel: ObservableObject {
    @Published var images: [UIImage] = []
    @Published var selectedIndex = 0
    @Published var configuration = MotionConfiguration()
    @Published var status = ""
    @Published var isWorking = false
    @Published var didSucceed = false

    var image: UIImage? {
        images.indices.contains(selectedIndex) ? images[selectedIndex] : images.first
    }

    func load(_ items: [PhotosPickerItem]) async {
        isWorking = true
        didSucceed = false
        status = "正在读取照片…"
        defer { isWorking = false }

        do {
            var loadedImages: [UIImage] = []
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let loadedImage = UIImage(data: data) else {
                    throw LivePhotoError.imageRead
                }
                loadedImages.append(loadedImage)
            }
            images = loadedImages
            selectedIndex = 0
            status = ""
        } catch {
            status = "读取失败：\(error.localizedDescription)"
        }
    }

    func generateAndSave() async {
        guard !images.isEmpty else { return }
        isWorking = true
        didSucceed = false
        var succeeded = 0
        var failed = 0
        var lastFailure = ""
        let total = images.count

        for (index, image) in images.enumerated() {
            do {
                let generator = LivePhotoGenerator()
                let resources = try await generator.generate(
                    from: image,
                    configuration: configuration
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.status = "正在生成 \(index + 1)/\(total) · \(Int(progress * 100))%"
                    }
                }
                status = "正在保存 \(index + 1)/\(total)…"
                try await PhotoLibrarySaver.save(resources)
                succeeded += 1
            } catch {
                failed += 1
                lastFailure = error.localizedDescription
            }
        }

        didSucceed = succeeded > 0 && failed == 0
        status = failed == 0
            ? "已保存 \(succeeded) 张 Live Photo。"
            : "完成：成功 \(succeeded) 张，失败 \(failed) 张。\(lastFailure)"
        isWorking = false
    }
}
