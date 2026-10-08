import SwiftUI

struct PersonalHotspotSection<Details: View>: View {
    @ObservedObject var controller: PersonalHotspotController
    @EnvironmentObject private var localization: Localization
    let currentSSID: String?
    let disabled: Bool
    let onDisconnect: () -> Void
    let onSelect: (PersonalHotspot) -> Void
    @ViewBuilder let details: () -> Details

    private var visibleDevices: [PersonalHotspot] {
        var devices = controller.devices
        if let currentSSID, !devices.contains(where: { $0.name == currentSSID }),
           let fallback = PersonalHotspot(row: ["id": "current-hotspot", "name": currentSSID]) {
            devices.insert(fallback, at: 0)
        }
        return devices
    }

    var body: some View {
        if !visibleDevices.isEmpty {
            Text(localization.string(.wifiPersonalHotspot))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(visibleDevices) { device in
                Button {
                    if device.name == currentSSID && controller.connectingID == nil { onDisconnect() }
                    else { onSelect(device) }
                } label: {
                    HStack(spacing: 8) {
                        Group {
                            if controller.connectingID == device.id && !controller.isCancelling {
                                ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 22, height: 22)
                                        .background(Color.gray.opacity(0.55), in: Circle())
                            } else {
                                Image(systemName: "personalhotspot.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, device.name == currentSSID ? Color.blue : Color.gray.opacity(0.55))
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .frame(width: 22, height: 22)
                        Text(device.name).lineLimit(1).truncationMode(.tail).foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        if controller.connectingID != device.id {
                            if let signal = device.signal {
                                HStack(alignment: .bottom, spacing: 2) {
                                    ForEach(0..<4) { index in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.primary.opacity(index < signal ? 0.65 : 0.18))
                                            .frame(width: 3, height: CGFloat(4 + index * 3))
                                    }
                                }
                                .accessibilityLabel("\(signal)/4")
                            }
                            if let cellular = device.cellular {
                                Text(cellular).font(.caption)
                            }
                            if let battery = device.battery {
                                Image(systemName: batterySymbol(battery))
                                    .help("\(battery)%")
                                    .accessibilityLabel("\(battery)%")
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PopupHoverButtonStyle())
                .disabled(disabled && controller.connectingID == nil)
                if device.name == currentSSID { details() }
            }
            if controller.failed {
                Text(localization.string(.wifiConnectionFailed)).font(.caption).foregroundStyle(.red)
            }
            Divider()
        }
    }

    private func batterySymbol(_ percentage: Int) -> String {
        switch percentage {
        case 0..<13: "battery.0percent"
        case 13..<38: "battery.25percent"
        case 38..<63: "battery.50percent"
        case 63..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
