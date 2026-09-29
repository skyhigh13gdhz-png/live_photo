import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct StablePushRenderer {
    static let outputSize = CGSize(width: 1080, height: 1920)

    let source: CIImage
    let configuration: MotionConfiguration
    let outputSize: CGSize

    init(image: UIImage, configuration: MotionConfiguration = .init(), outputSize: CGSize? = nil) throws {
        guard let source = CIImage(image: image, options: [.applyOrientationProperty: true]) else {
            throw LivePhotoError.imageRead
        }
        let normalized = source.transformed(
            by: CGAffineTransform(translationX: -source.extent.origin.x, y: -source.extent.origin.y)
        )
        let whiteBackground = CIImage(color: CIColor.white).cropped(to: normalized.extent)
        self.source = normalized.composited(over: whiteBackground)
        self.configuration = configuration
        self.outputSize = outputSize ?? configuration.canvasRatio.outputSize(for: normalized.extent.size)
    }

    func frame(progress: Double) -> CIImage {
        let bounds = CGRect(origin: .zero, size: outputSize)
        let sourceSize = source.extent.size
        let smooth = Self.smooth(progress)
        let amount = configuration.appliesMotion ? configuration.motionIntensity : 0
        let fillScale = max(outputSize.width / sourceSize.width, outputSize.height / sourceSize.height)
        let (zoom, travel) = motion(progress: smooth, amount: amount)
        let totalScale = fillScale * zoom * shapeSafetyScale()
        let scaledSize = CGSize(width: sourceSize.width * totalScale, height: sourceSize.height * totalScale)
        let translation = CGAffineTransform(
            translationX: (outputSize.width - scaledSize.width) / 2
                + travel.x * max(0, scaledSize.width - outputSize.width) / 2,
            y: (outputSize.height - scaledSize.height) / 2
                + travel.y * max(0, scaledSize.height - outputSize.height) / 2
        )
        let positioned = source
            .transformed(by: CGAffineTransform(scaleX: totalScale, y: totalScale))
            .transformed(by: translation)
        return applyShape(to: positioned, progress: progress, bounds: bounds).cropped(to: bounds)
    }

    private func motion(progress: Double, amount: Double) -> (Double, CGPoint) {
        guard configuration.appliesMotion else { return (1, .zero) }
        switch configuration.motionEffect {
        case .zoomIn: return (1 + amount * progress, .zero)
        case .zoomOut: return (1 + amount * (1 - progress), .zero)
        case .panLeft: return (1 + amount, CGPoint(x: 1 - 2 * progress, y: 0))
        case .panRight: return (1 + amount, CGPoint(x: -1 + 2 * progress, y: 0))
        case .panUp: return (1 + amount, CGPoint(x: 0, y: -1 + 2 * progress))
        case .panDown: return (1 + amount, CGPoint(x: 0, y: 1 - 2 * progress))
        case .diagonal: return (1 + amount, CGPoint(x: -1 + 2 * progress, y: -1 + 2 * progress))
        }
    }

    private func applyShape(to image: CIImage, progress: Double, bounds: CGRect) -> CIImage {
        guard configuration.appliesShape else { return image }
        let phase = sin(.pi * min(max(progress, 0), 1))
        let strength = configuration.shapeIntensity
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        switch configuration.shapeEffect {
        case .verticalStretch:
            return image.transformed(by: centered(
                CGAffineTransform(scaleX: 1, y: 1 + 0.005 * strength * phase), at: center
            ))
        case .horizontalStretch:
            return image.transformed(by: centered(
                CGAffineTransform(scaleX: 1 + 0.005 * strength * phase, y: 1), at: center
            ))
        case .shear:
            return image.transformed(by: centered(
                CGAffineTransform(a: 1, b: 0, c: 0.008 * strength * phase, d: 1, tx: 0, ty: 0), at: center
            ))
        case .roll:
            return image.transformed(by: centered(
                CGAffineTransform(rotationAngle: 0.25 * .pi / 180 * strength * phase), at: center
            ))
        case .lensBreathing:
            let filter = CIFilter.bumpDistortion()
            filter.inputImage = image
            filter.center = center
            filter.radius = Float(max(outputSize.width, outputSize.height) * 0.72)
            filter.scale = Float(0.012 * strength * phase)
            return filter.outputImage ?? image
        }
    }

    private func centered(_ transform: CGAffineTransform, at center: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y)
            .concatenating(transform)
            .concatenating(CGAffineTransform(translationX: -center.x, y: -center.y))
    }

    private func shapeSafetyScale() -> Double {
        guard configuration.appliesShape else { return 1 }
        switch configuration.shapeEffect {
        case .shear: return 1 + 0.012 * configuration.shapeIntensity
        case .roll: return 1 + 0.008 * configuration.shapeIntensity
        case .lensBreathing: return 1 + 0.035 * configuration.shapeIntensity
        default: return 1.005
        }
    }

    static func smooth(_ progress: Double) -> Double {
        let value = min(max(progress, 0), 1)
        return value * value * (3 - 2 * value)
    }
}
