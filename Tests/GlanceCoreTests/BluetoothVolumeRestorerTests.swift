import CoreAudio
import XCTest
@testable import GlanceCore

@MainActor
final class BluetoothVolumeRestorerTests: XCTestCase {
    func testReconnectUsesPersistentUIDInsteadOfDefaultOutputOrOldID() {
        let audio = BluetoothVolumeAudioStub()
        let restorer = BluetoothVolumeRestorer(audio: audio)
        let device = BluetoothDevice(id: "AA-BB-CC-DD-EE-FF", name: "AirPods", kind: .audio, isConnected: true)
        audio.devices = [output(id: 10, uid: "AA:BB:CC:DD:EE:FF-output", volume: 0.12)]
        restorer.capture(device)
        audio.devices = [output(id: 10, uid: "BuiltInSpeaker", volume: 0.6)]
        XCTAssertNil(restorer.restore(device.id))
        XCTAssertTrue(audio.writes.isEmpty)
        audio.devices.append(output(id: 99, uid: "AA:BB:CC:DD:EE:FF-output", volume: 0.5))
        XCTAssertEqual(restorer.restore(device.id), true)
        XCTAssertEqual(audio.writes.first?.id, 99)
        XCTAssertEqual(audio.writes.first?.scalar, 0.12)
    }

    func testUnavailableOrAmbiguousIdentityNeverWritesVolume() {
        let audio = BluetoothVolumeAudioStub()
        let restorer = BluetoothVolumeRestorer(audio: audio)
        let device = BluetoothDevice(id: "AA-BB-CC-DD-EE-FF", name: "AirPods", kind: .audio, isConnected: true)
        audio.devices = [output(id: 10, uid: "BuiltInSpeaker", volume: 0.6)]
        restorer.capture(device)
        XCTAssertEqual(restorer.restore(device.id), true)
        XCTAssertTrue(audio.writes.isEmpty)
        audio.devices = [output(id: 11, uid: "AA:BB:CC:DD:EE:FF-output", volume: 0.12),
                         output(id: 12, uid: "AA:BB:CC:DD:EE:FF-other", volume: 0.2)]
        restorer.capture(device)
        XCTAssertEqual(restorer.restore(device.id), true)
        XCTAssertTrue(audio.writes.isEmpty)
    }

    func testClosingAndReopeningPopupDoesNotDiscardCapturedVolume() async {
        let device = BluetoothDevice(id: "AA-BB-CC-DD-EE-FF", name: "AirPods", kind: .audio, isConnected: true)
        let audio = BluetoothVolumeAudioStub()
        audio.devices = [output(id: 10, uid: "AA:BB:CC:DD:EE:FF-output", volume: 0.12)]
        let restorer = BluetoothVolumeRestorer(audio: audio)
        let reader = VolumeReconnectReader(device: device)
        let connections = VolumeReconnectConnections(reader: reader)
        let controller = BluetoothDeviceController(worker: reader, connections: connections,
            volumeRestorer: restorer, stateMonitor: VolumeReconnectState())
        controller.activate()
        for _ in 0..<100 where controller.devices.isEmpty { await Task.yield() }
        controller.toggleConnection(to: device)
        for _ in 0..<100 where controller.connectionDeviceID != nil { await Task.yield() }
        XCTAssertFalse(controller.devices[0].isConnected)
        controller.deactivate()
        audio.devices = [output(id: 99, uid: "AA:BB:CC:DD:EE:FF-output", volume: 0.5)]
        controller.activate()
        for _ in 0..<100 where controller.availability != .available { await Task.yield() }
        controller.toggleConnection(to: controller.devices[0])
        for _ in 0..<100 where controller.connectionDeviceID != nil { await Task.yield() }
        XCTAssertTrue(controller.devices[0].isConnected)
        XCTAssertNil(controller.connectionFailedDeviceID)
        XCTAssertEqual(audio.writes.first?.id, 99)
        XCTAssertEqual(audio.writes.first?.scalar, 0.12)
        controller.deactivate()
    }

    private func output(id: AudioDeviceID, uid: String, volume: Double) -> AudioOutputDevice {
        AudioOutputDevice(id: id, name: "Output", uid: uid, isCurrent: true, volume: volume)
    }
}

@MainActor
private final class BluetoothVolumeAudioStub: BluetoothDeviceVolumeControlling {
    var devices: [AudioOutputDevice] = []
    var writes: [(id: AudioDeviceID, scalar: Double)] = []
    func outputDevices() -> [AudioOutputDevice] { devices }
    func setVolume(_ scalar: Double, deviceID: AudioDeviceID) -> Bool {
        writes.append((deviceID, scalar)); return true
    }
}
private final class VolumeReconnectReader: BluetoothPairedDeviceReading {
    var device: BluetoothDevice
    init(device: BluetoothDevice) { self.device = device }
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) { completion(.success([device])) }
}
private final class VolumeReconnectConnections: BluetoothConnectionManaging {
    let reader: VolumeReconnectReader
    init(reader: VolumeReconnectReader) { self.reader = reader }
    func setConnected(_ connected: Bool, deviceID: String, completion: @escaping @Sendable (Bool) -> Void) {
        reader.device = BluetoothDevice(id: reader.device.id, name: reader.device.name, kind: .audio, isConnected: connected)
        completion(true)
    }
}
@MainActor
private final class VolumeReconnectState: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}
