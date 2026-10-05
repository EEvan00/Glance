// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    @EnvironmentObject private var localization: Localization

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
                Link(destination: AppMetadata.authorURL) {
                    Label(AppMetadata.authorName, systemImage: "person.crop.circle")
                }
                Link(destination: AppMetadata.upstreamURL) {
                    Label(localization.string(.settingsAboutUpstream), systemImage: "heart")
                }
            }.buttonStyle(.bordered).controlSize(.small)

        }
    }
}
