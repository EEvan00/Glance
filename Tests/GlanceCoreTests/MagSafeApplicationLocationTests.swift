import XCTest
@testable import GlanceCore

final class MagSafeApplicationLocationTests: XCTestCase {
    func testMovingAppOutOfItsLaunchLocationStopsRenewalEvenIfReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Glance.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = MagSafeApplicationLocation(url: app)
        XCTAssertTrue(location.isPresent)
        try FileManager.default.moveItem(at: app, to: root.appendingPathComponent("Moved.app"))
        XCTAssertFalse(location.isPresent)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertFalse(location.isPresent)
    }

    func testLaunchingFromTrashNeverRenewsOffState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent(".Trash/Glance.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(MagSafeApplicationLocation(url: app).isPresent)
    }
}
