import Foundation
import XCTest
@testable import GlanceCore

@MainActor
final class WeatherShortcutUpdateTests: XCTestCase {
    private func withStore(_ body: (WeatherShortcutVersions, UserDefaults) throws -> Void) rethrows {
        let name = "Glance.ShortcutRevisions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(WeatherShortcutVersions(defaults: defaults), defaults)
    }

    func testUpdateRequiresConfirmedOutputAndPersistsAcrossLaunches() {
        withStore { versions, defaults in
            let name = BundledWeatherShortcut.current.rawValue
            XCTAssertFalse(versions.needsUpdate(name: name, bundledVersion: 1))
            versions.record(name: name, version: nil)
            XCTAssertTrue(versions.needsUpdate(name: name, bundledVersion: 1))
            versions.requestVerification(name: name)
            XCTAssertTrue(versions.needsUpdate(name: name, bundledVersion: 1))
            XCTAssertTrue(versions.pendingVerification.contains(name))
            // Cancelling an importer leaves the legacy output and its update notice intact.
            versions.record(name: name, version: nil)
            XCTAssertTrue(versions.needsUpdate(name: name, bundledVersion: 1))
            XCTAssertTrue(versions.pendingVerification.contains(name))
            versions.record(name: name, version: 1)
            XCTAssertFalse(versions.needsUpdate(name: name, bundledVersion: 1))
            let restored = WeatherShortcutVersions(defaults: defaults)
            XCTAssertFalse(restored.needsUpdate(name: name, bundledVersion: 1))
            XCTAssertTrue(restored.needsUpdate(name: name, bundledVersion: 2))
            XCTAssertFalse(restored.needsUpdate(name: name, bundledVersion: 0))
        }
    }

    func testCurrentAndForecastUpdatesAreIndependent() {
        withStore { versions, _ in
            let current = BundledWeatherShortcut.current.rawValue
            let forecast = BundledWeatherShortcut.forecast.rawValue
            versions.record(name: current, version: 1)
            versions.record(name: forecast, version: nil)
            XCTAssertFalse(versions.needsUpdate(name: current, bundledVersion: 1))
            XCTAssertTrue(versions.needsUpdate(name: forecast, bundledVersion: 1))
            versions.record(name: "Unrelated shortcut", version: 1)
            XCTAssertNil(versions.observed["Unrelated shortcut"])
        }
    }

    func testVersionMarkerDoesNotBecomePartOfForecastSections() throws {
        let snapshot = try XCTUnwrap(WeatherSnapshot.fromShortcut("18°C\nDrizzle\nUV\n0\nRAIN_CHANCE\n96%\nGLANCE_VERSION\n1"))
        XCTAssertEqual(snapshot.shortcutVersion, 1)
        XCTAssertEqual(snapshot.uvIndex, 0)
        XCTAssertEqual(snapshot.precipitationChance, 96)
        XCTAssertNil(WeatherSnapshot.fromShortcut("18°C\nClear\nGLANCE_VERSION\n-1")?.shortcutVersion)
        XCTAssertNil(WeatherSnapshot.fromShortcut("18°C\nClear\nGLANCE_VERSION\ninvalid")?.shortcutVersion)
        XCTAssertNil(WeatherSnapshot.fromShortcut("18°C\nClear")?.shortcutVersion)
    }

    func testBundledWorkflowMarkersMatchManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for shortcut in BundledWeatherShortcut.allCases {
            XCTAssertGreaterThan(shortcut.version, 0)
            let source = root.appendingPathComponent("Support/WeatherShortcuts/\(shortcut.rawValue).wflow")
            let workflow = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: source), format: nil) as? [String: Any])
            let actions = try XCTUnwrap(workflow["WFWorkflowActions"] as? [[String: Any]])
            let comment = try XCTUnwrap(actions.first)
            XCTAssertEqual(comment["WFWorkflowActionIdentifier"] as? String, "is.workflow.actions.comment")
            let commentParameters = try XCTUnwrap(comment["WFWorkflowActionParameters"] as? [String: Any])
            XCTAssertTrue(try XCTUnwrap(commentParameters["WFCommentActionText"] as? String).contains("Version / 版本: \(shortcut.version)"))
            let text = try XCTUnwrap(actions.last(where: { $0["WFWorkflowActionIdentifier"] as? String == "is.workflow.actions.gettext" }))
            let parameters = try XCTUnwrap(text["WFWorkflowActionParameters"] as? [String: Any])
            let token = try XCTUnwrap(parameters["WFTextActionText"] as? [String: Any])
            let value = try XCTUnwrap(token["Value"] as? [String: Any])
            XCTAssertTrue(try XCTUnwrap(value["string"] as? String).hasSuffix("\nGLANCE_VERSION\n\(shortcut.version)"))
        }
    }

    func testReturnAfterImportBypassesWeatherCacheAndFailedRunsDoNotAcknowledge() async throws {
        let name = "Glance.ShortcutVerification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let versions = WeatherShortcutVersions(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("weather")
        func script(_ output: String) throws {
            try "#!/bin/sh\ncat > /dev/null\nprintf '%s' '\(output)' > \"$6\"\n".write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
        let shortcut = BundledWeatherShortcut.current.rawValue
        let controller = WeatherController(executable: executable, versions: versions)
        try script("18°C\nClear")
        controller.setVisible(true, shortcutName: shortcut)
        for _ in 0..<250 where controller.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(versions.needsUpdate(name: shortcut, bundledVersion: 1))
        controller.setVisible(false, shortcutName: shortcut)
        versions.requestVerification(name: shortcut)
        try script("bad output")
        controller.setVisible(true, shortcutName: shortcut)
        for _ in 0..<250 where controller.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(controller.isUnavailable)
        XCTAssertTrue(versions.needsUpdate(name: shortcut, bundledVersion: 1))
        XCTAssertTrue(versions.pendingVerification.contains(shortcut))
        controller.setVisible(false, shortcutName: shortcut)
        try script("19°C\nClear\nGLANCE_VERSION\n1")
        controller.setVisible(true, shortcutName: shortcut)
        for _ in 0..<250 where controller.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(controller.snapshot?.shortcutVersion, 1)
        XCTAssertFalse(versions.needsUpdate(name: shortcut, bundledVersion: 1))
        XCTAssertFalse(versions.pendingVerification.contains(shortcut))
        controller.setVisible(false, shortcutName: shortcut)
    }
}
