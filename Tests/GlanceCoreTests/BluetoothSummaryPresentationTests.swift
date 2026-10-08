import XCTest
@testable import GlanceCore

@MainActor
final class BluetoothSummaryPresentationTests: XCTestCase {
    func testPoweredOnWithoutConnectionsDisplaysOn() {
        XCTAssertEqual(summary([], availability: .available), "On")
    }

    func testConnectedDevicesReplaceOnWithTheirNames() {
        let devices = [BluetoothDevice(id: "1", name: "Headphones", kind: .audio, isConnected: true), BluetoothDevice(id: "2", name: "Keyboard", kind: .peripheral, isConnected: true)]
        XCTAssertEqual(summary(devices, availability: .available), "Headphones, Keyboard")
    }

    func testPoweredOffDoesNotShowStaleConnectedDevice() {
        XCTAssertEqual(summary([BluetoothDevice(id: "1", name: "Headphones", kind: .audio, isConnected: true)], availability: .poweredOff), "Off")
    }

    func testCurrentBluetoothAudioOutputTakesPriorityOverOtherConnectedDevices() {
        let devices = [
            BluetoothDevice(id: "AA-BB-CC-DD-EE-FF", name: "Headphones", kind: .audio, isConnected: true),
            BluetoothDevice(id: "11-22-33-44-55-66", name: "Speaker", kind: .audio, isConnected: true),
            BluetoothDevice(id: "keyboard", name: "Keyboard", kind: .peripheral, isConnected: true)
        ]
        let outputs = [AudioOutputDevice(id: 10, name: "Renamed output",
            uid: "Bluetooth_AA:BB:CC:DD:EE:FF", isCurrent: true)]
        XCTAssertEqual(summary(devices, availability: .available, outputs: outputs), "Headphones")
    }

    func testBuiltInOutputFallsBackToConnectedPeripheralNames() {
        let devices = [BluetoothDevice(id: "keyboard", name: "Keyboard", kind: .peripheral, isConnected: true)]
        let outputs = [AudioOutputDevice(id: 10, name: "MacBook Speakers", uid: "BuiltInSpeakerDevice", isCurrent: true)]
        XCTAssertEqual(summary(devices, availability: .available, outputs: outputs), "Keyboard")
    }

    private func summary(_ devices: [BluetoothDevice], availability: BluetoothAvailability, outputs: [AudioOutputDevice] = []) -> String {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        return BluetoothSummaryPresentation.text(devices: devices, availability: availability, localization: localization, outputs: outputs)
    }
}
