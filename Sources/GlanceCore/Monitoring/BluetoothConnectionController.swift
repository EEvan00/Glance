import Foundation
import IOBluetooth

protocol BluetoothConnectionManaging: AnyObject {
    func setConnected(_ connected: Bool, deviceID: String, completion: @escaping @Sendable (Bool) -> Void)
}

/// Uses only paired devices and public IOBluetooth connection APIs. Blocking
/// connection requests run off the main thread so the popup stays responsive.
final class IOBluetoothConnectionManager: BluetoothConnectionManaging, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Glance.BluetoothConnectionManager")

    func setConnected(_ connected: Bool, deviceID: String, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
                  let device = paired.first(where: { $0.addressString == deviceID }) else {
                completion(false)
                return
            }
            if device.isConnected() == connected {
                completion(true)
                return
            }
            let result = connected ? device.openConnection() : device.closeConnection()
            completion(result == kIOReturnSuccess)
        }
    }
}
