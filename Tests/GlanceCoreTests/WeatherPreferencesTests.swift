import XCTest
import SwiftUI
@testable import GlanceCore

@MainActor
final class WeatherPreferencesTests: XCTestCase {
    func testDefaultSourceFollowsBuildCapabilityWithoutSavingAnImplicitChoice() {
        withDefaults { defaults in
            XCTAssertEqual(SettingsStore(defaults: defaults, nativeWeatherAvailable: false).weatherSource, .shortcuts)
            XCTAssertEqual(SettingsStore(defaults: defaults, nativeWeatherAvailable: true).weatherSource, .nativeWeather)
            XCTAssertNil(defaults.object(forKey: SettingsStore.weatherSourceDefaultsKey))
        }
    }

    func testExplicitShortcutSelectionSurvivesCapabilityUpgrade() {
        withDefaults { defaults in
            let settings = SettingsStore(defaults: defaults, nativeWeatherAvailable: false)
            settings.weatherSource = .shortcuts
            XCTAssertEqual(SettingsStore(defaults: defaults, nativeWeatherAvailable: true).weatherSource, .shortcuts)
        }
    }

    func testExplicitNativeSelectionSurvivesUnconfiguredBuild() {
        withDefaults { defaults in
            let settings = SettingsStore(defaults: defaults, nativeWeatherAvailable: true)
            settings.weatherSource = .nativeWeather
            XCTAssertEqual(SettingsStore(defaults: defaults, nativeWeatherAvailable: false).weatherSource, .nativeWeather)
        }
    }

    func testInvalidStoredSourceUsesCapabilityDefault() {
        withDefaults { defaults in
            defaults.set("future-source", forKey: SettingsStore.weatherSourceDefaultsKey)
            XCTAssertEqual(SettingsStore(defaults: defaults, nativeWeatherAvailable: false).weatherSource, .shortcuts)
            XCTAssertEqual(SettingsStore(defaults: defaults, nativeWeatherAvailable: true).weatherSource, .nativeWeather)
        }
    }

    func testNativeIssuesSelectActionableLocalizedGuidance() {
        XCTAssertEqual(NativeWeatherIssue.notConfigured.messageKey, .weatherNativeNotConfigured)
        XCTAssertEqual(NativeWeatherIssue.locationDenied.messageKey, .weatherNativeLocationDenied)
        XCTAssertEqual(NativeWeatherIssue.locationServicesDisabled.messageKey, .weatherNativeLocationServicesDisabled)
        XCTAssertEqual(NativeWeatherIssue.authorizationTimedOut.messageKey, .weatherNativeAuthorizationTimedOut)
        XCTAssertTrue(NativeWeatherIssue.locationServicesDisabled.opensLocationSettings)
        XCTAssertFalse(NativeWeatherIssue.authorizationTimedOut.opensLocationSettings)
        XCTAssertEqual(NativeWeatherIssue.locationUnavailable.messageKey, .weatherNativeLocationUnavailable)
        XCTAssertEqual(NativeWeatherIssue.serviceUnavailable.messageKey, .weatherNativeServiceUnavailable)
        XCTAssertTrue(NativeWeatherIssue.locationDenied.opensLocationSettings)
        XCTAssertFalse(NativeWeatherIssue.notConfigured.opensLocationSettings)
        XCTAssertFalse(NativeWeatherIssue.locationUnavailable.opensLocationSettings)
        XCTAssertFalse(NativeWeatherIssue.serviceUnavailable.opensLocationSettings)
    }

    func testOfficialMarkContrastsWithLightAndDarkSurfaces() {
        let attribution = NativeWeatherAttribution(
            combinedMarkLightURL: URL(string: "https://weatherkit.apple.com/assets/black-mark.png")!,
            combinedMarkDarkURL: URL(string: "https://weatherkit.apple.com/assets/white-mark.png")!,
            legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
        XCTAssertEqual(attribution.markURL(for: .dark).lastPathComponent, "white-mark.png")
        XCTAssertEqual(attribution.markURL(for: .light).lastPathComponent, "black-mark.png")
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "Glance.WeatherPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}
