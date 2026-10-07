import SwiftUI

struct UpdatesSettingsPane: View {
    var body: some View {
        PreferencesPane { UpdateSettingsControls() }
    }
}

struct UpdateSettingsControls: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreferenceCheckboxRow(
                label: .settingsUpdatesAutomatic,
                isOn: updaterManager.automaticallyChecksForUpdatesBinding
            )
            .disabled(!updaterManager.canCheckForUpdates)

            Button(localization.string(.settingsUpdatesCheck)) {
                updaterManager.checkForUpdates()
            }
            .buttonStyle(.bordered)
            .disabled(!updaterManager.canCheckForUpdates)
        }
    }
}
