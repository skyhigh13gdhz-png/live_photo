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

    func testEveryMotionEffectKeepsOutputCovered() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900))
            .image { context in
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
            }

        for effect in MotionEffect.allCases {
            let configuration = MotionConfiguration(
                effect: effect,
                duration: 3,
                intensity: MotionConfiguration.intensityRange.upperBound
            )
            let renderer = try StablePushRenderer(image: image, configuration: configuration)
            for progress in [0.0, 0.5, 1.0] {
                XCTAssertEqual(renderer.frame(progress: progress).extent, CGRect(origin: .zero, size: StablePushRenderer.outputSize))
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
