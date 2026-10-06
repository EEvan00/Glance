import AppKit
import SwiftUI

enum BundledWeatherShortcut: String, CaseIterable {
    case current = "Glance Weather"
    case forecast = "Glance Weather Forecast"

    var url: URL? { Bundle.module.url(forResource: rawValue, withExtension: "shortcut") }

    @MainActor
    func openInstaller() {
        if let url { NSWorkspace.shared.open(url) }
    }
}

struct WeatherShortcutInstallButtons: View {
    @ObservedObject var localization: Localization
    var purpose: ShortcutManagementView.Purpose = .missingOnly
    var body: some View {
        ShortcutManagementView(items: [
            .init(name: BundledWeatherShortcut.current.rawValue, addLabel: .settingsWeatherAddCurrent, resource: BundledWeatherShortcut.current.url),
            .init(name: BundledWeatherShortcut.forecast.rawValue, addLabel: .settingsWeatherAddForecast, resource: BundledWeatherShortcut.forecast.url)
        ], purpose: purpose)
    }
}
