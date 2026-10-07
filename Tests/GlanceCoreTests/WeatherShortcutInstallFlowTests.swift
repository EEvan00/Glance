import XCTest
@testable import GlanceCore

@MainActor
final class WeatherShortcutInstallFlowTests: XCTestCase {
    func testImportersOpenInOrderAndCancellationDoesNotAdvance() {
        let flow = WeatherShortcutInstallFlow()
        XCTAssertEqual(flow.nextToOpen(installed: []), .current)
        XCTAssertTrue(flow.isInProgress)
        // Returning without installing keeps the current shortcut as the next step.
        flow.reconcile(installed: [])
        XCTAssertEqual(flow.nextToOpen(installed: []), .current)
        let current: Set<String> = [BundledWeatherShortcut.current.rawValue]
        flow.reconcile(installed: current)
        XCTAssertEqual(flow.nextToOpen(installed: current), .forecast)
        let both = Set(BundledWeatherShortcut.allCases.map(\.rawValue))
        flow.reconcile(installed: both)
        XCTAssertFalse(flow.isInProgress)
        XCTAssertNil(flow.nextToOpen(installed: both))
    }

    func testSkipsAlreadyInstalledShortcutAndResumesAfterReopening() {
        let flow = WeatherShortcutInstallFlow()
        let current: Set<String> = [BundledWeatherShortcut.current.rawValue]
        XCTAssertEqual(flow.nextToOpen(installed: current), .forecast)
        flow.reconcile(installed: current)
        XCTAssertEqual(flow.pending, [.forecast])
        // A fresh flow also derives the right remaining step from actual installation state.
        XCTAssertEqual(WeatherShortcutInstallFlow().nextToOpen(installed: current), .forecast)
        let forecast: Set<String> = [BundledWeatherShortcut.forecast.rawValue]
        XCTAssertEqual(WeatherShortcutInstallFlow().nextToOpen(installed: forecast), .current)
    }
}
