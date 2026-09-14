import CoreImage
import UIKit

struct StablePushRenderer {
    static let outputSize = CGSize(width: 1080, height: 1920)

    let source: CIImage
    let configuration: MotionConfiguration

    init(image: UIImage, configuration: MotionConfiguration = .init()) throws {
        guard let source = CIImage(image: image, options: [.applyOrientationProperty: true]) else {
            throw LivePhotoError.imageRead
        }
        self.source = source.transformed(
            by: CGAffineTransform(
                translationX: -source.extent.origin.x,
                y: -source.extent.origin.y
            )
        )
        self.configuration = configuration
    }

    func frame(progress: Double) -> CIImage {
        let bounds = CGRect(origin: .zero, size: Self.outputSize)
        let sourceSize = source.extent.size
        let fillScale = max(
            Self.outputSize.width / sourceSize.width,
            Self.outputSize.height / sourceSize.height
        )
        let smooth = Self.smooth(progress)
        let intensity = configuration.intensity
        let zoom: Double
        let travel: CGPoint

        switch configuration.effect {
        case .zoomIn:
            zoom = 1 + intensity * smooth
            travel = .zero
        case .zoomOut:
            zoom = 1 + intensity * (1 - smooth)
            travel = .zero
        case .panLeft:
            zoom = 1 + intensity
            travel = CGPoint(x: 1 - 2 * smooth, y: 0)
        case .panRight:
            zoom = 1 + intensity
            travel = CGPoint(x: -1 + 2 * smooth, y: 0)
        case .panUp:
            zoom = 1 + intensity
            travel = CGPoint(x: 0, y: -1 + 2 * smooth)
        case .panDown:
            zoom = 1 + intensity
            travel = CGPoint(x: 0, y: 1 - 2 * smooth)
        case .diagonal:
            zoom = 1 + intensity
            travel = CGPoint(x: -1 + 2 * smooth, y: -1 + 2 * smooth)
        }
        let totalScale = fillScale * zoom
        let scaledSize = CGSize(
            width: sourceSize.width * totalScale,
            height: sourceSize.height * totalScale
        )
        let translation = CGAffineTransform(
            translationX: (Self.outputSize.width - scaledSize.width) / 2
                + travel.x * max(0, scaledSize.width - Self.outputSize.width) / 2,
            y: (Self.outputSize.height - scaledSize.height) / 2
                + travel.y * max(0, scaledSize.height - Self.outputSize.height) / 2
        )
        return source
            .transformed(by: CGAffineTransform(scaleX: totalScale, y: totalScale))
            .transformed(by: translation)
            .cropped(to: bounds)
    }

    static func smooth(_ progress: Double) -> Double {
        let value = min(max(progress, 0), 1)
        return value * value * (3 - 2 * value)
    }
}
