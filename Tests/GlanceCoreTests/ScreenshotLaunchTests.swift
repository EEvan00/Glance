import AppKit
import XCTest
@testable import GlanceCore

@MainActor
final class ScreenshotLaunchTests: XCTestCase {
    /// Opt-in: opens the real macOS screenshot toolbar without taking a screenshot.
    func testSystemScreenshotLaunchDoesNotCrashOnWorkspaceCompletion() async throws {
        guard ProcessInfo.processInfo.environment["GLANCE_TEST_SYSTEM_LAUNCH"] == "1" else {
            throw XCTSkip("Requires an interactive macOS desktop")
        }
        let controller = ScreenshotController()
        controller.capture(localization: Localization())
        try await Task.sleep(for: .seconds(2))
        // Verify the same production launch boundary reports success, including
        // a repeated launch while the screenshot utility is already available.
        try await SystemApplicationLauncher.open(
            URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
    }
    func testShowDesktopLaunchUsesSystemApplicationService() async throws {
        guard ProcessInfo.processInfo.environment["GLANCE_TEST_SYSTEM_LAUNCH"] == "1" else {
            throw XCTSkip("Requires an interactive macOS desktop")
        }
        let controller = FooterActionController(localization: Localization())
        controller.perform(FooterModule(kind: .showDesktop))
        try await Task.sleep(for: .seconds(2))
        XCTAssertNil(controller.errorMessage)
    }
}
