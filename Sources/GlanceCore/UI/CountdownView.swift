import AppKit
import SwiftUI

struct CountdownView: View {
    @ObservedObject var controller: CountdownController
    @EnvironmentObject private var localization: Localization
    let onBack: () -> Void
    @State private var customMinutes = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onBack) { PopupChevron(symbol: "chevron.backward") }
                    .buttonStyle(.plain).accessibilityLabel(localization.string(.commonBack))
                Text(localization.string(.timerTitle)).font(.headline)
                Spacer()
            }
            if controller.isRunning || controller.isPaused || controller.isFinished {
                VStack(spacing: 8) {
                    Text(CountdownController.display(controller.remaining))
                        .font(.system(size: 36, weight: .light, design: .rounded)).monospacedDigit()
                    if controller.isFinished || controller.isPaused {
                        Text(localization.string(controller.isFinished ? .timerFinished : .timerPaused))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    PopupProgressBar(percent: controller.duration > 0 ? controller.remaining / controller.duration * 100 : 0)
                    HStack {
                        if !controller.isFinished {
                            Button(localization.string(controller.isRunning ? .timerPause : .timerResume)) {
                                if controller.isRunning { controller.pause() } else { controller.resume() }
                            }
                        }
                        Button(localization.string(controller.isFinished ? .timerDone : .timerCancel)) { controller.cancel() }
                    }.buttonStyle(.bordered)
                }.frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach([1, 5, 10, 15, 25, 30], id: \.self) { minutes in
                        Button(localization.format(.timerMinutes, minutes)) { controller.start(minutes: minutes) }
                            .buttonStyle(.plain).frame(maxWidth: .infinity).padding(.vertical, 10).systemModuleSurface()
                    }
                }
                PopupDivider()
                HStack(spacing: 8) {
                    TextField(localization.string(.timerCustom), value: $customMinutes, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 56)
                        .accessibilityLabel(localization.string(.timerCustom))
                    Text(localization.string(.timerMinuteUnit)).font(.subheadline)
                    Spacer()
                    Button(localization.string(.timerStart)) { controller.start(minutes: customMinutes) }
                        .disabled(!(1...1440).contains(customMinutes))
                }
            }
            if controller.notificationsUnavailable {
                VStack(alignment: .leading, spacing: 6) {
                    PopupDivider()
                    Text(localization.string(.timerNotificationHelp)).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                    Button(localization.string(.timerOpenNotifications)) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
