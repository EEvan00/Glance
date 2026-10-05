import SwiftUI

struct WeatherDetailsView: View {
    @ObservedObject var controller: WeatherController
    @ObservedObject var forecast: WeatherController
    @ObservedObject var settings: SettingsStore
    @EnvironmentObject private var localization: Localization
    let onBack: () -> Void
    let onOpenWeather: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: CompactPopupLayout.gap) {
                Button(action: onBack) { PopupChevron(symbol: "chevron.backward") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localization.string(.commonBack))
                Text(localization.string(.weatherTitle)).font(.headline)
                Spacer(minLength: 4)
                Text(forecast.snapshot?.location ?? localization.string(.weatherCurrentLocation))
                    .font(.caption).foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(1).truncationMode(.tail)
                    .help(forecast.snapshot?.location ?? localization.string(.weatherCurrentLocation))
                if controller.isLoading || forecast.isLoading { ProgressView().controlSize(.small) }
            }
            if let snapshot = forecast.snapshot ?? controller.snapshot {
                HStack(spacing: 12) {
                    Image(systemName: snapshot.symbol).font(.system(size: 28))
                        .accessibilityHidden(true)
                    Text(snapshot.temperatureText).font(.system(size: 28, weight: .medium))
                        .monospacedDigit()
                }
                detail(.weatherCondition, value: snapshot.appleCondition ?? localization.string(snapshot.conditionKey))
                if let updated = forecast.updatedAt ?? controller.updatedAt {
                    Text(localization.format(.weatherUpdated, updated.formatted(date: .omitted, time: .shortened)))
                        .font(.caption).foregroundStyle(.primary.opacity(0.78))
                }
            } else {
                WeatherShortcutInstallButtons(localization: localization)
                Text(localization.string(controller.isLoading ? .weatherLoading : .weatherUnavailable))
                    .foregroundStyle(.primary.opacity(0.78))
            }
            if let snapshot = forecast.snapshot {
                HStack {
                    if let low = snapshot.low {
                        Text("\(localization.string(.weatherLow)) \(WeatherSnapshot(temperature: low, code: 0, isDay: -1).temperatureText)")
                    }
                    Spacer()
                    if let high = snapshot.high {
                        Text("\(localization.string(.weatherHigh)) \(WeatherSnapshot(temperature: high, code: 0, isDay: -1).temperatureText)")
                    }
                }.font(.subheadline)
                if let hourly = snapshot.hourly, !hourly.isEmpty {
                    Text(localization.string(.weatherHourly)).font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(hourly) { hour in
                                VStack(spacing: 6) {
                                    Text(FooterClockFormatting.time(hour.date, uses24HourClock: settings.uses24HourClock))
                                        .foregroundStyle(.primary.opacity(0.78))
                                    Image(systemName: hour.symbol).font(.system(size: 16))
                                        .accessibilityHidden(true)
                                    Text(hour.temperatureText)
                                }.font(.caption).monospacedDigit()
                                    .frame(minWidth: 36)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("\(FooterClockFormatting.time(hour.date, uses24HourClock: settings.uses24HourClock)), \(hour.condition), \(hour.temperatureText)")
                                    .help(hour.condition)
                            }
                        }.padding(.vertical, 4)
                    }.scrollIndicators(.hidden).frame(height: 70)
                }
            } else if forecast.isUnavailable {
                Text(localization.string(.weatherForecastUnavailable)).font(.caption)
                    .foregroundStyle(.primary.opacity(0.78))
            }
            VStack(alignment: .leading, spacing: 0) {
                PopupDivider()
                Button(localization.string(.weatherOpenApp), action: onOpenWeather)
                    .buttonStyle(.plain)
                    .popupFooterInsets()
            }
        }
        .onAppear { forecast.setVisible(true, shortcutName: settings.weatherForecastShortcutName) }
        .onDisappear { forecast.setVisible(false, shortcutName: settings.weatherForecastShortcutName) }
    }

    private func detail(_ key: LocalizationKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(localization.string(key)).foregroundStyle(.primary.opacity(0.78))
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
}
