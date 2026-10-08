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
                Button(action: onBack) {
                    Text(localization.string(.weatherTitle)).font(.headline)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                Text((forecast.snapshot?.location ?? localization.string(.weatherCurrentLocation)).uppercased())
                    .font(.caption).foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(1).truncationMode(.tail)
                    .help(forecast.snapshot?.location ?? localization.string(.weatherCurrentLocation))
                if controller.isLoading || forecast.isLoading { ProgressView().controlSize(.small) }
            }
            if let snapshot = forecast.snapshot ?? controller.snapshot {
                HStack(spacing: 12) {
                    Image(systemName: snapshot.symbol).font(.system(size: 28))
                        .accessibilityHidden(true)
                    Text(settings.temperatureUnit.text(celsius: snapshot.temperature, includesUnit: true)).font(.system(size: 28, weight: .medium))
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        if let high = snapshot.high { Text("\(localization.string(.weatherHigh)): \(temperature(high))") }
                        if let low = snapshot.low { Text("\(localization.string(.weatherLow)): \(temperature(low))") }
                    }.font(.caption).monospacedDigit()
                }
                detail(.weatherCondition, value: localization.string(snapshot.conditionKey))
                detail(.weatherUVIndex, value: snapshot.uvIndex.map { $0.formatted() } ?? "—")

            } else {
                Text(localization.string(controller.isLoading ? .weatherLoading : .weatherUnavailable))
                    .foregroundStyle(.primary.opacity(0.78))
            }
            if let snapshot = forecast.snapshot {
                if !snapshot.forecastEntries.isEmpty {
                    Text(localization.string(.weatherHourly)).font(.subheadline.weight(.semibold))
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(snapshot.forecastEntries) { entry in
                                forecastCell(entry)
                            }
                        }.padding(.vertical, 4)
                    }.scrollIndicators(.hidden).frame(height: 94)
                }
            } else if forecast.isUnavailable {
                Text(localization.string(.weatherForecastUnavailable)).font(.caption)
                    .foregroundStyle(.primary.opacity(0.78))
            }
            WeatherShortcutInstallButtons(localization: localization)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text((forecast.updatedAt ?? controller.updatedAt).map {
                        localization.format(.weatherUpdated, $0.formatted(date: .omitted, time: .shortened))
                    } ?? localization.string(.weatherUnavailable))
                        .font(.caption).foregroundStyle(.primary.opacity(0.78))
                    Spacer()
                    Button {
                        controller.refreshNow(shortcutName: settings.weatherShortcutName)
                        forecast.refreshNow(shortcutName: settings.weatherForecastShortcutName)
                    } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 24, height: 24).contentShape(Rectangle())
                    }.buttonStyle(PopupHoverButtonStyle())
                        .accessibilityLabel(localization.string(.weatherRefresh))
                        .disabled(controller.isLoading || forecast.isLoading)
                }.padding(.bottom, 8)
                PopupDivider()
                Button(localization.string(.weatherOpenApp), action: onOpenWeather)
                    .popupFooterInsets()
                    .buttonStyle(PopupHoverButtonStyle(fullWidth: true))
            }
        }
        .onAppear { forecast.setVisible(true, shortcutName: settings.weatherForecastShortcutName) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Verify the installed output after returning from the system importer.
            controller.refreshNow(shortcutName: settings.weatherShortcutName)
            forecast.refreshNow(shortcutName: settings.weatherForecastShortcutName)
        }
        .onDisappear { forecast.setVisible(false, shortcutName: settings.weatherForecastShortcutName) }
    }

    private func temperature(_ value: Double) -> String {
        settings.temperatureUnit.text(celsius: value)
    }

    private func forecastCell(_ entry: WeatherForecastEntry) -> some View {
        let symbol: String
        let caption: String
        let help: String
        let rainChance: String
        switch entry {
        case .hour(let hour):
            symbol = hour.symbol
            caption = settings.temperatureUnit.text(celsius: hour.temperature)
            rainChance = hour.precipitationChance.map { "\(Int($0.rounded()))%" } ?? "—"
            help = localization.string(WeatherSnapshot(temperature: hour.temperature, code: hour.code, isDay: hour.isDay).conditionKey)
        case .sunrise:
            symbol = "sunrise.fill"
            caption = localization.string(.weatherSunrise)
            help = caption
            rainChance = ""
        case .sunset:
            symbol = "sunset.fill"
            caption = localization.string(.weatherSunset)
            help = caption
            rainChance = ""
        }
        let time = FooterClockFormatting.time(entry.date, uses24HourClock: settings.uses24HourClock)
        return VStack(spacing: 6) {
            Text(time).foregroundStyle(.primary.opacity(0.78)).frame(height: 14)
            Image(systemName: symbol).font(.system(size: 16)).frame(width: 24, height: 24).accessibilityHidden(true)
            Text(caption).lineLimit(1).frame(height: 14)
            Text(rainChance).foregroundStyle(.primary.opacity(0.78)).frame(height: 14)
        }.font(.caption).monospacedDigit()
            .frame(minWidth: 36)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(time), \(help), \(caption)" + (rainChance.isEmpty ? "" : ", \(localization.string(.weatherRainChance)) \(rainChance)"))
            .help(help)
    }

    private func detail(_ key: LocalizationKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(localization.string(key)).foregroundStyle(.primary.opacity(0.78))
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
}
