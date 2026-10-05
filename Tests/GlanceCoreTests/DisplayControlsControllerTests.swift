import XCTest
import DisplayFeaturesBridge
@testable import GlanceCore

@MainActor
final class DisplayControlsControllerTests: XCTestCase {
    func testUnsupportedFeatureFailsClosed() {
        XCTAssertEqual(STDisplayFeatureState(-1), -1)
        XCTAssertFalse(STSetDisplayFeature(-1, true))
    }

    func testReadOnlyDisplaySnapshotHasValidIdentities() {
        let controller = DisplayControlsController()
        controller.refresh()
        XCTAssertEqual(Set(controller.presets.map(\.id)).count, controller.presets.count)
        XCTAssertTrue(controller.presets.allSatisfy { !$0.name.isEmpty && $0.id >= 0 })
        XCTAssertTrue(controller.states.keys.allSatisfy { (0...2).contains($0) })
        let before = controller.activePreset
        controller.select(DisplayPreset(id: -1, name: "Invalid"))
        XCTAssertEqual(controller.activePreset, before, "Unknown identities must never reach the display setter")
        print("Display snapshot:", controller.displayName, controller.presets.map(\.name), controller.states)
    }
}
