import SwiftUI

/// Module-specific preferences keep their existing persisted keys and consumers.
struct FooterModulePreferencesView: View {
    let kind: FooterModuleKind
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch kind {
            case .clock:
                LabeledContent(localization.string(.settingsClockFormat)) {
                    Picker(localization.string(.settingsClockFormat), selection: $store.uses24HourClock) {
                        Text(localization.string(.settingsClock12)).tag(false)
                        Text(localization.string(.settingsClock24)).tag(true)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                PreferenceCheckboxRow(label: .settingsClockSeconds, isOn: $store.showsClockSeconds)
            case .weather:
                LabeledContent(localization.string(.weatherSource)) {
                    Picker(localization.string(.weatherSource), selection: $store.weatherSource) {
                        ForEach(WeatherSource.allCases) { source in
                            Text(localization.string(source.labelKey)).tag(source)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                LabeledContent(localization.string(.settingsTemperatureUnit)) {
                    Picker(localization.string(.settingsTemperatureUnit), selection: $store.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                if store.weatherSource == .shortcuts {
                    Text(localization.string(.settingsWeatherShortcut)).font(.subheadline.weight(.medium))
                    WeatherShortcutInstallButtons(localization: localization, purpose: .settings)
                } else {
                    Text(localization.string(NativeWeatherConfiguration.isAvailable ? .weatherNativeHelp : .weatherNativeNotConfigured))
                        .font(.caption).foregroundStyle(.secondary)
                }
            default:
                EmptyView()
            }
        }
    }
}
