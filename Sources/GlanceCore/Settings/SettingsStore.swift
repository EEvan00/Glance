// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let iconSizeRange: ClosedRange<Double> = 16...36
    static let defaultIconSize: Double = 28
    static let iconSizeDefaultsKey = "menuBarIconSize"

    static let batteryCriticalThresholdRange: ClosedRange<Double> = 0...100
    static let defaultBatteryCriticalThreshold: Double = 20
    static let batterySymbolScaleRange: ClosedRange<Double> = 0.9...1.1
    static let defaultBatterySymbolScale: Double = 1
    static let showsBatteryPercentageDefaultsKey = "showsBatteryPercentage"
    static let showsChargingIndicatorDefaultsKey = "showsChargingIndicator"
    static let usesBatteryStatusColorsDefaultsKey = "usesBatteryStatusColors"
    static let batteryCriticalThresholdDefaultsKey = "batteryCriticalThreshold"
    static let batterySymbolScaleDefaultsKey = "batterySymbolScale"
    static let showsWiFiIconForEthernetDefaultsKey = "showsWiFiIconForEthernet"
    static let showsWiFiIconForHotspotDefaultsKey = "showsWiFiIconForHotspot"
    static let showsWiFiIconForTemporaryConnectionDefaultsKey = "showsWiFiIconForTemporaryConnection"
    static let showsWiFiIconForInternetSharingDefaultsKey = "showsWiFiIconForInternetSharing"

    static let refreshIntervalRange: ClosedRange<Double> = 5...60
    static let defaultRefreshIntervalSeconds: Double = 5
    static let refreshIntervalDefaultsKey = "statusRefreshIntervalSeconds"

    static let outputDeviceLimitRange: ClosedRange<Int> = 1...20
    static let defaultMaxVisibleOutputDevices = 5
    static let maxVisibleOutputDevicesDefaultsKey = "maxVisibleOutputDevices"
    static let alwaysShowsAllOutputDevicesDefaultsKey = "alwaysShowsAllOutputDevices"
    static let outputDeviceOrderDefaultsKey = "outputDeviceOrder"
    static let popupSectionOrderDefaultsKey = "popupSectionOrder"

    @Published var iconSize: Double {
        didSet {
            let clamped = Self.clampedIconSize(iconSize)
            // 写入越界值时先夹取再落盘，夹取会再次触发 didSet，一次后收敛。
            guard clamped == iconSize else {
                iconSize = clamped
                return
            }
            defaults.set(clamped, forKey: Self.iconSizeDefaultsKey)
        }
    }

    @Published var showsBatteryPercentage: Bool {
        didSet {
            defaults.set(showsBatteryPercentage, forKey: Self.showsBatteryPercentageDefaultsKey)
        }
    }

    @Published var showsChargingIndicator: Bool {
        didSet {
            defaults.set(showsChargingIndicator, forKey: Self.showsChargingIndicatorDefaultsKey)
        }
    }

    @Published var usesBatteryStatusColors: Bool {
        didSet {
            defaults.set(usesBatteryStatusColors, forKey: Self.usesBatteryStatusColorsDefaultsKey)
        }
    }

    @Published var batterySymbolScale: Double {
        didSet {
            let clamped = Self.clampedBatterySymbolScale(batterySymbolScale)
            guard clamped == batterySymbolScale else {
                batterySymbolScale = clamped
                return
            }
            defaults.set(clamped, forKey: Self.batterySymbolScaleDefaultsKey)
        }
    }

    @Published var batteryCriticalThreshold: Double {
        didSet {
            let clamped = Self.clampedBatteryCriticalThreshold(batteryCriticalThreshold)
            guard clamped == batteryCriticalThreshold else {
                batteryCriticalThreshold = clamped
                return
            }
            defaults.set(clamped, forKey: Self.batteryCriticalThresholdDefaultsKey)
        }
    }

    @Published var showsWiFiIconForEthernet: Bool {
        didSet {
            defaults.set(
                showsWiFiIconForEthernet,
                forKey: Self.showsWiFiIconForEthernetDefaultsKey
            )
        }
    }

    @Published var showsWiFiIconForHotspot: Bool {
        didSet {
            defaults.set(
                showsWiFiIconForHotspot,
                forKey: Self.showsWiFiIconForHotspotDefaultsKey
            )
        }
    }

    @Published var showsWiFiIconForTemporaryConnection: Bool {
        didSet {
            defaults.set(
                showsWiFiIconForTemporaryConnection,
                forKey: Self.showsWiFiIconForTemporaryConnectionDefaultsKey
            )
        }
    }

    @Published var showsWiFiIconForInternetSharing: Bool {
        didSet {
            defaults.set(
                showsWiFiIconForInternetSharing,
                forKey: Self.showsWiFiIconForInternetSharingDefaultsKey
            )
        }
    }

    @Published var refreshIntervalSeconds: Double {
        didSet {
            let clamped = Self.clampedRefreshInterval(refreshIntervalSeconds)
            guard clamped == refreshIntervalSeconds else {
                refreshIntervalSeconds = clamped
                return
            }
            defaults.set(clamped, forKey: Self.refreshIntervalDefaultsKey)
        }
    }

    @Published var maxVisibleOutputDevices: Int {
        didSet {
            let clamped = Self.clampedOutputDeviceLimit(maxVisibleOutputDevices)
            guard clamped == maxVisibleOutputDevices else {
                maxVisibleOutputDevices = clamped
                return
            }
            defaults.set(clamped, forKey: Self.maxVisibleOutputDevicesDefaultsKey)
        }
    }

    @Published var alwaysShowsAllOutputDevices: Bool {
        didSet {
            defaults.set(
                alwaysShowsAllOutputDevices,
                forKey: Self.alwaysShowsAllOutputDevicesDefaultsKey
            )
        }
    }

    @Published private(set) var outputDeviceOrder: [String] {
        didSet {
            defaults.set(outputDeviceOrder, forKey: Self.outputDeviceOrderDefaultsKey)
        }
    }

    @Published private(set) var popupSectionOrder: [PopupSection] {
        didSet {
            defaults.set(
                popupSectionOrder.map(\.rawValue),
                forKey: Self.popupSectionOrderDefaultsKey
            )
        }
    }

    var refreshInterval: Duration {
        .seconds(Int(refreshIntervalSeconds.rounded()))
    }

    var visibleOutputDeviceLimit: Int? {
        alwaysShowsAllOutputDevices ? nil : maxVisibleOutputDevices
    }

    func orderedOutputDevices(_ devices: [AudioOutputDevice]) -> [AudioOutputDevice] {
        OutputDeviceListPresentation.orderedDevices(devices, using: outputDeviceOrder)
    }

    func moveOutputDevices(
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        in devices: [AudioOutputDevice]
    ) {
        guard !source.isEmpty,
              source.allSatisfy({ devices.indices.contains($0) }),
              (0...devices.count).contains(destination) else {
            return
        }

        let movedDevices = source.map { devices[$0] }
        let remainingDevices = devices.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let insertionOffset = destination - source.filter { $0 < destination }.count

        var reorderedDevices = remainingDevices
        reorderedDevices.insert(
            contentsOf: movedDevices,
            at: min(insertionOffset, reorderedDevices.count)
        )
        outputDeviceOrder = reorderedDevices.compactMap(\.uid)
    }

    func movePopupSections(
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        guard !source.isEmpty,
              source.allSatisfy({ popupSectionOrder.indices.contains($0) }),
              (0...popupSectionOrder.count).contains(destination) else {
            return
        }

        let movedSections = source.map { popupSectionOrder[$0] }
        let remainingSections = popupSectionOrder.enumerated()
            .filter { !source.contains($0.offset) }
            .map(\.element)
        let insertionOffset = destination - source.filter { $0 < destination }.count

        var reorderedSections = remainingSections
        reorderedSections.insert(
            contentsOf: movedSections,
            at: min(insertionOffset, reorderedSections.count)
        )
        popupSectionOrder = reorderedSections
    }

    var isBatterySymbolSizeEnabled: Bool {
        showsBatteryPercentage || showsChargingIndicator
    }

    var batteryIconOptions: BatteryIconOptions {
        BatteryIconOptions(
            showsPercentage: showsBatteryPercentage,
            showsChargingIndicator: showsChargingIndicator,
            usesStatusColors: usesBatteryStatusColors,
            criticalThreshold: Int(batteryCriticalThreshold.rounded()),
            textScale: batterySymbolScale * BatteryIconOptions.defaultTextScale
        )
    }

    var connectionIconOptions: ConnectionIconOptions {
        ConnectionIconOptions(
            showsWiFiIconForEthernet: showsWiFiIconForEthernet,
            showsWiFiIconForHotspot: showsWiFiIconForHotspot,
            showsWiFiIconForTemporaryConnection: showsWiFiIconForTemporaryConnection,
            showsWiFiIconForInternetSharing: showsWiFiIconForInternetSharing
        )
    }

    @Published var firstQuickAction: PopupQuickAction {
        didSet { defaults.set(firstQuickAction.rawValue, forKey: "firstQuickAction") }
    }
    @Published var secondQuickAction: PopupQuickAction {
        didSet { defaults.set(secondQuickAction.rawValue, forKey: "secondQuickAction") }
    }
    @Published var quickActionShortcutName: String {
        didSet { defaults.set(quickActionShortcutName, forKey: "quickActionShortcutName") }
    }
    @Published var quickActionApplicationPath: String {
        didSet { defaults.set(quickActionApplicationPath, forKey: "quickActionApplicationPath") }
    }

    @Published var firstUtilityRow: PopupUtilityRow {
        didSet { defaults.set(firstUtilityRow.rawValue, forKey: "firstUtilityRow") }
    }
    @Published var secondUtilityRow: PopupUtilityRow {
        didSet { defaults.set(secondUtilityRow.rawValue, forKey: "secondUtilityRow") }
    }
    var visiblePopupUtilities: Set<PopupUtility> {
        Self.popupUtilities(card: popupUtility, first: firstUtilityRow, second: secondUtilityRow)
    }
    static func popupUtilities(card: PopupUtility, first: PopupUtilityRow, second: PopupUtilityRow) -> Set<PopupUtility> {
        Set([card, first.utility, second.utility].compactMap { $0 })
    }

    @Published var popupUtility: PopupUtility {
        didSet { defaults.set(popupUtility.rawValue, forKey: "popupUtility") }
    }

    @Published var scrollToAdjustVolume: Bool {
        didSet { defaults.set(scrollToAdjustVolume, forKey: "scrollToAdjustVolume") }
    }

    @Published var screenshotMode: ScreenshotMode {
        didSet { defaults.set(screenshotMode.rawValue, forKey: "screenshotMode") }
    }
    @Published var screenshotDestination: ScreenshotDestination {
        didSet { defaults.set(screenshotDestination.rawValue, forKey: "screenshotDestination") }
    }

    @Published var automaticallyShrinksCardText: Bool {
        didSet { defaults.set(automaticallyShrinksCardText, forKey: "automaticallyShrinksCardText") }
    }

    @Published var showsClockSeconds: Bool {
        didSet { defaults.set(showsClockSeconds, forKey: "showsClockSeconds") }
    }
    @Published var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: "temperatureUnit") }
    }

    @Published var uses24HourClock: Bool {
        didSet { defaults.set(uses24HourClock, forKey: "uses24HourClock") }
    }

    var weatherShortcutName: String { BundledWeatherShortcut.current.rawValue }
    var weatherForecastShortcutName: String { BundledWeatherShortcut.forecast.rawValue }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults === UserDefaults.standard,
           Bundle.main.bundleIdentifier == "io.github.EEvan00.Glance",
           !defaults.bool(forKey: "glanceImportedLegacyPreferences") {
            let legacy = defaults.persistentDomain(forName: "io.github.404404.StatusTrio") ?? [:]
            for (key, value) in legacy where !key.hasPrefix("SU") && !key.hasPrefix("NS") {
                if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: "glanceImportedLegacyPreferences")
        }
        let first = defaults.string(forKey: "firstQuickAction").flatMap(PopupQuickAction.init(rawValue:)) ?? .timer
        let second = defaults.string(forKey: "secondQuickAction").flatMap(PopupQuickAction.init(rawValue:)) ?? .screenshot
        self.firstQuickAction = first
        self.secondQuickAction = second == first ? (first == .screenshot ? .timer : .screenshot) : second
        self.quickActionShortcutName = defaults.string(forKey: "quickActionShortcutName") ?? ""
        self.quickActionApplicationPath = defaults.string(forKey: "quickActionApplicationPath") ?? ""
        let firstRow = defaults.string(forKey: "firstUtilityRow").flatMap(PopupUtilityRow.init(rawValue:)) ?? .none
        let secondRow = defaults.string(forKey: "secondUtilityRow").flatMap(PopupUtilityRow.init(rawValue:)) ?? .none
        self.firstUtilityRow = firstRow
        self.secondUtilityRow = firstRow != .none && firstRow == secondRow ? .none : secondRow
        self.popupUtility = defaults.string(forKey: "popupUtility").flatMap(PopupUtility.init(rawValue:)) ?? .performance
        self.scrollToAdjustVolume = defaults.object(forKey: "scrollToAdjustVolume") as? Bool ?? false
        self.screenshotMode = defaults.string(forKey: "screenshotMode").flatMap(ScreenshotMode.init(rawValue:)) ?? .toolbar
        self.screenshotDestination = defaults.string(forKey: "screenshotDestination").flatMap(ScreenshotDestination.init(rawValue:)) ?? .desktop
        self.automaticallyShrinksCardText = defaults.object(forKey: "automaticallyShrinksCardText") as? Bool ?? true
        self.temperatureUnit = defaults.string(forKey: "temperatureUnit").flatMap(TemperatureUnit.init(rawValue:)) ?? .celsius
        self.showsClockSeconds = defaults.bool(forKey: "showsClockSeconds")
        self.uses24HourClock = defaults.object(forKey: "uses24HourClock") as? Bool ?? true
        let storedIconSize = (defaults.object(forKey: Self.iconSizeDefaultsKey) as? NSNumber)?.doubleValue
        let storedCriticalThreshold = (defaults.object(forKey: Self.batteryCriticalThresholdDefaultsKey) as? NSNumber)?.doubleValue
        let storedBatterySymbolScale = (defaults.object(forKey: Self.batterySymbolScaleDefaultsKey) as? NSNumber)?.doubleValue
        let storedOutputDeviceLimit = (defaults.object(forKey: Self.maxVisibleOutputDevicesDefaultsKey) as? NSNumber)?.intValue
        let storedRefreshInterval = (defaults.object(forKey: Self.refreshIntervalDefaultsKey) as? NSNumber)?.doubleValue
        let storedOutputDeviceOrder = defaults.stringArray(forKey: Self.outputDeviceOrderDefaultsKey) ?? []
        let storedPopupSectionOrder = defaults.stringArray(
            forKey: Self.popupSectionOrderDefaultsKey
        ) ?? []

        self.iconSize = Self.clampedIconSize(storedIconSize ?? Self.defaultIconSize)
        self.showsBatteryPercentage = defaults.object(forKey: Self.showsBatteryPercentageDefaultsKey) as? Bool ?? true
        self.showsChargingIndicator = defaults.object(forKey: Self.showsChargingIndicatorDefaultsKey) as? Bool ?? true
        self.usesBatteryStatusColors = defaults.object(forKey: Self.usesBatteryStatusColorsDefaultsKey) as? Bool ?? true
        self.batterySymbolScale = Self.clampedBatterySymbolScale(
            storedBatterySymbolScale ?? Self.defaultBatterySymbolScale
        )
        self.batteryCriticalThreshold = Self.clampedBatteryCriticalThreshold(
            storedCriticalThreshold ?? Self.defaultBatteryCriticalThreshold
        )
        self.showsWiFiIconForEthernet = defaults.object(
            forKey: Self.showsWiFiIconForEthernetDefaultsKey
        ) as? Bool ?? false
        self.showsWiFiIconForHotspot = defaults.object(
            forKey: Self.showsWiFiIconForHotspotDefaultsKey
        ) as? Bool ?? false
        self.showsWiFiIconForTemporaryConnection = defaults.object(
            forKey: Self.showsWiFiIconForTemporaryConnectionDefaultsKey
        ) as? Bool ?? false
        self.showsWiFiIconForInternetSharing = defaults.object(
            forKey: Self.showsWiFiIconForInternetSharingDefaultsKey
        ) as? Bool ?? false
        self.refreshIntervalSeconds = Self.clampedRefreshInterval(
            storedRefreshInterval ?? Self.defaultRefreshIntervalSeconds
        )
        self.maxVisibleOutputDevices = Self.clampedOutputDeviceLimit(
            storedOutputDeviceLimit ?? Self.defaultMaxVisibleOutputDevices
        )
        self.alwaysShowsAllOutputDevices = defaults.object(
            forKey: Self.alwaysShowsAllOutputDevicesDefaultsKey
        ) as? Bool ?? false
        self.outputDeviceOrder = storedOutputDeviceOrder
        self.popupSectionOrder = Self.sanitizedPopupSectionOrder(
            storedPopupSectionOrder
        )
    }

    static func clampedIconSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultIconSize }
        return min(iconSizeRange.upperBound, max(iconSizeRange.lowerBound, value))
    }

    static func clampedBatterySymbolScale(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBatterySymbolScale }
        return min(
            batterySymbolScaleRange.upperBound,
            max(batterySymbolScaleRange.lowerBound, value)
        )
    }

    static func clampedBatteryCriticalThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return defaultBatteryCriticalThreshold }
        return min(
            batteryCriticalThresholdRange.upperBound,
            max(batteryCriticalThresholdRange.lowerBound, value)
        ).rounded()
    }

    static func clampedRefreshInterval(_ value: Double) -> Double {
        guard value.isFinite else { return defaultRefreshIntervalSeconds }
        let clamped = min(refreshIntervalRange.upperBound, max(refreshIntervalRange.lowerBound, value))
        return (clamped / 5).rounded() * 5
    }

    static func clampedOutputDeviceLimit(_ value: Int) -> Int {
        min(outputDeviceLimitRange.upperBound, max(outputDeviceLimitRange.lowerBound, value))
    }

    static func sanitizedPopupSectionOrder(_ rawValues: [String]) -> [PopupSection] {
        var seen: Set<PopupSection> = []
        let storedSections = rawValues
            .compactMap(PopupSection.init(rawValue:))
            .filter { seen.insert($0).inserted }
        return storedSections + PopupSection.allCases.filter { !seen.contains($0) }
    }
}
