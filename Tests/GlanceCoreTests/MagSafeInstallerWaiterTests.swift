import XCTest
import ServiceManagement
@testable import GlanceCore

@MainActor
final class MagSafeInstallerWaiterTests: XCTestCase {
    func testMigrationContinuesWhenUnregisterThrowsButServiceIsAlreadyRemoved() async throws {
        try await SystemMagSafeLEDHelperManager.unregisterForPackage(status: { .notRegistered }, unregister: { throw CocoaError(.fileNoSuchFile) })
    }

    func testMigrationDoesNotHideFailureWhenOldServiceRemainsEnabled() async {
        do {
            try await SystemMagSafeLEDHelperManager.unregisterForPackage(status: { .enabled }, unregister: { throw CocoaError(.fileNoSuchFile) })
            XCTFail("An active conflicting registration must not be ignored")
        } catch {
            XCTAssertEqual((error as? CocoaError)?.code, .fileNoSuchFile)
        }
    }

    func testRunningInstallerWithNoObservedWindowStopsAfterInitialGrace() {
        let start = Date(timeIntervalSince1970: 100)
        var session = MagSafeInstallerSessionState(startedAt: start)
        XCTAssertTrue(session.isActive(processTerminated: false, hasWindow: false, now: start))
        XCTAssertFalse(session.isActive(processTerminated: false, hasWindow: false, now: start.addingTimeInterval(10)))
    }

    func testObservedWindowClosingCancelsEvenIfInstallerProcessRemainsAlive() {
        let start = Date(timeIntervalSince1970: 100)
        var session = MagSafeInstallerSessionState(startedAt: start)
        XCTAssertTrue(session.isActive(processTerminated: false, hasWindow: true, now: start))
        XCTAssertFalse(session.isActive(processTerminated: false, hasWindow: false, now: start.addingTimeInterval(1)))
    }

    func testInstallerWithOpenWindowCanRemainActiveBeyondInitialGrace() {
        let start = Date(timeIntervalSince1970: 100)
        var session = MagSafeInstallerSessionState(startedAt: start)
        XCTAssertTrue(session.isActive(processTerminated: false, hasWindow: true, now: start.addingTimeInterval(60)))
        XCTAssertFalse(session.isActive(processTerminated: true, hasWindow: true, now: start.addingTimeInterval(61)))
    }

    func testClosingInstallerCancelsImmediatelyInsteadOfWaitingForTimeout() async {
        var pauses = 0
        do {
            try await MagSafeInstallerWaiter.waitForCompletion(completed: { false }, isInstallerRunning: { false }, attempts: 2, pause: { pauses += 1 })
            XCTFail("Closed installer must cancel the request")
        } catch {
            XCTAssertEqual((error as? CocoaError)?.code, .userCancelled)
        }
        XCTAssertEqual(pauses, 0)
    }

    func testSuccessfulInstallationIsRecognizedEvenIfInstallerHasExited() async throws {
        try await MagSafeInstallerWaiter.waitForCompletion(completed: { true }, isInstallerRunning: { false }, pause: { XCTFail("Completed installation must not wait") })
    }

    func testInstallerExitAfterOpeningStopsPolling() async {
        var pauses = 0
        do {
            try await MagSafeInstallerWaiter.waitForCompletion(completed: { false }, isInstallerRunning: { pauses == 0 }, attempts: 3, pause: { pauses += 1 })
            XCTFail("Closed installer must cancel the request")
        } catch {
            XCTAssertEqual((error as? CocoaError)?.code, .userCancelled)
        }
        XCTAssertEqual(pauses, 1)
    }
}
