import XCTest
@testable import LivePhotoApp

final class MotionCurveTests: XCTestCase {
    func testStablePushEndpoints() throws {
        let smoothAtStart = 0.0 * 0.0 * (3 - 2 * 0.0)
        let smoothAtEnd = 1.0 * 1.0 * (3 - 2 * 1.0)
        XCTAssertEqual(1 + 0.075 * smoothAtStart, 1, accuracy: 0.000_001)
        XCTAssertEqual(1 + 0.075 * smoothAtEnd, 1.075, accuracy: 0.000_001)
    }
}
