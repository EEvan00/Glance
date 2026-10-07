// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject private var localization: Localization

    @State private var confirmsUninstall = false
    @State private var isUninstalling = false
    @State private var uninstallError: String?

    var body: some View {
        PreferencesPane {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 112, height: 112)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(AppMetadata.name)
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        localization.format(
                            .settingsAboutVersion,
                            AppMetadata.versionDisplayString
                        )
                    )
                    .font(.system(size: 11, weight: .light))

                    Text(localization.string(.settingsAboutDescription))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(localization.string(.settingsAboutCopyright))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 8) {
                Link(destination: URL(string: "https://glance.gadels.com")!) {
                    Label(localization.string(.settingsAboutWebsite), systemImage: "globe")
                }
                Link(destination: AppMetadata.authorURL) {
                    Label(AppMetadata.authorName, systemImage: "person.crop.circle")
                }
                Link(destination: AppMetadata.upstreamURL) {
                    Label(localization.string(.settingsAboutUpstream), systemImage: "heart")
                }
            }.buttonStyle(.bordered).controlSize(.small)

            if UpdaterManager.isEnabled || UninstallCoordinator.supportsCurrentApplication {
                Divider()
                HStack(alignment: .bottom, spacing: 12) {
                    if UpdaterManager.isEnabled {
                        UpdateSettingsControls()
                    }
                    Spacer(minLength: 12)
                    if UninstallCoordinator.supportsCurrentApplication {
                        Button(localization.string(.settingsUninstall)) {
                            confirmsUninstall = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isUninstalling)
                    }
                }
            }

        }
        .alert(localization.string(.settingsUninstallTitle), isPresented: $confirmsUninstall) {
            Button(localization.string(.settingsUninstallConfirm), role: .destructive) {
                isUninstalling = true
                Task { @MainActor in
                    do { try await UninstallCoordinator.live.uninstall() }
                    catch {
                        uninstallError = error.localizedDescription
                        isUninstalling = false
                    }
                }
            }
            Button(localization.string(.settingsWeatherOpenShortcut)) {
                NSWorkspace.shared.open(URL(string: "shortcuts://")!)
            }
            Button(localization.string(.commonCancel), role: .cancel) {}
        } message: {
            Text(localization.string(.settingsUninstallMessage) + "\n\n" + localization.string(.settingsUninstallShortcuts))
        }
        .alert(localization.string(.settingsUninstallError), isPresented: Binding(
            get: { uninstallError != nil },
            set: { if !$0 { uninstallError = nil } }
        )) {
            Button("OK") { uninstallError = nil }
        } message: {
            Text(uninstallError ?? "")
        }
    }
}
