// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import SwiftUI

struct BluetoothStatusView: View {
    @ObservedObject var controller: BluetoothDeviceController
    @EnvironmentObject private var localization: Localization
    let onOpenDetails: () -> Void
    let onOpenBluetoothSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenDetails) {
                HStack(spacing: 10) {
                    Image(systemName: "bluetooth")
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.string(.bluetoothTitle))
                            .font(.headline)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer()
                    PopupChevron()
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(localization.string(.bluetoothTitle)), \(summary)")

            Button(localization.string(.bluetoothActionOpenSettings), systemImage: "gearshape", action: onOpenBluetoothSettings)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(0.78))
                .help(localization.string(.bluetoothActionOpenSettings))
                .frame(width: 24, height: 24)
        }
        .task { controller.activateIfAuthorized() }
    }

    private var summary: String {
        switch controller.availability {
        case .idle:
            return localization.string(.bluetoothAuthorizationNotDetermined)
        case .initializing:
            return localization.string(.bluetoothInitializing)
        case .authorizationNotDetermined:
            return localization.string(.bluetoothAuthorizationNotDetermined)
        case .authorizationDenied:
            return localization.string(.bluetoothAuthorizationDenied)
        case .authorizationRestricted:
            return localization.string(.bluetoothAuthorizationRestricted)
        case .available:
            let devices = controller.connectedDevices
            if devices.isEmpty { return localization.string(.compactOn) }
            return devices.map(\.name).joined(separator: ", ")
        case .poweredOff:
            return localization.string(.bluetoothOff)
        case .unavailable:
            return localization.string(.bluetoothUnavailable)
        case .failed:
            return localization.string(.bluetoothReadFailed)
        }
    }
}

struct BluetoothDeviceListView: View {
    @ObservedObject var controller: BluetoothDeviceController
    @ObservedObject var settings: SettingsStore
    let volume: VolumeStatus
    let onSelectOutputDevice: (AudioOutputDevice) -> Void
    let onOpenDeviceSettings: (BluetoothDevice) -> Void
    @EnvironmentObject private var localization: Localization
    let onBack: () -> Void
    let onOpenBluetoothSettings: () -> Void

    var body: some View {
        let groups = BluetoothDevicePresentation.grouped(controller.devices)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: CompactPopupLayout.gap) {
                Button(action: onBack) {
                    PopupChevron(symbol: "chevron.backward")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localization.string(.commonBack))
                Button(action: onBack) {
                    Text(localization.string(.bluetoothTitle))
                        .font(.headline)
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: { controller.refresh(forceMetadata: true) }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(PopupHoverButtonStyle())
                .accessibilityLabel(localization.string(.bluetoothRefresh))
            }

            VStack(alignment: .leading, spacing: 10) {
                if controller.availability == .available && !controller.devices.isEmpty {
                    section(localization.string(.bluetoothDevices), devices: groups.connected + groups.disconnected)
                }
                message
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                PopupDivider()
                Button(localization.string(.bluetoothActionOpenSettings), action: onOpenBluetoothSettings)
                    .popupFooterInsets()
                    .buttonStyle(PopupHoverButtonStyle(fullWidth: true))
            }
        }
        .onAppear { controller.activate() }
        .onDisappear { controller.deactivate() }
    }

    private func section(_ title: String, devices: [BluetoothDevice]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.78))
            ForEach(devices) { device in
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        controller.toggleConnection(to: device)
                    } label: {
                        HStack(spacing: 10) {
                            Group {
                                if controller.queuedConnectionDevice?.id == device.id || (controller.connectionDeviceID == device.id && controller.cancellingConnectionDeviceID != device.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 22, height: 22)
                                        .background(Color.gray.opacity(0.55), in: Circle())
                                } else {
                                    Image(systemName: BluetoothDevicePresentation.symbolName(for: device))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(device.isConnected ? Color.blue : Color.gray.opacity(0.55), in: Circle())
                                }
                            }
                            .frame(width: 22, height: 22)
                            Text(device.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PopupHoverButtonStyle())
                    .accessibilityLabel("\(device.name), \(localization.string(device.isConnected ? .bluetoothDisconnect : .bluetoothConnect))")

                    if controller.connectionFailedDeviceID == device.id {
                        Text(localization.string(.bluetoothConnectionFailed))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if device.isConnected && BluetoothDevicePresentation.isAudioDevice(device) {
                        Text(localization.string(.volumeOutputTitle))
                            .font(.caption.weight(.semibold))
                        OutputDeviceList(settings: settings, devices: volume.outputDevices, onSelect: onSelectOutputDevice)
                        Button(localization.string(BluetoothDevicePresentation.isAirPods(device) ? .bluetoothDeviceSettings : .bluetoothActionOpenSettings)) {
                            onOpenDeviceSettings(device)
                        }
                        .buttonStyle(PopupHoverButtonStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var message: some View {
        switch controller.availability {
        case .idle, .initializing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(localization.string(.bluetoothInitializing))
            }
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.78))
        case .authorizationNotDetermined:
            Text(localization.string(.bluetoothAuthorizationNotDetermined))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.78))
        case .authorizationDenied:
            Button(localization.string(.bluetoothAuthorizationDenied), action: onOpenBluetoothSettings)
                .buttonStyle(.link)
                .font(.caption)
        case .authorizationRestricted:
            Text(localization.string(.bluetoothAuthorizationRestricted))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.78))
        case .available where controller.devices.isEmpty:
            Text(localization.string(.bluetoothNoDevices))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.78))
        case .poweredOff:
            Text(localization.string(.bluetoothOff))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.78))
        case .unavailable:
            Text(localization.string(.bluetoothUnavailable))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.78))
        case .failed:
            Text(localization.string(.bluetoothReadFailed))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.78))
        case .available:
            EmptyView()
        }
    }

}
