import XCTest
import UIKit
@testable import LivePhotoApp

final class MotionCurveTests: XCTestCase {
    func testStablePushEndpoints() throws {
        let smoothAtStart = StablePushRenderer.smooth(0)
        let smoothAtEnd = StablePushRenderer.smooth(1)
        XCTAssertEqual(1 + 0.075 * smoothAtStart, 1, accuracy: 0.000_001)
        XCTAssertEqual(1 + 0.075 * smoothAtEnd, 1.075, accuracy: 0.000_001)
    }

    func testMotionCurveClampsAndHasSmoothMidpoint() {
        XCTAssertEqual(StablePushRenderer.smooth(-1), 0)
        XCTAssertEqual(StablePushRenderer.smooth(0.5), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(StablePushRenderer.smooth(2), 1)
    }

    func testRandomScopeResolvesToRequestedEffectType() {
        var configuration = MotionConfiguration()
        for scope in RandomScope.allCases {
            configuration.randomScope = scope
            let resolved = configuration.resolvedForExport()
            switch scope {
            case .combined: XCTAssertEqual(resolved.mode, .combined)
            case .motion: XCTAssertEqual(resolved.mode, .motion)
            case .shape: XCTAssertEqual(resolved.mode, .shape)
            }
        }
    }

    func testEveryMotionAndShapeCombinationKeepsOutputOpaque() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900))
            .image { context in
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
            }

        let outputSize = CGSize(width: 108, height: 192)
        let context = CIContext(options: [.cacheIntermediates: false])
        for motion in MotionEffect.allCases {
            for shape in ShapeEffect.allCases {
                var configuration = MotionConfiguration()
                configuration.mode = .combined
                configuration.motionEffect = motion
                configuration.shapeEffect = shape
                configuration.motionIntensity = MotionConfiguration.motionIntensityRange.upperBound
                configuration.shapeIntensity = MotionConfiguration.shapeIntensityRange.upperBound
                let renderer = try StablePushRenderer(
                    image: image,
                    configuration: configuration,
                    outputSize: outputSize
                )
                for progress in [0.0, 0.5, 1.0] {
                    let frame = renderer.frame(progress: progress)
                    XCTAssertEqual(frame.extent, CGRect(origin: .zero, size: outputSize))
                    var pixels = [UInt8](repeating: 0, count: Int(outputSize.width * outputSize.height * 4))
                    context.render(
                        frame,
                        toBitmap: &pixels,
                        rowBytes: Int(outputSize.width) * 4,
                        bounds: frame.extent,
                        format: .RGBA8,
                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
                    )
                    let width = Int(outputSize.width)
                    let height = Int(outputSize.height)
                    let cornerOffsets = [0, (width - 1) * 4, (height - 1) * width * 4, ((height * width) - 1) * 4]
                    XCTAssertTrue(
                        cornerOffsets.allSatisfy { offset in
                            pixels[offset] >= 200
                                && pixels[offset + 1] >= 70
                                && pixels[offset + 2] <= 60
                                && pixels[offset + 3] >= 250
                        },
                        "\(motion.title) + \(shape.title) 在 \(progress) 时露出非素材背景"
                    )
                }
            }
        }
    }

    func testGeneratedPairPassesValidation() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1600))
            .image { context in
                UIColor.systemIndigo.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 900, height: 1600))
                UIColor.white.setFill()
                context.fill(CGRect(x: 200, y: 300, width: 500, height: 1000))
            }
        let resources = try await LivePhotoGenerator().generate(from: image) { _ in }
        defer {
            try? FileManager.default.removeItem(
                at: resources.photoURL.deletingLastPathComponent()
            )
        }

        try await LivePhotoValidator.validate(resources)
    }
}
