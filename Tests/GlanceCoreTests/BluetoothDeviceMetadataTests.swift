import AppKit
import XCTest
@testable import GlanceCore

final class BluetoothDeviceMetadataTests: XCTestCase {
    func testAirPodsReportMatchesRenamedDevice() {
        let data = Data(#"""
        {"SPBluetoothDataType":[{"device_connected":[{"Renamed earbuds":{
          "device_address":"AA:BB:CC:DD:EE:FF", "device_vendorID":"0x004C", "device_productID":"0x2013",
          "device_minorType":"Headphones"
        }}]}]}
        """#.utf8)
        let metadata = BluetoothDeviceMetadata.parse(data)[BluetoothDeviceMetadata.addressKey("aa-bb-cc-dd-ee-ff")]
        let device = BluetoothDevice(id: "id", name: "Renamed earbuds", kind: .unknown, isConnected: true, metadata: metadata)
        XCTAssertEqual(BluetoothDevicePresentation.symbolName(for: device), "airpods.gen3")
        XCTAssertEqual(metadata?.name, "Renamed earbuds")
        XCTAssertTrue(BluetoothDevicePresentation.isAudioDevice(device))
        XCTAssertNotNil(NSImage(systemSymbolName: BluetoothDevicePresentation.symbolName(for: device), accessibilityDescription: nil))
    }

    func testAccessoryFilterKeepsUnclassifiedMouseAndHidesPhones() {
        let phone = BluetoothDevice(id: "phone", name: "Phone", kind: .unknown, isConnected: false)
        let mouse = BluetoothDevice(id: "mouse", name: "Mouse", kind: .unknown, isConnected: false,
            metadata: BluetoothDeviceMetadata(vendorID: nil, productID: nil, minorType: "Mouse"))
        XCTAssertFalse(BluetoothDevicePresentation.isVisibleAccessory(phone))
        XCTAssertTrue(BluetoothDevicePresentation.isVisibleAccessory(mouse))
    }

    @MainActor
    func testAirPodsSettingsUsesDedicatedPane() {
        let device = BluetoothDevice(id: "pods", name: "AirPods", kind: .audio, isConnected: true)
        XCTAssertEqual(StatusBarController.bluetoothDeviceSettingsURLs(for: device).first?.absoluteString,
            "x-apple.systempreferences:com.apple.HeadphoneSettings")
    }

    func testUnknownProductsRetainCategoryIcon() {
        let device = BluetoothDevice(id: "id", name: "Headset", kind: .audio, isConnected: true,
            metadata: BluetoothDeviceMetadata(vendorID: 0x004C, productID: 0xFFFF, minorType: "Headphones"))
        XCTAssertEqual(BluetoothDevicePresentation.symbolName(for: device), "headphones")
        XCTAssertTrue(BluetoothDeviceMetadata.parse(Data("not json".utf8)).isEmpty)
    }
}
