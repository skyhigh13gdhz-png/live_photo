import PhotosUI
import SwiftUI

@MainActor
final class ComposerModel: ObservableObject {
    @Published var images: [UIImage] = []
    @Published var selectedIndex = 0
    @Published var configuration = MotionConfiguration()
    @Published private(set) var randomizedConfigurations: [MotionConfiguration] = []
    @Published var status = ""
    @Published var isWorking = false
    @Published var didSucceed = false

    var image: UIImage? {
        images.indices.contains(selectedIndex) ? images[selectedIndex] : images.first
    }

    var previewConfiguration: MotionConfiguration {
        guard configuration.mode == .random,
              randomizedConfigurations.indices.contains(selectedIndex) else {
            return configuration
        }
        return applyingAdvancedValues(to: randomizedConfigurations[selectedIndex])
    }

    var previewAspectRatio: CGFloat {
        guard let image else { return 9.0 / 16.0 }
        return configuration.canvasRatio.aspectRatio(for: image.size)
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
            randomizeAll()
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
                let exportConfiguration = configuration.mode == .random
                    ? configurationForRandomImage(at: index)
                    : configuration
                let resources = try await generator.generate(
                    from: image,
                    configuration: exportConfiguration
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

    func randomizeCurrent() {
        guard images.indices.contains(selectedIndex) else { return }
        ensureRandomSlots()
        randomizedConfigurations[selectedIndex] = configuration.resolvedForExport()
    }

    func randomizeAll() {
        randomizedConfigurations = images.map { _ in configuration.resolvedForExport() }
    }

    private func ensureRandomSlots() {
        guard randomizedConfigurations.count != images.count else { return }
        randomizeAll()
    }

    private func configurationForRandomImage(at index: Int) -> MotionConfiguration {
        guard randomizedConfigurations.indices.contains(index) else {
            return configuration.resolvedForExport()
        }
        return applyingAdvancedValues(to: randomizedConfigurations[index])
    }

    private func applyingAdvancedValues(to resolved: MotionConfiguration) -> MotionConfiguration {
        var result = resolved
        result.canvasRatio = configuration.canvasRatio
        result.duration = configuration.duration
        result.motionIntensity = configuration.motionIntensity
        result.shapeIntensity = configuration.shapeIntensity
        result.advancedEnabled = configuration.advancedEnabled
        return result
    }
}
