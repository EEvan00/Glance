import XCTest
@testable import GlanceCore

final class PopupUtilityTests: XCTestCase {
    @MainActor
    func testDefaultAndInvalidPreferenceUsePerformanceAndSelectionPersists() {
        let name = "Glance.PopupUtility.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(SettingsStore(defaults: defaults).popupUtility, .performance)
        defaults.set("focus", forKey: "popupUtility")
        XCTAssertEqual(SettingsStore(defaults: defaults).popupUtility, .performance)
        defaults.set("removed", forKey: "popupUtility")
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.popupUtility, .performance)
        settings.popupUtility = .claude
        XCTAssertEqual(SettingsStore(defaults: defaults).popupUtility, .claude)
        settings.popupUtility = .codex
        XCTAssertEqual(SettingsStore(defaults: defaults).popupUtility, .codex)
    }

    @MainActor
    func testClaudeLimitsRequireValidUnexpiredWindows() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let data = Data(#"{"updated_at":990,"rate_limits":{"five_hour":{"used_percentage":24,"resets_at":2000},"seven_day":{"used_percentage":40,"resets_at":5000}}}"#.utf8)
        let result = try ClaudeUsageController.decode(data, now: now)
        XCTAssertEqual(result.snapshot.windows.map(\.remainingPercent), [76, 60])
        XCTAssertEqual(result.snapshot.windows.map(\.windowDurationMins), [300, 10080])
        let expired = Data(#"{"updated_at":990,"rate_limits":{"five_hour":{"used_percentage":24,"resets_at":900},"seven_day":{"used_percentage":40,"resets_at":5000}}}"#.utf8)
        XCTAssertEqual(try ClaudeUsageController.decode(expired, now: now).snapshot.windows.count, 1)
        for json in [
            #"{"updated_at":990,"rate_limits":{"five_hour":{"used_percentage":101,"resets_at":2000}}}"#,
            #"{"updated_at":990,"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":900}}}"#,
            #"{"updated_at":990,"rate_limits":{}}"#,
            #"{"updated_at":3000,"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":4000}}}"#
        ] { XCTAssertThrowsError(try ClaudeUsageController.decode(Data(json.utf8), now: now)) }
    }

    @MainActor
    func testMissingClaudeDataNeverInventsQuotaAndHiddenRefreshDoesNotRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let controller = ClaudeUsageController(cacheURL: url)
        controller.setVisible(true)
        XCTAssertNil(controller.snapshot)
        XCTAssertTrue(controller.isUnavailable)
        controller.setVisible(false)
        let reset = Date().timeIntervalSince1970 + 3600
        let payload: [String: Any] = ["updated_at": Date().timeIntervalSince1970,
            "rate_limits": ["five_hour": ["used_percentage": 25, "resets_at": reset]]]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        controller.refreshNow()
        XCTAssertNil(controller.snapshot)
        controller.setVisible(true)
        XCTAssertEqual(controller.snapshot?.windows.first?.remainingPercent, 75)
        XCTAssertFalse(controller.isUnavailable)
    }

    func testClaudeConnectionPreservesExistingCommandAndSettingsAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home with space")
        let support = root.appendingPathComponent("support's dir")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        let original: [String: Any] = ["theme": "dark", "statusLine": ["type": "command", "command": "cat", "padding": 2]]
        let bytes = try JSONSerialization.data(withJSONObject: original)
        try bytes.write(to: settingsURL)
        try ClaudeUsageIntegration.install(home: home, support: support)
        let installed = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
        XCTAssertEqual(installed["theme"] as? String, "dark")
        XCTAssertEqual((installed["statusLine"] as? [String: Any])?["padding"] as? Int, 2)
        XCTAssertEqual(try Data(contentsOf: support.appendingPathComponent("claude-settings-backup.json")), bytes)
        let installedBytes = try Data(contentsOf: settingsURL)
        try ClaudeUsageIntegration.install(home: home, support: support)
        XCTAssertEqual(try Data(contentsOf: settingsURL), installedBytes)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [support.appendingPathComponent("claude-statusline.pl").path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output
        try process.run()
        let sample = Data(#"{"model":{"display_name":"Test"},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":9999999999}},"sensitive":"must not be cached"}"#.utf8)
        input.fileHandleForWriting.write(sample)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(output.fileHandleForReading.readDataToEndOfFile(), sample)
        let cache = try JSONSerialization.jsonObject(with: Data(contentsOf: support.appendingPathComponent("claude-usage.json"))) as! [String: Any]
        XCTAssertNil(cache["sensitive"])
        XCTAssertNotNil(cache["rate_limits"])
    }

    func testClaudeConnectionRejectsMalformedSettingsInsteadOfReplacingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let url = root.appendingPathComponent(".claude/settings.json")
        let bytes = Data("[]".utf8)
        try bytes.write(to: url)
        XCTAssertThrowsError(try ClaudeUsageIntegration.install(home: root, support: root.appendingPathComponent("support")))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
}
