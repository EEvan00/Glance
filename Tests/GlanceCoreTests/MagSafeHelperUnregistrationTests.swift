import Dispatch
import XCTest
@testable import GlanceCore

@MainActor
final class MagSafeHelperUnregistrationTests: XCTestCase {
    func testBackgroundUnregistrationReplyCompletesBeforeTrashAndQuit() async throws {
        var events: [String] = []
        let coordinator = UninstallCoordinator(
            removeHelper: {
                try await SystemMagSafeLEDHelperManager.awaitUnregistration { reply in
                    DispatchQueue.global().async { reply(nil) }
                }
                events.append("helper")
            },
            removeLoginItem: { events.append("login") },
            moveApplicationToTrash: { events.append("trash") },
            quit: { events.append("quit") }
        )
        try await coordinator.uninstall()
        XCTAssertEqual(events, ["helper", "login", "trash", "quit"])
    }

    func testBackgroundFailurePreservesErrorAndDoesNotTrashApp() async {
        enum Failure: Error { case denied }
        var trashed = false
        let coordinator = UninstallCoordinator(
            removeHelper: {
                try await SystemMagSafeLEDHelperManager.awaitUnregistration { reply in
                    DispatchQueue.global().async { reply(Failure.denied) }
                }
            },
            removeLoginItem: {},
            moveApplicationToTrash: { trashed = true },
            quit: { XCTFail("Failed helper removal must not quit") }
        )
        do { try await coordinator.uninstall(); XCTFail("Expected unregistration failure") }
        catch { XCTAssertEqual(error as? Failure, .denied) }
        XCTAssertFalse(trashed)
    }
}
