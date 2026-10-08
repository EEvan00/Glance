import XCTest
@testable import GlanceCore

final class WiFiNetworkGroupsTests: XCTestCase {
    func testNearbySavedNetworksAreKnownAndUnknownNetworksRemainOther() {
        let groups = WiFiNetworkGroups(networks: networks(), knownSSIDs: ["Home", "Office"], hotspotSSIDs: [])
        XCTAssertEqual(groups.known.map(\.ssid), ["Home", "Office"])
        XCTAssertEqual(groups.other.map(\.ssid), ["Phone", "Cafe"])
    }

    func testConnectedHotspotNeverAppearsInEitherWiFiGroupEvenIfSaved() {
        let groups = WiFiNetworkGroups(networks: networks(connected: "phone"), knownSSIDs: ["Home", "Phone"], hotspotSSIDs: ["Phone"])
        XCTAssertEqual(groups.known.map(\.ssid), ["Home"])
        XCTAssertEqual(groups.other.map(\.ssid), ["Office", "Cafe"])
    }

    func testCurrentUnsavedWiFiStaysVisibleAboveCollapsedOtherNetworks() {
        let groups = WiFiNetworkGroups(networks: networks(connected: "cafe"), knownSSIDs: ["Home"], hotspotSSIDs: ["Phone"])
        XCTAssertEqual(groups.known.map(\.ssid), ["Cafe", "Home"])
        XCTAssertEqual(groups.other.map(\.ssid), ["Office"])
    }

    private func networks(connected: String? = "home") -> [WiFiNetwork] {
        zip(["Home", "Office", "Phone", "Cafe"], ["home", "office", "phone", "cafe"]).map { name, bssid in
            WiFiNetwork(identity: .init(ssid: name, security: .wpa2Personal), candidates: [.init(ssid: name, bssid: bssid, rssi: -50, channel: 1, security: .wpa2Personal)], connectedBSSID: connected)
        }
    }
}
