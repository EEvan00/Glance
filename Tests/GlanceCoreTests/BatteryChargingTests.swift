import XCTest
@testable import GlanceCore

@MainActor
final class BatteryChargingTests: XCTestCase {
    func testPausedPresentationRequiresSystemConfirmation() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let paused = battery(hold: .resumable)
        XCTAssertEqual(StatusPresentation.batterySubtitle(paused, localization: localization), "Paused")
        XCTAssertEqual(paused.indicatorSymbol, "powerplug.portrait.fill")
        XCTAssertTrue(paused.canChargeToFull)
        XCTAssertFalse(battery(hold: .unknown).isChargingPaused)
        XCTAssertFalse(battery(hold: .inactive).isChargingPaused)
        XCTAssertFalse(battery(hold: .paused).canChargeToFull)
    }

    func testResumedUnpluggedFullOrMissingBatteryIgnoresStaleHold() {
        for status in [
            battery(hold: .resumable, charging: true),
            battery(hold: .resumable, connected: false),
            battery(hold: .resumable, percentage: 100),
            battery(hold: .resumable, present: false),
            battery(hold: .resumable, charged: true)
        ] {
            XCTAssertFalse(status.isChargingPaused)
            XCTAssertFalse(status.canChargeToFull)
        }
        XCTAssertEqual(battery(hold: .resumable, charging: true).indicatorSymbol, "bolt.fill")
    }

    func testChargeRequestReportsFailureAndDoesNotInventChargingState() async {
        let controller = BatteryChargingController(request: { false })
        await controller.chargeToFull(battery: battery(hold: .resumable))
        XCTAssertEqual(controller.result, .failed)
        XCTAssertFalse(controller.isRequesting)
    }

    func testChargeRequestAcceptsOnlyResumableHold() async {
        let controller = BatteryChargingController(request: { true })
        await controller.chargeToFull(battery: battery(hold: .inactive))
        XCTAssertNil(controller.result)
        await controller.chargeToFull(battery: battery(hold: .resumable))
        XCTAssertEqual(controller.result, .accepted)
        XCTAssertFalse(controller.isRequesting)
    }

    func testAcceptedRequestWaitsForObservationBeforeAllowingRetry() async {
        let counter = ChargingRequestCounter()
        let controller = BatteryChargingController(request: { await counter.accept() })
        let status = battery(hold: .resumable)
        await controller.chargeToFull(battery: status)
        await controller.chargeToFull(battery: status)
        let firstCount = await counter.count
        XCTAssertEqual(firstCount, 1)
        controller.reportResumeTimeout()
        XCTAssertEqual(controller.result, .failed)
        await controller.chargeToFull(battery: status)
        let retryCount = await counter.count
        XCTAssertEqual(retryCount, 2)
        controller.clearResult()
        XCTAssertNil(controller.result)
    }

    private func battery(
        hold: BatteryChargingHold,
        charging: Bool = false,
        connected: Bool = true,
        percentage: Int = 80,
        present: Bool = true,
        charged: Bool = false
    ) -> BatteryStatus {
        BatteryStatus(rawPercentage: percentage, isPresent: present, isCharging: charging,
                      isCharged: charged, isLowPowerMode: false, isConnectedToPower: connected,
                      chargingHold: hold)
    }
}

private actor ChargingRequestCounter {
    private(set) var count = 0
    func accept() -> Bool {
        count += 1
        return true
    }
}
