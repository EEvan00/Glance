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
        case .locationServicesDisabled: .weatherNativeLocationServicesDisabled
        case .authorizationTimedOut: .weatherNativeAuthorizationTimedOut
        case .locationUnavailable: .weatherNativeLocationUnavailable
        case .serviceUnavailable: .weatherNativeServiceUnavailable
        }
    }

    var opensLocationSettings: Bool {
        switch self {
        case .locationDenied, .locationServicesDisabled: return true
        default: return false
        }
    }
}
