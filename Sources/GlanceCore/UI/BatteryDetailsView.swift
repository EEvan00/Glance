import SwiftUI

struct BatteryDetailsView: View {
    let battery: BatteryStatus
    @ObservedObject var magSafeLED: MagSafeLEDController
    let onBack: () -> Void
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    @StateObject private var charging = BatteryChargingController()
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onBack) { PopupChevron(symbol: "chevron.backward") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localization.string(.commonBack))
                Button(action: onBack) {
                    Text(StatusPresentation.batteryTitle(battery, localization: localization))
                        .font(.headline)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            Label(StatusPresentation.batterySubtitle(battery, localization: localization),
                  systemImage: battery.indicatorSymbol ?? "battery.100")
                .font(.callout)

            if battery.isChargingPaused {
                Button(localization.string(.batteryChargeToFull)) {
                    Task {
                        await charging.chargeToFull(battery: battery)
                        onRefresh()
                    }
                }
                .disabled(!battery.canChargeToFull || charging.isRequesting || charging.result == .accepted)
                .help(localization.string(battery.canChargeToFull
                    ? .batteryChargeToFullExplanation : .batteryChargeToFullUnavailable))
            }
            if charging.isRequesting {
                ProgressView().controlSize(.small)
            } else if battery.isChargingPaused, let result = charging.result {
                Text(localization.string(result == .accepted
                    ? .batteryChargeRequestAccepted : .batteryChargeRequestFailed))
                    .font(.caption)
                    .foregroundStyle(result == .failed ? Color.red : Color.secondary)
            }
            Button(localization.string(.batteryActionOpenSettings), action: onOpenSettings)
                .buttonStyle(PopupHoverButtonStyle(fullWidth: true))
            Divider()
            Text(localization.string(.magSafeTitle))
                .font(.headline)
            MagSafeLEDView(controller: magSafeLED, onBack: onBack, showsHeader: false)
        }
        .onChange(of: battery.isChargingPaused) { _, paused in
            if !paused { charging.clearResult() }
        }
        .onChange(of: charging.result) { _, result in
            if result != nil && !battery.isChargingPaused { charging.clearResult() }
        }
        .task(id: battery.isChargingPaused && charging.result == .accepted) {
            guard battery.isChargingPaused, charging.result == .accepted else { return }
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            charging.reportResumeTimeout()
        }
    }
}
