import Foundation

struct WiFiNetworkGroups {
    let known: [WiFiNetwork]
    let other: [WiFiNetwork]

    init(networks: [WiFiNetwork], knownSSIDs: Set<String>, hotspotSSIDs: Set<String>) {
        let wifi = networks.filter { !hotspotSSIDs.contains($0.ssid) }
        known = wifi.filter { $0.isConnected || knownSSIDs.contains($0.ssid) }
            .sorted { lhs, rhs in
                if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
                return lhs.ssid.localizedStandardCompare(rhs.ssid) == .orderedAscending
            }
        other = wifi.filter { !$0.isConnected && !knownSSIDs.contains($0.ssid) }
    }
}
