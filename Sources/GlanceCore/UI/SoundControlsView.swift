import SwiftUI

struct SoundControlsView: View {
    @ObservedObject var store: SystemStatusStore
    @ObservedObject var settings: SettingsStore
    let onBack: () -> Void
    let onOpenSettings: () -> Void
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: CompactPopupLayout.gap) {
                Button(action: onBack) { PopupChevron(symbol: "chevron.backward") }
                    .buttonStyle(.plain).accessibilityLabel(localization.string(.commonBack))
                Text(localization.string(.soundTitle)).font(.headline)
            }
            CompactVolumeControlsView(store: store)
            PopupDivider()
            Text(localization.string(.volumeOutputTitle)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary.opacity(0.78))
            OutputDeviceList(settings: settings, devices: store.liveVolume.outputDevices, onSelect: { store.selectOutputDevice($0) })
            VStack(alignment: .leading, spacing: 0) {
                PopupDivider()
                Button(localization.string(.soundSettings), action: onOpenSettings)
                    .buttonStyle(.plain)
                    .popupFooterInsets()
            }
        }
    }
}
