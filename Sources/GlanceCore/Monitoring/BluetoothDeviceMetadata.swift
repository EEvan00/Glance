import Foundation

struct BluetoothDeviceMetadata: Equatable, Sendable {
    let vendorID: Int?
    let productID: Int?
    let minorType: String?
    let name: String?

    init(vendorID: Int?, productID: Int?, minorType: String?, name: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.minorType = minorType
        self.name = name
    }

    static func addressKey(_ address: String) -> String {
        address.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
    }

    static func parse(_ data: Data) -> [String: BluetoothDeviceMetadata] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        var result: [String: BluetoothDeviceMetadata] = [:]
        for controller in controllers {
            for group in ["device_not_connected", "device_connected"] {
                guard let devices = controller[group] as? [[String: Any]] else { continue }
                for device in devices {
                    for (name, value) in device {
                        guard let fields = value as? [String: Any],
                              let address = fields["device_address"] as? String, !address.isEmpty else { continue }
                        result[addressKey(address)] = BluetoothDeviceMetadata(
                            vendorID: hexID(fields["device_vendorID"]),
                            productID: hexID(fields["device_productID"]),
                            minorType: fields["device_minorType"] as? String,
                            name: name.isEmpty ? nil : name
                        )
                    }
                }
            }
        }
        return result
    }

    private static func hexID(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        return text.hasPrefix("0x") ? Int(text.dropFirst(2), radix: 16) : Int(text)
    }
}

/// Reads the same OS report exposed by System Information. No BLE scanning,
/// extra permissions, private setters, or entitlement changes are required.
enum SystemProfilerBluetoothMetadata {
    static func read() -> [String: BluetoothDeviceMetadata] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        defer { timeout.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count <= 2_000_000 else { return [:] }
        return BluetoothDeviceMetadata.parse(data)
    }
}
