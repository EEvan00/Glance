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

    static func compactWiFiSubtitle(_ wifi: WiFiStatus, localization: Localization) -> String {
        if wifi.state == .connected, let ssid = wifi.ssid, !ssid.isEmpty { return ssid }
        let key: LocalizationKey
        switch wifi.state {
        case .connected: key = .compactConnected
        case .notAssociated: key = .compactDisconnected
        case .off: key = .compactOff
        case .noInternet: key = .compactNoInternet
        case .hotspot: key = .compactHotspot
        case .temporary: key = .compactTemporary
        case .shared: key = .compactShared
        case .unavailable: key = .compactUnavailable
        }
        let status = localization.string(key)
        if wifi.state.isNetworkAssociated, let ssid = wifi.ssid, !ssid.isEmpty {
            return ssid + " · " + status
        }
        return status
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
    case timer
}

struct StatusPopoverView: View {
    @ObservedObject var store: SystemStatusStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var magSafeLED: MagSafeLEDController
    @ObservedObject var countdown: CountdownController
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
    let openBluetoothDeviceSettings: (BluetoothDevice) -> Void
    let openSettings: () -> Void
    let openCalendar: () -> Void
    let openClock: () -> Void
    let openScreenshot: () -> Void
    let openWeather: () -> Void
    let openSoundSettings: () -> Void
    let quit: () -> Void
    @ObservedObject var footerActions: FooterActionController
    var openFooterAction: (FooterModule) -> Void = { _ in }
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
            case .timer:
                CountdownView(controller: countdown, onBack: { panel = .summary })
            case .performance:
                PerformanceDetailsView(controller: performance, onBack: { panel = .summary })
            case .claude:
                ClaudeUsageView(controller: claudeUsage, onBack: { panel = .summary })
            case .codex:
                CodexUsageView(controller: codexUsage, onBack: { panel = .summary })
            case .bluetooth:
                BluetoothDeviceListView(
                    controller: store.bluetoothDevices,
                    settings: settings,
                    volume: store.snapshot.volume,
                    onSelectOutputDevice: { store.selectOutputDevice($0) },
                    onOpenDeviceSettings: openBluetoothDeviceSettings,
                    onBack: { panel = .summary },
                    onOpenBluetoothSettings: openBluetoothSettings
                )
            }
        }
        .padding(.horizontal, panel == .summary ? 0 : CompactPopupLayout.contentInset)
        .padding(CompactPopupLayout.gap)
        .frame(width: CompactPopupLayout.span(10) + CompactPopupLayout.gap * 2)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if countdown.isRunning || countdown.isFinished || countdown.shouldOpenDetails { panel = .timer }
            countdown.shouldOpenDetails = false
        }
        .onChange(of: countdown.shouldOpenDetails) { _, requested in
            if requested { panel = .timer; countdown.shouldOpenDetails = false }
        }
        .onChange(of: countdown.isFinished) { _, finished in
            if finished { panel = .timer }
            else if panel == .timer && countdown.indicator == nil { panel = .summary }
        }
    }

    private var summary: some View {
        VStack(spacing: CompactPopupLayout.gap) {
            HStack(alignment: .top, spacing: CompactPopupLayout.gap) {
                VStack(spacing: 0) {
                    cell(symbol: store.popupSnapshot.battery.isChargingPaused ? "powerplug.portrait.fill" : "battery.100",
                         title: localization.string(.compactBattery) + " · \(store.popupSnapshot.battery.percentage)%",
                         subtitle: compactBatterySubtitle) {
                        magSafeLED.refreshAvailability()
                        panel = .battery
                    }
                    PopupDivider().padding(.horizontal, CompactPopupLayout.moduleTextInset)
                    cell(symbol: "wifi", title: localization.string(.wifiTitle),
                         subtitle: compactWiFiSubtitle, wifi: store.popupSnapshot.wifi) {
                        store.activateWiFiPanel()
                        panel = .wifi(showDetails: false)
                    }
                }
                .frame(width: CompactPopupLayout.span(5))
                .systemModuleSurface()
                VStack(spacing: 0) {
                    cell(symbol: "bluetooth", title: localization.string(.bluetoothTitle), subtitle: bluetoothSummary) {
                        store.activateBluetoothPanel()
                        panel = .bluetooth
                    }
                    PopupDivider().padding(.horizontal, CompactPopupLayout.moduleTextInset)
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
                .frame(width: CompactPopupLayout.span(5))
                .systemModuleSurface()
            }
            VStack(spacing: 0) {
                BrightnessControlsView(controller: brightness, onOpenDisplay: { panel = .display })
                CompactVolumeControlsView(store: store, onOpenOutput: { panel = .output })
            }
            .padding(.vertical, 2)
            .frame(height: CompactPopupLayout.span(2))
            .systemModuleSurface()
            if !nowPlaying.items.isEmpty {
                NowPlayingView(controller: nowPlaying)
            }
            if settings.firstUtilityRow != .none || settings.secondUtilityRow != .none {
                TimelineView(.everyMinute) { context in
                    VStack(spacing: CompactPopupLayout.gap) {
                        if let utility = settings.firstUtilityRow.utility { utilityRow(utility, date: context.date) }
                        if let utility = settings.secondUtilityRow.utility { utilityRow(utility, date: context.date) }
                    }
                }
            }
            TimelineView(.periodic(from: FooterClockFormatting.timelineStart(showsSeconds: settings.showsClockSeconds), by: settings.showsClockSeconds ? 1 : 60)) { context in
                FooterModulesView(layout: settings.footerLayout,
                                  content: { footerContent($0, date: context.date) },
                                  activate: { activateFooter($0) },
                                  openSettings: openSettings, quit: quit)
            }
            if settings.footerLayout.modules.contains(where: { $0.kind == .weather }),
               weather.source == .nativeWeather, weather.snapshot != nil,
               let attribution = weather.attribution {
                WeatherAttributionView(attribution: attribution)
                    .padding(.horizontal, CompactPopupLayout.contentInset)
            }
        }
        .onChange(of: settings.popupUtility) { _, _ in panel = .summary }
        .onAppear { store.bluetoothDevices.activateIfAuthorized() }
    }

    private var weatherHelp: String {
        if weather.source == .nativeWeather, let issue = weather.nativeIssue {
            return localization.string(issue.messageKey)
        }
        let condition = weather.isUnavailable
            ? localization.string(.weatherUnavailable)
            : weather.snapshot.map { localization.string($0.conditionKey) }
                ?? localization.string(.weatherUnknown)
        let uv = weather.snapshot?.uvIndex.map { $0.formatted() } ?? "—"
        let rainChance = weather.snapshot?.precipitationChance.map { "\(Int($0.rounded()))%" } ?? "—"
        return localization.format(.weatherSummary, condition, uv, rainChance)
    }

    private func utilityRow(_ utility: PopupUtility, date: Date) -> some View {
        PopupUtilityStripView(utility: utility, performance: performance, codexUsage: codexUsage,
                             claudeUsage: claudeUsage, date: date) {
            switch utility {
            case .performance: panel = .performance
            case .codex: panel = .codex
            case .claude: panel = .claude
            }
        }
    }

    private func activateFooter(_ module: FooterModule) {
        switch module.kind {
        case .weather: panel = .weather
        case .date: openCalendar()
        case .clock: openClock()
        case .timer: panel = .timer
        case .screenshot: openScreenshot()
        case .battery: panel = .battery
        case .wifi: panel = .wifi(showDetails: false)
        case .bluetooth: panel = .bluetooth
        case .output: panel = .output
        case .performance: panel = .performance
        case .codex: panel = .codex
        case .claude: panel = .claude
        default: openFooterAction(module)
        }
    }

    private func footerContent(_ module: FooterModule, date: Date) -> FooterTileContent {
        let name = module.displayName(localization: localization)
        var result = FooterTileContent(symbol: module.kind.symbol, text: name, help: name)
        result.kind = module.kind
        switch module.kind {
        case .weather:
            result.symbol = weather.snapshot?.symbol ?? "cloud"
            result.text = weather.snapshot.map { settings.temperatureUnit.text(celsius: $0.temperature) } ?? "—"
            result.help = weatherHelp
        case .date:
            result.text = FooterClockFormatting.date(date, locale: localization.resolvedLanguage.locale, chinese: localization.resolvedLanguage.isChinese)
            result.textOnly = true
            result.help = FooterClockFormatting.detailedDate(date, locale: localization.resolvedLanguage.locale)
        case .clock:
            result.text = FooterClockFormatting.time(date, uses24HourClock: settings.uses24HourClock, showsSeconds: settings.showsClockSeconds)
            result.textOnly = true
            result.help = result.text
        case .timer:
            if countdown.isFinished { result.symbol = "timer.circle.fill"; result.isActive = true }
            if countdown.isRunning || countdown.isPaused {
                let seconds = Int(countdown.remaining.rounded(.up))
                result.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
                result.textOnly = true
            }
        case .battery:
            result.symbol = store.popupSnapshot.battery.isChargingPaused ? "powerplug.portrait.fill" : "battery.100"
            result.text = store.popupSnapshot.battery.rawPercentage == nil ? "—" : "\(store.popupSnapshot.battery.percentage)%"
        case .performance:
            result.text = performance.snapshot?.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—"
            let memory = performance.snapshot.map { "\(Int($0.memoryPercent.rounded()))%" } ?? "—"
            result.help = "CPU: \(result.text)\nRAM: \(memory)"
        case .codex:
            result.text = codexUsage.snapshot?.preferredPopupWindow?.remainingPercent.map { "\($0)%" } ?? "—"
        case .claude:
            result.text = claudeUsage.snapshot?.preferredPopupWindow?.remainingPercent.map { "\($0)%" } ?? "—"
        case .wifi:
            result.text = compactWiFiSubtitle
            result.wifi = store.popupSnapshot.wifi
        case .bluetooth:
            result.text = bluetoothSummary
            result.symbol = store.bluetoothDevices.availability == .poweredOff ? "antenna.radiowaves.left.and.right.slash" : module.kind.symbol
            result.isActive = store.bluetoothDevices.availability == .available
        case .output: result.text = store.liveVolume.deviceName ?? "—"
        case .keepAwake:
            result.isActive = footerActions.isKeepingAwake
            result.text = localization.string(footerActions.isKeepingAwake ? .footerEnabled : .footerDisabled)
        default: break
        }
        // Preserve v1 footer tooltips and accessibility labels. Only new status
        // modules add their current value; the timer keeps its original name.
        switch module.kind {
        case .battery, .codex, .claude, .wifi, .bluetooth, .output, .keepAwake:
            if result.text != name { result.help = name + ": " + result.text }
        default: break
        }
        return result
    }

    private var compactBatterySubtitle: String {
        let battery = store.popupSnapshot.battery
        let key: LocalizationKey
        if !battery.isPresent { key = .compactUnavailable }
        else if battery.isChargingPaused { key = .timerPaused }
        else if battery.isConnectedToPower { key = .compactPower }
        else { key = .compactOnBattery }
        return localization.string(key)
    }

    private var compactWiFiSubtitle: String {
        StatusPresentation.compactWiFiSubtitle(store.popupSnapshot.wifi, localization: localization)
    }

    private var bluetoothSummary: String {
        BluetoothSummaryPresentation.text(
            devices: store.bluetoothDevices.devices,
            availability: store.bluetoothDevices.availability,
            localization: localization,
            outputs: store.liveVolume.outputDevices
        )
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
        guard let percent = claudeUsage.snapshot?.preferredPopupWindow?.remainingPercent else { return "Claude" }
        return "Claude · \(percent)%"
    }

    private func claudeSubtitle(at date: Date) -> String {
        if claudeUsage.isUnavailable, claudeUsage.snapshot != nil { return localization.string(.compactCached) }
        if let countdown = claudeUsage.snapshot?.preferredPopupWindow?.resetCountdown(now: date) {
            return "↻ " + countdown
        }
        return localization.string(.compactNoData)
    }

    private var codexTitle: String {
        guard let window = codexUsage.snapshot?.preferredPopupWindow, let percent = window.remainingPercent else { return "Codex" }
        return "Codex · \(percent)%"
    }

    private func codexHelp(at date: Date) -> String {
        guard let percent = codexUsage.snapshot?.preferredPopupWindow?.remainingPercent else { return "Codex · \(codexSubtitle(at: date))" }
        return "Codex · \(localization.format(.codexRemaining, percent)) · \(codexSubtitle(at: date))"
    }

    private func codexSubtitle(at date: Date) -> String {
        if codexUsage.isUnavailable, codexUsage.snapshot != nil { return localization.string(.compactCached) }
        if let countdown = codexUsage.snapshot?.preferredPopupWindow?.resetCountdown(now: date) {
            return "↻ " + countdown
        }
        return localization.string(codexUsage.isLoading ? .compactLoading : .compactUnavailable)
    }

    // A 14pt SF Wi-Fi symbol is 18pt wide; bitmap size is a canvas width, not font size.
    private var compactWiFiIconSize: CGFloat {
        NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: CompactPopupLayout.moduleIconSize, weight: .medium))?
            .size.width ?? 18
    }

    private func cell(symbol: String, title: String, subtitle: String, provider: UsageProviderIcon.Provider? = nil, wifi: WiFiStatus? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Group {
                    if let provider {
                        UsageProviderIcon(provider: provider).scaleEffect(provider == .codex ? 1 : CompactPopupLayout.moduleIconSize / 18).frame(width: provider == .codex ? 18 : CompactPopupLayout.moduleIconSize, height: provider == .codex ? 18 : CompactPopupLayout.moduleIconSize)
                    } else if let wifi {
                        Image(nsImage: StatusIconRenderer.popupWiFiImage(wifi: wifi, size: compactWiFiIconSize))
                            .renderingMode(.template)
                    } else if symbol == "bluetooth", let image = NSImage(named: NSImage.bluetoothTemplateName) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 22)
                    } else {
                        Image(systemName: symbol).font(.system(size: CompactPopupLayout.moduleIconSize - (symbol == "battery.100" ? 1 : 0), weight: .medium))
                    }
                }.frame(width: CompactPopupLayout.unit)
                    .offset(x: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(settings.automaticallyShrinksCardText ? 0.85 : 1).fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.primary.opacity(0.78)).lineLimit(1).minimumScaleFactor(settings.automaticallyShrinksCardText ? 0.85 : 1).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .padding(.leading, CompactPopupLayout.gap)
                PopupChevron(alignsToModuleEdge: true, fitsSymbolWidth: true)
                    .padding(.leading, CompactPopupLayout.gap)
            }
            .frame(maxWidth: .infinity)
            .frame(height: CompactPopupLayout.cardRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}
