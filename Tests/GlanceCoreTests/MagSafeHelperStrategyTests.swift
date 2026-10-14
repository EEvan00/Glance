import XCTest
import ServiceManagement
@testable import GlanceCore

@MainActor
final class MagSafeHelperStrategyTests: XCTestCase {
    func testBundledStrategyRequiresMigrationEvenWhenLegacyHelperIsCurrent() {
        XCTAssertEqual(SystemMagSafeLEDHelperManager.helperStatus(
            strategy: .bundledService, legacyInstalled: true, legacyCurrent: true, serviceStatus: .enabled
        ), .notRegistered)
    }

    func testBundledStrategyPreservesSystemApprovalRequirement() {
        XCTAssertEqual(SystemMagSafeLEDHelperManager.helperStatus(
            strategy: .bundledService, legacyInstalled: false, legacyCurrent: false, serviceStatus: .requiresApproval
        ), .requiresApproval)
    }

    func testLegacyStrategyIgnoresBundledRegistrationUntilPackageIsInstalled() {
        XCTAssertEqual(SystemMagSafeLEDHelperManager.helperStatus(
            strategy: .legacyPackage, legacyInstalled: false, legacyCurrent: false, serviceStatus: .enabled
        ), .notRegistered)
        XCTAssertEqual(SystemMagSafeLEDHelperManager.helperStatus(
            strategy: .legacyPackage, legacyInstalled: true, legacyCurrent: true, serviceStatus: .notRegistered
        ), .enabled)
    }

    func testUnknownStrategyFailsClosed() {
        XCTAssertEqual(MagSafeHelperStrategy(configuration: "unexpected"), .unavailable)
        XCTAssertEqual(SystemMagSafeLEDHelperManager.helperStatus(
            strategy: .unavailable, legacyInstalled: true, legacyCurrent: true, serviceStatus: .enabled
        ), .notRegistered)
    }

    func testMigrationRemovesLegacyFilesBeforeRegisteringBundledService() async throws {
        var installed = true
        var events: [String] = []
        try await SystemMagSafeLEDHelperManager.installBundled(
            hasLegacyFiles: { installed },
            uninstallLegacy: { events.append("uninstall"); installed = false },
            register: { events.append("register") }
        )
        XCTAssertEqual(events, ["uninstall", "register"])
    }

    func testMigrationCancellationDoesNotRegisterBundledService() async {
        var registered = false
        do {
            try await SystemMagSafeLEDHelperManager.installBundled(
                hasLegacyFiles: { true }, uninstallLegacy: { throw CocoaError(.userCancelled) },
                register: { registered = true }
            )
            XCTFail("Cancelled administrator authorization must stop migration")
        } catch { XCTAssertEqual((error as? CocoaError)?.code, .userCancelled) }
        XCTAssertFalse(registered)
    }

    func testMigrationFailureDoesNotRegisterBundledService() async {
        var registered = false
        do {
            try await SystemMagSafeLEDHelperManager.installBundled(
                hasLegacyFiles: { true }, uninstallLegacy: { throw CocoaError(.fileWriteNoPermission) },
                register: { registered = true }
            )
            XCTFail("Failed uninstall must stop migration")
        } catch { XCTAssertEqual((error as? CocoaError)?.code, .fileWriteNoPermission) }
        XCTAssertFalse(registered)
    }

    func testRemainingLegacyFilesStopMigrationEvenWhenUninstallReturnsSuccess() async {
        var registered = false
        do {
            try await SystemMagSafeLEDHelperManager.installBundled(
                hasLegacyFiles: { true }, uninstallLegacy: {}, register: { registered = true }
            )
            XCTFail("Conflicting legacy files must be removed before registration")
        } catch { XCTAssertEqual((error as? CocoaError)?.code, .fileWriteUnknown) }
        XCTAssertFalse(registered)
    }

    func testFreshBundledInstallSkipsLegacyUninstaller() async throws {
        var registered = false
        try await SystemMagSafeLEDHelperManager.installBundled(
            hasLegacyFiles: { false }, uninstallLegacy: { XCTFail("No installed legacy helper") },
            register: { registered = true }
        )
        XCTAssertTrue(registered)
    }
}
