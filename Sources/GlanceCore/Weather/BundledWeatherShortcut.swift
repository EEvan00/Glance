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

    var body: some View {
        HStack {
            Button(localization.string(.settingsWeatherAddCurrent)) {
                BundledWeatherShortcut.current.openInstaller()
            }
            Button(localization.string(.settingsWeatherAddForecast)) {
                BundledWeatherShortcut.forecast.openInstaller()
            }
        }.buttonStyle(.bordered).controlSize(.small)
    }
}
