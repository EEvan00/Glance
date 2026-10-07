import XCTest
@testable import GlanceCore

final class PopupQuickActionTests: XCTestCase {
    @MainActor
    func testDefaultSlotsAndSavedConfigurationSurviveRestart() throws {
        let suite = "QuickActionsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.firstQuickAction, .timer)
        XCTAssertEqual(store.secondQuickAction, .screenshot)
        store.firstQuickAction = .shortcut
        store.secondQuickAction = .application
        store.quickActionShortcutName = "我的计时器 & Music + Notes"
        store.quickActionApplicationPath = "/Applications/My App.app"
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.firstQuickAction, .shortcut)
        XCTAssertEqual(restored.secondQuickAction, .application)
        XCTAssertEqual(restored.quickActionShortcutName, store.quickActionShortcutName)
        XCTAssertEqual(restored.quickActionApplicationPath, store.quickActionApplicationPath)
    }

    @MainActor
    func testDuplicateAndUnknownStoredSlotsRecover() throws {
        let suite = "QuickActionsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("screenshot", forKey: "firstQuickAction")
        defaults.set("screenshot", forKey: "secondQuickAction")
        let repaired = SettingsStore(defaults: defaults)
        XCTAssertEqual(repaired.firstQuickAction, .screenshot)
        XCTAssertEqual(repaired.secondQuickAction, .timer)
        defaults.set("removedAction", forKey: "firstQuickAction")
        defaults.set("unknown", forKey: "secondQuickAction")
        let recovered = SettingsStore(defaults: defaults)
        XCTAssertEqual(recovered.firstQuickAction, .timer)
        XCTAssertEqual(recovered.secondQuickAction, .screenshot)
    }

    @MainActor
    func testOptionalStripsPersistAndEnableAllDisplayedServices() throws {
        let suite = "UtilityStripsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.firstUtilityRow, .none)
        XCTAssertEqual(store.secondUtilityRow, .none)
        XCTAssertEqual(store.visiblePopupUtilities, [.performance])
        store.firstUtilityRow = .codex
        store.secondUtilityRow = .claude
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.firstUtilityRow, .codex)
        XCTAssertEqual(restored.secondUtilityRow, .claude)
        XCTAssertEqual(restored.visiblePopupUtilities, [.performance, .codex, .claude])
        restored.firstUtilityRow = .none
        XCTAssertEqual(restored.visiblePopupUtilities, [.performance, .claude])
        restored.secondUtilityRow = .none
        XCTAssertEqual(restored.visiblePopupUtilities, [.performance])
        restored.popupUtility = .codex
        XCTAssertEqual(restored.visiblePopupUtilities, [.codex])
    }

    @MainActor
    func testUnknownAndDuplicateStripPreferencesRecover() throws {
        let suite = "UtilityStripsTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("codex", forKey: "firstUtilityRow")
        defaults.set("codex", forKey: "secondUtilityRow")
        let duplicate = SettingsStore(defaults: defaults)
        XCTAssertEqual(duplicate.firstUtilityRow, .codex)
        XCTAssertEqual(duplicate.secondUtilityRow, .none)
        defaults.set("removed", forKey: "firstUtilityRow")
        defaults.set("invalid", forKey: "secondUtilityRow")
        let invalid = SettingsStore(defaults: defaults)
        XCTAssertEqual(invalid.firstUtilityRow, .none)
        XCTAssertEqual(invalid.secondUtilityRow, .none)
    }

    func testPopupQuotaPrefersFiveHourWindowWithoutChangingDetailOrder() {
        let weekly = CodexUsageWindow(id: "weekly", usedPercent: 20, windowDurationMins: 10080, resetsAt: 9000)
        let fiveHour = CodexUsageWindow(id: "five", usedPercent: 70, windowDurationMins: 300, resetsAt: 2000)
        let both = CodexUsageSnapshot(windows: [weekly, fiveHour])
        XCTAssertEqual(both.preferredPopupWindow?.id, "five")
        XCTAssertEqual(both.preferredPopupWindow?.remainingPercent, 30)
        XCTAssertEqual(both.preferredPopupWindow?.resetsAt, 2000)
        XCTAssertEqual(both.windows.map(\.id), ["weekly", "five"])
        XCTAssertEqual(CodexUsageSnapshot(windows: [weekly]).preferredPopupWindow?.id, "weekly")
        XCTAssertNil(CodexUsageSnapshot(windows: []).preferredPopupWindow)
    }

    func testShortcutNameIsOneQueryValueAndMissingChoicesDoNotLaunch() throws {
        let name = "我的快捷指令 & name=wrong #?/+"
        let url = try XCTUnwrap(PopupQuickAction.shortcutURL(name: name))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "shortcuts")
        XCTAssertEqual(components.host, "run-shortcut")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "name", value: name)])
        XCTAssertNil(components.fragment)
        XCTAssertNil(PopupQuickAction.shortcut.launchURL(applicationPath: "", shortcutName: ""))
        XCTAssertNil(PopupQuickAction.application.launchURL(applicationPath: "", shortcutName: ""))
    }
}
