import Foundation

@MainActor
enum BluetoothSummaryPresentation {
    static func text(devices: [BluetoothDevice], availability: BluetoothAvailability, localization: Localization, outputs: [AudioOutputDevice] = []) -> String {
        let key: LocalizationKey
        switch availability {
        case .available:
            let connected = BluetoothDevicePresentation.grouped(devices).connected
            if let output = outputs.first(where: { $0.isCurrent }) {
                let audio = connected.filter { BluetoothDevicePresentation.isAudioDevice($0) }
                let uid = normalized(output.uid ?? "")
                let addressMatches = audio.filter {
                    let address = normalized($0.id)
                    return address.count == 12 && !uid.isEmpty && uid.contains(address)
                }
                if addressMatches.count == 1, let device = addressMatches.first {
                    return device.name
                }
                // Some audio drivers omit the address from the UID. Use a unique exact name.
                let nameMatches = audio.filter {
                    guard let name = output.name else { return false }
                    return $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
                }
                if nameMatches.count == 1, let device = nameMatches.first { return device.name }
            }
            if !connected.isEmpty { return connected.map(\.name).joined(separator: ", ") }
            key = .compactOn
        case .poweredOff: key = .compactOff
        case .idle, .initializing: key = .compactLoading
        case .authorizationNotDetermined, .authorizationDenied, .authorizationRestricted: key = .compactNoAccess
        case .failed, .unavailable: key = .compactUnavailable
        }
        return localization.string(key)
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
