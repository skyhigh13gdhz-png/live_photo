import XCTest
import UIKit
@testable import LivePhotoApp

final class MotionCurveTests: XCTestCase {
    func testStablePushEndpoints() throws {
        let smoothAtStart = 0.0 * 0.0 * (3 - 2 * 0.0)
        let smoothAtEnd = 1.0 * 1.0 * (3 - 2 * 1.0)
        XCTAssertEqual(1 + 0.075 * smoothAtStart, 1, accuracy: 0.000_001)
        XCTAssertEqual(1 + 0.075 * smoothAtEnd, 1.075, accuracy: 0.000_001)
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
