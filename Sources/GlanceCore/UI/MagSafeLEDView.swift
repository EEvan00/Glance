// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import SwiftUI

struct MagSafeLEDView: View {
    @ObservedObject var controller: MagSafeLEDController
    @EnvironmentObject private var localization: Localization
    let onBack: () -> Void
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if showsHeader { header }
                content
                if let errorKey {
                    Text(localization.string(errorKey))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.bottom, CompactPopupLayout.contentInset)
    }

    private var header: some View {
        HStack(spacing: CompactPopupLayout.gap) {
            Button(action: onBack) {
                PopupChevron(symbol: "chevron.backward")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localization.string(.commonBack))
            Text(localization.string(.magSafeTitle))
                .font(.headline)
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.availability {
        case .unsupported:
            Text(localization.string(.magSafeUnsupported))
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.78))
        case .needsInstallation:
            Toggle(localization.string(.magSafeLight), isOn: .constant(true))
                .disabled(true)
                .help(localization.string(.magSafePrivateAPIWarning))
            Text(localization.string(.magSafeInstallExplanation))
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.78))
            Button(localization.string(.magSafeInstallHelper)) {
                controller.installHelper()
            }
            .disabled(controller.isBusy)
        case .requiresApproval:
            Text(localization.string(.settingsLaunchAtLoginRequiresApproval))
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.78))
            Button(localization.string(.settingsLaunchAtLoginOpenLoginItems)) {
                controller.openHelperSettings()
            }
        case .ready:
            Toggle(
                localization.string(.magSafeLight),
                isOn: Binding(
                    get: { controller.isLightEnabled },
                    set: { enabled in
                        controller.setLightEnabled(enabled)
                    }
                )
            )
            .disabled(controller.isBusy)
            .help(localization.string(.magSafePrivateAPIWarning))
            Button(localization.string(.magSafeUninstallHelper)) {
                if controller.needsHelperRecovery {
                    controller.removeUnresponsiveHelper()
                } else {
                    controller.uninstallHelper()
                }
            }
            .buttonStyle(.bordered)
            .disabled(controller.isBusy)
        }

        if controller.isBusy {
            ProgressView()
                .controlSize(.small)
        }
    }

    private var errorKey: LocalizationKey? {
        switch controller.error {
        case .installFailed: .magSafeErrorInstall
        case .uninstallFailed: .magSafeErrorUninstall
        case .writeFailed: .magSafeErrorWrite
        case nil: nil
        }
    }
}
