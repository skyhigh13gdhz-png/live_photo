import PhotosUI
import SwiftUI

@MainActor
final class ComposerModel: ObservableObject {
    @Published var image: UIImage?
    @Published var status = ""
    @Published var isWorking = false
    @Published var didSucceed = false

    func load(_ item: PhotosPickerItem) async {
        isWorking = true
        didSucceed = false
        status = "正在读取照片…"
        defer { isWorking = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let loadedImage = UIImage(data: data) else {
                throw LivePhotoError.imageRead
            }
            image = loadedImage
            status = ""
        } catch {
            status = "读取失败：\(error.localizedDescription)"
        }
    }

    func generateAndSave() async {
        guard let image else { return }
        isWorking = true
        didSucceed = false
        status = "正在渲染 0%"

        do {
            let generator = LivePhotoGenerator()
            let resources = try await generator.generate(from: image) { [weak self] progress in
                Task { @MainActor in
                    self?.status = "正在渲染 \(Int(progress * 100))%"
                }
            }
            status = "正在保存到照片…"
            try await PhotoLibrarySaver.save(resources)
            didSucceed = true
            status = "已保存到系统照片，可在“照片”中长按验收。"
        } catch {
            status = "生成失败：\(error.localizedDescription)"
        }

        isWorking = false
    }
}
