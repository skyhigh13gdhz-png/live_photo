import CoreImage
import UIKit

struct StablePushRenderer {
    static let outputSize = CGSize(width: 1080, height: 1920)

    let source: CIImage

    init(image: UIImage) throws {
        guard let source = CIImage(image: image, options: [.applyOrientationProperty: true]) else {
            throw LivePhotoError.imageRead
        }
        self.source = source.transformed(
            by: CGAffineTransform(
                translationX: -source.extent.origin.x,
                y: -source.extent.origin.y
            )
        )
    }

    func frame(progress: Double) -> CIImage {
        let bounds = CGRect(origin: .zero, size: Self.outputSize)
        let sourceSize = source.extent.size
        let fillScale = max(
            Self.outputSize.width / sourceSize.width,
            Self.outputSize.height / sourceSize.height
        )
        let smooth = progress * progress * (3 - 2 * progress)
        let zoom = 1 + 0.075 * smooth
        let totalScale = fillScale * zoom
        let scaledSize = CGSize(
            width: sourceSize.width * totalScale,
            height: sourceSize.height * totalScale
        )
        let translation = CGAffineTransform(
            translationX: (Self.outputSize.width - scaledSize.width) / 2,
            y: (Self.outputSize.height - scaledSize.height) / 2
        )
        return source
            .transformed(by: CGAffineTransform(scaleX: totalScale, y: totalScale))
            .transformed(by: translation)
            .cropped(to: bounds)
    }
}
