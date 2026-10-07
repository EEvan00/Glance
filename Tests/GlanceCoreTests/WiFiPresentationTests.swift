import XCTest
@testable import GlanceCore

@MainActor
final class WiFiPresentationTests: XCTestCase {
    func testConnectedNetworkNameDoesNotHideLaterConnectionState() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        let connected = WiFiStatus(state: .connected, rssi: -48, ssid: "Home")
        XCTAssertEqual(StatusPresentation.compactWiFiSubtitle(connected, localization: localization), "Home")
        let states: [(WiFiState, LocalizationKey)] = [
            (.off, .compactOff), (.notAssociated, .compactDisconnected),
            (.noInternet, .compactNoInternet), (.hotspot, .compactHotspot),
            (.temporary, .compactTemporary), (.shared, .compactShared),
            (.unavailable, .compactUnavailable)
        ]
        for (state, key) in states {
            let status = WiFiStatus(state: state, rssi: nil, ssid: "Home")
            XCTAssertEqual(StatusPresentation.compactWiFiSubtitle(status, localization: localization), (state.isNetworkAssociated ? "Home · " : "") + localization.string(key))
        }
    }
}
