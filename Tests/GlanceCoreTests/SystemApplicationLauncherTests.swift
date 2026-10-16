import XCTest
@testable import GlanceCore

@MainActor
final class SystemApplicationLauncherTests: XCTestCase {
    func testBackgroundCompletionReturnsToMainActor() async throws {
        try await SystemApplicationLauncher.awaitCompletion { reply in
            DispatchQueue.global().async { reply(nil) }
        }
        MainActor.assertIsolated()
    }

    func testBackgroundFailurePropagatesToCaller() async {
        do {
            try await SystemApplicationLauncher.awaitCompletion { reply in
                DispatchQueue.global().async { reply(CocoaError(.fileNoSuchFile)) }
            }
            XCTFail("Launch failure must reach the caller")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.fileNoSuchFile.rawValue)
        }
    }
}
