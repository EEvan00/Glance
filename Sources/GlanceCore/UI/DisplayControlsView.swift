import SwiftUI

struct DisplayControlsView: View {
    @ObservedObject var brightness: BrightnessController
    let onBack: () -> Void
    @StateObject private var controller = DisplayControlsController()
    @State private var expandsPresets = false
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: CompactPopupLayout.gap) {
                Button(action: onBack) { PopupChevron(symbol: "chevron.backward") }
                    .buttonStyle(.plain).accessibilityLabel(localization.string(.commonBack))
                VStack(alignment: .leading, spacing: 3) {
                    Button(action: onBack) {
                        Text(localization.string(.displayTitle)).font(.headline)
                            .frame(height: 24, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button {
                        expandsPresets.toggle()
                    } label: {
                        HStack(spacing: CompactPopupLayout.gap) {
                            Text(controller.presets.first { $0.id == controller.activePreset }?.name ?? controller.displayName)
                                .font(.caption).foregroundStyle(.primary.opacity(0.78)).lineLimit(1)
                            Spacer()
                            if !controller.presets.isEmpty {
                                Image(systemName: expandsPresets ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.primary.opacity(0.85))
                                    .frame(width: 28, height: 24)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.presets.isEmpty)
                }
            }
            if expandsPresets {
                PopupDivider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.presets) { preset in
                            Button {
                                controller.select(preset)
                                brightness.refresh()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark").opacity(controller.activePreset == preset.id ? 1 : 0).frame(width: 16)
                                    Text(preset.name).font(.system(size: 12)).lineLimit(2)
                                    Spacer(minLength: 0)
                                }.padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(PopupHoverButtonStyle())
                        }
                    }
                }.frame(maxHeight: 250)
            }
            PopupDivider()
            BrightnessControlsView(controller: brightness)
            HStack {
                feature(0, label: .displayDarkMode, symbol: "circle.lefthalf.filled")
                Spacer(minLength: 4)
                feature(1, label: .displayNightShift, symbol: "sun.max")
                Spacer(minLength: 4)
                feature(2, label: .displayTrueTone, symbol: "sun.max.fill")
            }
            if controller.actionFailed { Text(localization.string(.displayActionFailed)).font(.caption).foregroundStyle(.primary.opacity(0.78)) }
            VStack(alignment: .leading, spacing: 0) {
                PopupDivider()
                Button(localization.string(.displaySettings)) { controller.openSettings() }
                    .popupFooterInsets()
                    .buttonStyle(PopupHoverButtonStyle(fullWidth: true))
            }
        }
        .onAppear { controller.refresh(); brightness.refresh() }
    }

    private func feature(_ index: Int, label: LocalizationKey, symbol: String) -> some View {
        Button { controller.toggle(index); brightness.refresh() } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(controller.states[index] == true ? Color.accentColor : Color.primary.opacity(0.08), in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                Text(localization.string(label)).font(.system(size: 10, weight: .medium))
                Text(localization.string(controller.states[index].map { $0 ? .displayOn : .displayOff } ?? .displayUnavailable))
                    .font(.system(size: 10)).foregroundStyle(.primary.opacity(0.78))
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).disabled(controller.states[index] == nil)
    }
}
