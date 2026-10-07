import XCTest
@testable import GlanceCore

final class UninstallCoordinatorTests: XCTestCase {
    @MainActor func testUninstallRemovesServicesBeforeTrashAndQuitsLast() async throws {
        var events: [String] = []
        let coordinator = UninstallCoordinator(
            removeHelper: { events.append("helper") },
            removeLoginItem: { events.append("login") },
            removeIntegrations: { events.append("integrations") },
            moveApplicationToTrash: { events.append("trash") },
            quit: { events.append("quit") }
        )
        try await coordinator.uninstall()
        XCTAssertEqual(events, ["helper", "login", "integrations", "trash", "quit"])
    }

    @MainActor func testHelperFailureDoesNotTrashOrQuit() async {
        enum Failure: Error { case denied }
        var events: [String] = []
        let coordinator = UninstallCoordinator(
            removeHelper: { throw Failure.denied },
            removeLoginItem: { events.append("login") },
            moveApplicationToTrash: { events.append("trash") },
            quit: { events.append("quit") }
        )
        do { try await coordinator.uninstall(); XCTFail("Expected failure") }
        catch { XCTAssertTrue(events.isEmpty) }
    }

    @MainActor func testTrashFailureKeepsAppRunningToShowError() async {
        enum Failure: Error { case readOnly }
        var quit = false
        let coordinator = UninstallCoordinator(
            removeHelper: {}, removeLoginItem: {},
            moveApplicationToTrash: { throw Failure.readOnly },
            quit: { quit = true }
        )
        do { try await coordinator.uninstall(); XCTFail("Expected failure") }
        catch { XCTAssertFalse(quit) }
    }
}
