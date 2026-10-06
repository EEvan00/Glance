import CoreAudio
import Foundation

@MainActor
protocol BluetoothDeviceVolumeControlling: AnyObject {
    func outputDevices() -> [AudioOutputDevice]
    func setVolume(_ scalar: Double, deviceID: AudioDeviceID) -> Bool
}

@MainActor
final class BluetoothVolumeRestorer {
    private struct Snapshot {
        let uid: String
        let scalar: Double
    }
    private let audio: any BluetoothDeviceVolumeControlling
    private var saved: [String: Snapshot] = [:]

    init(audio: any BluetoothDeviceVolumeControlling = CoreAudioOutputController()) {
        self.audio = audio
    }

    func capture(_ device: BluetoothDevice) {
        // Never identify an output by its transient numeric CoreAudio ID.
        // Prefer the Bluetooth address embedded in its persistent UID.
        let outputs = audio.outputDevices()
        let address = normalized(device.id)
        let matches = outputs.filter {
            guard let uid = $0.uid else { return false }
            return !address.isEmpty && normalized(uid).contains(address)
        }
        let output = matches.count == 1 ? matches.first : nil
        guard let output, let uid = output.uid, let scalar = output.volume,
              scalar.isFinite, (0...1).contains(scalar) else {
            saved.removeValue(forKey: device.id)
            return
        }
        saved[device.id] = Snapshot(uid: uid, scalar: scalar)
    }

    /// nil means the reconnected audio endpoint has not appeared yet.
    /// The caller retries; it never writes to a fallback output device.
    func restore(_ deviceID: String) -> Bool? {
        guard let snapshot = saved[deviceID] else { return true }
        guard let output = audio.outputDevices().first(where: { $0.uid == snapshot.uid }) else { return nil }
        return audio.setVolume(snapshot.scalar, deviceID: output.id) ? true : nil
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
