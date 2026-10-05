import XCTest
import GlanceMediaBridge

final class MediaMetadataRecoveryTests: XCTestCase {
    func testMissingDurationGetsBoundedDelayedReads() {
        XCTAssertEqual((0...4).map { GlanceMediaMetadataRetryDelay(0, 1, UInt32($0)) },
                       [0.5, 1, 2, 4, 0])
        XCTAssertEqual(GlanceMediaMetadataRetryDelay(.nan, 1, 0), 0.5)
        XCTAssertEqual(GlanceMediaMetadataRetryDelay(-1, 2, 0), 0.5)
    }

    func testCompleteMetadataImmediatelyStopsRecovery() {
        XCTAssertEqual(GlanceMediaMetadataRetryDelay(252.815, 1, 0), 0)
        XCTAssertEqual(GlanceMediaMetadataRetryDelay(252.815, 2, 3), 0)
    }

    func testStoppedPlayerNeverGetsRecoveryReads() {
        XCTAssertEqual(GlanceMediaMetadataRetryDelay(0, 0, 0), 0)
        XCTAssertEqual(GlanceMediaMetadataRetryDelay(0, 3, 0), 0)
    }
}
