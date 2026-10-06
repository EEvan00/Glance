import XCTest
@testable import GlanceCore

@MainActor
final class ScreenshotOptionsTests: XCTestCase {
    func testPreferencesPersistAndInvalidValuesFallBack() {
        let suite = "Glance.Screenshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.screenshotMode, .toolbar)
        XCTAssertEqual(settings.screenshotDestination, .desktop)
        settings.screenshotMode = .region
        settings.screenshotDestination = .clipboard
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.screenshotMode, .region)
        XCTAssertEqual(restored.screenshotDestination, .clipboard)
        defaults.set("invalid", forKey: "screenshotMode")
        defaults.set("invalid", forKey: "screenshotDestination")
        XCTAssertEqual(SettingsStore(defaults: defaults).screenshotMode, .toolbar)
        XCTAssertEqual(SettingsStore(defaults: defaults).screenshotDestination, .desktop)
    }

    func testAllModesHonorDestinationWithoutShellParsing() {
        let file = URL(fileURLWithPath: "/tmp/screenshot folder/Glance image.png")
        for mode in ScreenshotMode.allCases {
            let prefix = ["-i", mode == .toolbar ? "-U" : "-s"]
            XCTAssertEqual(ScreenshotRequest(mode: mode, destination: .desktop).arguments(fileURL: file),
                           prefix + ["-t", "png", file.path])
            XCTAssertEqual(ScreenshotRequest(mode: mode, destination: .clipboard).arguments(fileURL: file),
                           prefix + ["-c"])
        }
    }
}
