import XCTest
@testable import GlanceCore

@MainActor
final class WeatherShortcutInstallFlowTests: XCTestCase {
    func testExistingMainShortcutNeedsNoSecondImporter() {
        let flow = WeatherShortcutInstallFlow()
        XCTAssertNil(flow.nextToOpen(installed: ["Glance Weather"]))
        XCTAssertFalse(flow.isInProgress)
    }

    func testCancelledImporterStaysPendingUntilMainShortcutIsInstalled() {
        let flow = WeatherShortcutInstallFlow()
        XCTAssertEqual(flow.nextToOpen(installed: []), .current)
        flow.reconcile(installed: [])
        XCTAssertEqual(flow.nextToOpen(installed: []), .current)
        flow.reconcile(installed: ["Glance Weather"])
        XCTAssertFalse(flow.isInProgress)
        XCTAssertNil(flow.nextToOpen(installed: ["Glance Weather"]))
    }

    func testLegacyForecastAloneStillRequiresUnifiedShortcut() {
        let installed: Set<String> = ["Glance Weather Forecast"]
        XCTAssertEqual(WeatherShortcutInstallFlow().nextToOpen(installed: installed), .current)
    }
}
