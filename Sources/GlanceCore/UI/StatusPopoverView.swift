// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import AppKit
import SwiftUI

@MainActor
enum StatusPresentation {
    static let statusItemAccessibilityLabel = "Glance"

    static func statusItemAccessibilityValue(
        _ snapshot: StatusSnapshot,
        localization: Localization
    ) -> String {
        statusItemAccessibilityValue(
            MenuBarStatus(snapshot: snapshot),
            localization: localization
        )
    }

    static func statusItemAccessibilityValue(
        _ status: MenuBarStatus,
        localization: Localization
    ) -> String {
        let battery = status.battery
        let batterySummary: String
        if battery.isPresent {
            let percentage = localization.format(
                .batteryAccessibilityValue,
                battery.percentage
            )
            let subtitle = batterySubtitle(battery, localization: localization)
            if isOrdinaryBatteryState(battery) {
                batterySummary = percentage
            } else {
                batterySummary = localization.format(
                    .commonParenthetical,
                    percentage,
                    subtitle
                )
            }
        } else {
            batterySummary = localization.string(.batteryStateNotPresent)
        }

        let networkSummary = status.connection == .ethernet
            ? localization.string(.ethernetAccessibilityConnected)
            : wifiAccessibilitySummary(status.wifi, localization: localization)
        let volumeSummary = localization.format(
            .accessibilityVolume,
            volumeValue(status.volume, localization: localization)
        )

        return localization.format(
            .accessibilityStatus,
            batterySummary,
            networkSummary,
            volumeSummary
        )
    }

    static func batteryTitle(
        _ battery: BatteryStatus,
        localization: Localization
    ) -> String {
        localization.format(.batteryTitle, battery.percentage)
    }

    static func batteryTimeToFullText(
        minutes: Int?,
        localization: Localization
    ) -> String {
        guard let minutes, minutes > 0 else {
            return localization.string(.batteryStateCalculatingTimeToFull)
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return localization.format(
                .batteryTimeToFullMinutes,
                remainingMinutes
            )
        }
        if remainingMinutes == 0 {
            return localization.format(.batteryTimeToFullHours, hours)
        }
        return localization.format(
            .batteryTimeToFullHoursMinutes,
            hours,
            remainingMinutes
        )
    }

    static func batterySubtitle(
        _ battery: BatteryStatus,
        localization: Localization
    ) -> String {
        if !battery.isPresent {
            return localization.string(.batteryStateNotPresent)
        }
        if battery.isChargingPaused {
            return localization.string(.batteryStatePaused)
        }
        if battery.isCharged {
            return localization.string(.batteryStateCharged)
        }
        if battery.isCharging {
            return batteryTimeToFullText(
                minutes: battery.timeToFullChargeMinutes,
                localization: localization
            )
        }
        if battery.isLowPowerMode {
            return localization.string(.batteryStateLowPowerMode)
        }
        if battery.isConnectedToPower {
            return localization.string(.batteryStateConnectedToPower)
        }
        return localization.string(.batteryStateOnBattery)
    }

    static func wifiValue(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        switch wifi.state {
        case .connected:
            return localization.format(
                .wifiValueBars,
                StatusMappings.wifiBars(rssi: wifi.rssi)
            )
        case .notAssociated:
            return localization.string(.wifiValueNotAssociated)
        case .off:
            return localization.string(.wifiValueOff)
        case .noInternet:
            return localization.string(.wifiValueNoInternet)
        case .hotspot:
            return localization.string(.wifiValueHotspot)
        case .temporary:
            return localization.string(.wifiValueTemporary)
        case .shared:
            return localization.string(.wifiValueShared)
        case .unavailable:
            return localization.string(.wifiValueUnavailable)
        }
    }

    static func wifiSubtitle(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return ssid
        }

        switch wifi.state {
        case .connected:
            return localization.string(.wifiSubtitleConnected)
        case .notAssociated:
            return localization.string(.wifiSubtitleNotAssociated)
        case .off:
            return localization.string(.wifiSubtitleOff)
        case .noInternet:
            return localization.string(.wifiSubtitleNoInternet)
        case .hotspot:
            return localization.string(.wifiSubtitleHotspot)
        case .temporary:
            return localization.string(.wifiSubtitleTemporary)
        case .shared:
            return localization.string(.wifiSubtitleShared)
        case .unavailable:
            return localization.string(.wifiSubtitleUnavailable)
        }
    }

    static func volumeTitle(
        _ volume: VolumeStatus,
        localization: Localization
    ) -> String {
        volumeTitle(MenuBarVolumeStatus(volume: volume), localization: localization)
    }

    static func volumeTitle(
        _ volume: MenuBarVolumeStatus,
        localization: Localization
    ) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else {
            return localization.string(.volumeTitleUnavailable)
        }
        let percentage = Int((min(1, max(0, scalar)) * 100).rounded())
        return localization.format(.volumeTitle, percentage)
    }

    static func volumeValue(
        _ volume: VolumeStatus,
        localization: Localization
    ) -> String {
        volumeValue(MenuBarVolumeStatus(volume: volume), localization: localization)
    }

    static func volumeValue(
        _ volume: MenuBarVolumeStatus,
        localization: Localization
    ) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else { return "—" }
        let clampedScalar = min(1, max(0, scalar))
        let percentage = Int((clampedScalar * 100).rounded())
        if volume.isMuted {
            return localization.string(.volumeMuted)
        }
        let steps = StatusMappings.volumeSteps(
            scalar: clampedScalar,
            isMuted: volume.isMuted
        ) ?? 0
        return localization.format(.volumeValue, percentage, steps)
    }

    static func volumeSubtitle(
        _ volume: VolumeStatus,
        localization: Localization
    ) -> String {
        volume.deviceName ?? localization.string(.volumeNoDefaultDevice)
    }

    private static func wifiAccessibilitySummary(
        _ wifi: WiFiStatus,
        localization: Localization
    ) -> String {
        let value = wifiValue(wifi, localization: localization)
        if let ssid = wifi.ssid, !ssid.isEmpty {
            return localization.format(.wifiAccessibilityWithSSID, ssid, value)
        }
        return localization.format(
            .commonLabelValue,
            localization.string(.wifiTitle),
            value
        )
    }

    private static func isOrdinaryBatteryState(_ battery: BatteryStatus) -> Bool {
        battery.isPresent
            && !battery.isCharged
            && !battery.isCharging
            && !battery.isLowPowerMode
            && !battery.isConnectedToPower
    }
}


private enum PopoverPanel: Equatable {
    case display
    case summary
    case battery
    case wifi(showDetails: Bool)
    case bluetooth
    case output
    case codex
    case claude
    case performance
    case weather
}

struct StatusPopoverView: View {
    @ObservedObject var store: SystemStatusStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var magSafeLED: MagSafeLEDController
    @ObservedObject var performance: PerformanceController
    @ObservedObject var claudeUsage: ClaudeUsageController
    @ObservedObject var codexUsage: CodexUsageController
    @ObservedObject var weather: WeatherController
    @ObservedObject var weatherForecast: WeatherController
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject var brightness: BrightnessController
    @EnvironmentObject private var localization: Localization
    let requestWiFiNameAccess: () -> Void
    let openBatterySettings: () -> Void
    let openWiFiSettings: () -> Void
    let openLocationSettings: () -> Void
    let openBluetoothSettings: () -> Void
    let openSettings: () -> Void
    let openWeather: () -> Void
    let openSoundSettings: () -> Void
    let quit: () -> Void
    @State private var panel: PopoverPanel = .summary

    var body: some View {
        Group {
            switch panel {
            case .summary:
                summary
            case .battery:
                BatteryDetailsView(
                    battery: store.popupSnapshot.battery,
                    magSafeLED: magSafeLED,
                    onBack: { panel = .summary },
                    onOpenSettings: openBatterySettings,
                    onRefresh: { store.refreshAll() }
                )
            case .wifi(let showDetails):
                WiFiNetworkListView(
                    controller: store.wifiNetworks,
                    hotspots: store.wifiNetworks.hotspots,
                    wifi: store.popupSnapshot.wifi,
                    onBack: { panel = .summary },
                    onRequestNameAccess: requestWiFiNameAccess,
                    onOpenWiFiSettings: openWiFiSettings,
                    onOpenLocationSettings: openLocationSettings,
                    showsDetailsInitially: showDetails
                )
            case .display:
                DisplayControlsView(brightness: brightness, onBack: { panel = .summary })
            case .output:
                SoundControlsView(store: store, settings: settings, onBack: { panel = .summary }, onOpenSettings: openSoundSettings)
            case .weather:
                WeatherDetailsView(controller: weather, forecast: weatherForecast, settings: settings, onBack: { panel = .summary }, onOpenWeather: openWeather)
            case .performance:
                PerformanceDetailsView(controller: performance, onBack: { panel = .summary })
            case .claude:
                ClaudeUsageView(controller: claudeUsage, onBack: { panel = .summary })
            case .codex:
                CodexUsageView(controller: codexUsage, onBack: { panel = .summary })
            case .bluetooth:
                BluetoothDeviceListView(
                    controller: store.bluetoothDevices,
                    onBack: { panel = .summary },
                    onOpenBluetoothSettings: openBluetoothSettings
                )
            }
        }
        .padding(.horizontal, panel == .summary ? 0 : CompactPopupLayout.contentInset)
        .padding(CompactPopupLayout.gap)
        .frame(width: 284)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: some View {
        VStack(spacing: CompactPopupLayout.gap) {
            HStack(alignment: .top, spacing: CompactPopupLayout.gap) {
                VStack(spacing: 0) {
                    cell(symbol: store.popupSnapshot.battery.isChargingPaused ? "powerplug.portrait.fill" : "battery.100",
                         title: StatusPresentation.batteryTitle(store.popupSnapshot.battery, localization: localization),
                         subtitle: StatusPresentation.batterySubtitle(store.popupSnapshot.battery, localization: localization)) {
                        magSafeLED.refreshAvailability()
                        panel = .battery
                    }
                    PopupDivider().padding(.horizontal, 8)
                    cell(symbol: "wifi", title: localization.string(.wifiTitle),
                         subtitle: StatusPresentation.wifiSubtitle(store.popupSnapshot.wifi, localization: localization)) {
                        store.activateWiFiPanel()
                        panel = .wifi(showDetails: false)
                    }
                }
                .systemModuleSurface()
                VStack(spacing: 0) {
                    cell(symbol: "bluetooth", title: localization.string(.bluetoothTitle), subtitle: bluetoothSummary) {
                        store.activateBluetoothPanel()
                        panel = .bluetooth
                    }
                    PopupDivider().padding(.horizontal, 8)
                    TimelineView(.everyMinute) { context in
                        switch settings.popupUtility {
                        case .performance:
                            cell(symbol: "cpu", title: performanceCPUText, subtitle: performanceMemoryText) { panel = .performance }
                                .accessibilityLabel(localization.string(.performanceTitle) + ", " + performanceSubtitle)
                        case .codex:
                            cell(symbol: "terminal", title: codexTitle, subtitle: codexSubtitle(at: context.date), provider: .codex) { panel = .codex }
                                .accessibilityLabel(codexHelp(at: context.date))
                        case .claude:
                            cell(symbol: "terminal", title: claudeTitle, subtitle: claudeSubtitle(at: context.date), provider: .claude) { panel = .claude }
                        }
                    }
                }
                .systemModuleSurface()
            }
            VStack(spacing: CompactPopupLayout.gap) {
                BrightnessControlsView(controller: brightness, onOpenDisplay: { panel = .display })
                CompactVolumeControlsView(store: store, onOpenOutput: { panel = .output })
            }
            .padding(CompactPopupLayout.gap)
            .systemModuleSurface()
            if !nowPlaying.items.isEmpty {
                NowPlayingView(controller: nowPlaying)
            }
            TimelineView(.everyMinute) { context in
                HStack(spacing: CompactPopupLayout.gap) {
                    footerButton(.compactSettings, symbol: "gearshape", action: openSettings)
                    Button { panel = .weather } label: {
                        HStack(spacing: 3) {
                            Image(systemName: weather.snapshot?.symbol ?? "cloud")
                            Text(weather.snapshot?.temperatureText ?? "—").monospacedDigit()
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .systemModuleSurface()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(weatherHelp)
                    .help(Text(weatherHelp))
                    Text(FooterClockFormatting.date(context.date, locale: localization.resolvedLanguage.locale, chinese: localization.resolvedLanguage.isChinese))
                        .font(.system(size: 11)).monospacedDigit().lineLimit(1)
                        .frame(width: 78, height: 24).systemModuleSurface()
                        .help(context.date.formatted(date: .complete, time: .omitted))
                    Text(FooterClockFormatting.time(context.date, uses24HourClock: settings.uses24HourClock))
                        .font(.system(size: 11)).monospacedDigit().lineLimit(1)
                        .frame(width: 44, height: 24).systemModuleSurface()
                    footerButton(.compactQuit, symbol: "xmark.circle", action: quit)
                }
            }

        }
        .onChange(of: settings.popupUtility) { _, _ in panel = .summary }
        .onAppear { store.bluetoothDevices.activateIfAuthorized() }
    }

    private var weatherHelp: String {
        let condition = weather.isUnavailable
            ? localization.string(.weatherUnavailable)
            : weather.snapshot.map { $0.appleCondition ?? localization.string($0.conditionKey) }
                ?? localization.string(.weatherUnknown)
        let uv = weather.snapshot?.uvIndex.map { $0.formatted() } ?? "—"
        let rainChance = weather.snapshot?.precipitationChance.map { "\(Int($0.rounded()))%" } ?? "—"
        return "\(condition) · UV \(uv) · \(rainChance) Rain"
    }

    private func footerButton(_ key: LocalizationKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .systemModuleSurface()
        }.buttonStyle(.plain)
            .help(localization.string(key))
            .accessibilityLabel(localization.string(key))
    }

    private var bluetoothSummary: String {
        if let device = store.bluetoothDevices.connectedDevices.first { return device.name }
        switch store.bluetoothDevices.availability {
        case .available: return localization.string(.bluetoothNoConnectedDevices)
        case .poweredOff: return localization.string(.bluetoothOff)
        case .idle, .initializing: return localization.string(.bluetoothInitializing)
        case .authorizationNotDetermined: return localization.string(.bluetoothAuthorizationNotDetermined)
        case .authorizationDenied: return localization.string(.bluetoothAuthorizationDenied)
        case .authorizationRestricted: return localization.string(.bluetoothAuthorizationRestricted)
        case .failed: return localization.string(.bluetoothReadFailed)
        case .unavailable: return localization.string(.bluetoothUnavailable)
        }
    }

    private var performanceCPUText: String {
        let value = performance.snapshot?.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—"
        return localization.format(.performanceCPUShort, value)
    }

    private var performanceMemoryText: String {
        let value = performance.snapshot.map { "\(Int($0.memoryPercent.rounded()))%" } ?? "—"
        return localization.format(.performanceMemoryShort, value)
    }

    private var performanceSubtitle: String {
        guard let snapshot = performance.snapshot else { return localization.string(.performanceUnavailable) }
        let cpu = snapshot.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—"
        return localization.format(.performanceSummary, cpu, "\(Int(snapshot.memoryPercent.rounded()))%")
    }

    private var claudeTitle: String {
        guard let percent = claudeUsage.snapshot?.windows.first?.remainingPercent else { return "Claude" }
        return "Claude · \(percent)%"
    }

    private func claudeSubtitle(at date: Date) -> String {
        if claudeUsage.isUnavailable, claudeUsage.snapshot != nil { return localization.string(.codexCached) }
        if let countdown = claudeUsage.snapshot?.windows.first?.resetCountdown(now: date) {
            return localization.format(.codexReset, countdown)
        }
        return localization.string(.claudeUnavailable)
    }

    private var codexTitle: String {
        guard let window = codexUsage.snapshot?.windows.first, let percent = window.remainingPercent else { return "Codex" }
        return "Codex · \(percent)%"
    }

    private func codexHelp(at date: Date) -> String {
        guard let percent = codexUsage.snapshot?.windows.first?.remainingPercent else { return "Codex · \(codexSubtitle(at: date))" }
        return "Codex · \(localization.format(.codexRemaining, percent)) · \(codexSubtitle(at: date))"
    }

    private func codexSubtitle(at date: Date) -> String {
        if codexUsage.isUnavailable, codexUsage.snapshot != nil { return localization.string(.codexCached) }
        if let countdown = codexUsage.snapshot?.windows.first?.resetCountdown(now: date) {
            return localization.format(.codexReset, countdown)
        }
        return localization.string(codexUsage.isLoading ? .codexLoading : .codexUnavailable)
    }

    private func cell(symbol: String, title: String, subtitle: String, provider: UsageProviderIcon.Provider? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Group {
                    if let provider {
                        UsageProviderIcon(provider: provider)
                    } else if symbol == "bluetooth", let image = NSImage(named: NSImage.bluetoothTemplateName) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 22)
                    } else {
                        Image(systemName: symbol).font(.system(size: 14))
                    }
                }.frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.primary.opacity(0.78)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PopupChevron()
            }
            .padding(.horizontal, CompactPopupLayout.gap)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}
