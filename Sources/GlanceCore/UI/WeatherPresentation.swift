import Foundation
import SwiftUI

extension NativeWeatherAttribution {
    /// Apple's light/dark names identify the surface appearance, not the ink.
    func markURL(for colorScheme: ColorScheme) -> URL {
        colorScheme == .dark ? combinedMarkDarkURL : combinedMarkLightURL
    }
}

extension WeatherSource {
    var labelKey: LocalizationKey {
        switch self {
        case .nativeWeather: .weatherSourceNative
        case .shortcuts: .weatherSourceShortcuts
        }
    }
}

extension NativeWeatherIssue {
    var messageKey: LocalizationKey {
        switch self {
        case .notConfigured: .weatherNativeNotConfigured
        case .locationDenied: .weatherNativeLocationDenied
        case .locationUnavailable: .weatherNativeLocationUnavailable
        case .serviceUnavailable: .weatherNativeServiceUnavailable
        }
    }

    var opensLocationSettings: Bool {
        if case .locationDenied = self { return true }
        return false
    }
}
