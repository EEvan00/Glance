// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import AppKit
import SwiftUI

struct BasicsSettingsPane: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var localization: Localization
    @ObservedObject private var launchAtLogin: LaunchAtLoginManager

    init(
        store: SettingsStore,
        localization: Localization,
        launchAtLogin: LaunchAtLoginManager = .shared
    ) {
        self.store = store
        self.localization = localization
        self._launchAtLogin = ObservedObject(wrappedValue: launchAtLogin)
    }

    var body: some View {
        PreferencesPane {
            launchAtLoginSection

            Divider()

            PreferenceRow(
                label: .settingsLanguage,
                description: .settingsLanguageDescription,
                placesControlInline: true
            ) {
                Picker(
                    localization.string(.settingsLanguage),
                    selection: Binding(
                        get: { localization.preference },
                        set: { newPreference in
                            localization.setPreference(newPreference)
                        }
                    )
                ) {
                    Text(localization.string(.settingsLanguageFollowSystem))
                        .tag(LanguagePreference.system)

                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName)
                            .tag(LanguagePreference.language(language))
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            Divider()

            PreferenceRow(label: .settingsPopupUtility, description: .settingsUtilityCardDescription, placesControlInline: true) {
                Picker(localization.string(.settingsPopupUtility), selection: $store.popupUtility) {
                    ForEach(PopupUtility.allCases) { utility in
                        Text(localization.string(utility.labelKey)).tag(utility)
                    }
                }.labelsHidden().frame(width: 220)
            }

            Divider()

            utilityRowPicker(.settingsUtilityFirstRow, selection: $store.firstUtilityRow, other: store.secondUtilityRow)
            utilityRowPicker(.settingsUtilitySecondRow, selection: $store.secondUtilityRow, other: store.firstUtilityRow)
            Text(localization.string(.settingsUtilityStripPosition))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            PreferenceCheckboxRow(label: .settingsCardTextAutoShrink, isOn: $store.automaticallyShrinksCardText)

            Divider()

            refreshIntervalSection

            Divider()

            PreferenceRow(label: .settingsClockFormat, placesControlInline: true) {
                Picker(localization.string(.settingsClockFormat), selection: $store.uses24HourClock) {
                    Text(localization.string(.settingsClock12)).tag(false)
                    Text(localization.string(.settingsClock24)).tag(true)
                }
                .labelsHidden()
                .frame(width: 180)
            }

            PreferenceCheckboxRow(label: .settingsClockSeconds, isOn: $store.showsClockSeconds)

            Divider()
            QuickActionSettingsView(store: store)

            Divider()
            PreferenceRow(label: .settingsWeatherShortcut) {
                VStack(alignment: .leading, spacing: 12) {
                    PreferenceRow(label: .settingsTemperatureUnit, placesControlInline: true) {
                        Picker(localization.string(.settingsTemperatureUnit), selection: $store.temperatureUnit) {
                            ForEach(TemperatureUnit.allCases) { unit in
                                Text(unit.symbol).tag(unit)
                            }
                        }.labelsHidden().frame(width: 220)
                    }
                    WeatherShortcutInstallButtons(localization: localization, purpose: .settings)
                }
            }


        }
    }

    private func utilityRowPicker(_ key: LocalizationKey, selection: Binding<PopupUtilityRow>, other: PopupUtilityRow) -> some View {
        PreferenceRow(label: key, placesControlInline: true) {
            Picker(localization.string(key), selection: selection) {
                ForEach(PopupUtilityRow.allCases.filter { $0 == .none || $0 != other }) { row in
                    Text(localization.string(row.labelKey)).tag(row)
                }
            }.labelsHidden().frame(width: 220)
        }
    }

    private var refreshIntervalSection: some View {
        PreferenceRow(
            label: .settingsRefreshInterval,
            description: .settingsRefreshIntervalDescription
        ) {
            HStack(spacing: 12) {
                Slider(
                    value: $store.refreshIntervalSeconds,
                    in: SettingsStore.refreshIntervalRange,
                    step: 5
                )
                .accessibilityLabel(localization.string(.settingsRefreshInterval))
                .accessibilityValue(
                    localization.format(
                        .settingsRefreshIntervalValue,
                        Int(store.refreshIntervalSeconds)
                    )
                )

                Text(
                    localization.format(
                        .settingsRefreshIntervalValue,
                        Int(store.refreshIntervalSeconds)
                    )
                )
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .trailing)
            }
        }
    }

    private var launchAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PreferenceCheckboxRow(
                label: .settingsLaunchAtLogin,
                description: .settingsLaunchAtLoginDescription,
                isOn: launchAtLogin.isEnabledBinding
            )
            .disabled(!launchAtLogin.isAvailable)

            if launchAtLogin.status == .requiresApproval {
                notice(
                    .settingsLaunchAtLoginRequiresApproval,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )

                Button(localization.string(.settingsLaunchAtLoginOpenLoginItems)) {
                    launchAtLogin.openLoginItemsSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.leading, 18)
            }

            if launchAtLogin.didFailLastOperation {
                notice(
                    .settingsLaunchAtLoginFailure,
                    systemImage: "exclamationmark.octagon.fill",
                    tint: .red
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The user may change the login item in System Settings while we're not
        // looking, so re-read the system state whenever the pane appears.
        .onAppear { launchAtLogin.refresh() }
    }

    private func notice(
        _ key: LocalizationKey,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            Text(localization.string(key))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
