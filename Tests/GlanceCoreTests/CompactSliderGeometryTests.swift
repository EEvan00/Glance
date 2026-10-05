import XCTest
@testable import GlanceCore

final class CompactSliderGeometryTests: XCTestCase {
    func testFarEndsStayInsideTrackAndClampDrags() {
        XCTAssertEqual(CapsuleSliderGeometry.thumbCenter(value: 0, width: 310), 7)
        XCTAssertEqual(CapsuleSliderGeometry.thumbCenter(value: 1, width: 310), 303, accuracy: 0.001)
        XCTAssertEqual(CapsuleSliderGeometry.value(at: -20, width: 310), 0)
        XCTAssertEqual(CapsuleSliderGeometry.value(at: 400, width: 310), 1)
    }

    func testInvalidValuesNeverProduceInvalidDrawingCoordinates() {
        XCTAssertEqual(CapsuleSliderGeometry.thumbCenter(value: .nan, width: 310), 7)
        XCTAssertTrue(CapsuleSliderGeometry.thumbCenter(value: 0.5, width: 0).isFinite)
    }
}
