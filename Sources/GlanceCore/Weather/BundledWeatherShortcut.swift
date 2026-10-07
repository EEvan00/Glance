import AppKit
import SwiftUI

enum BundledWeatherShortcut: String, CaseIterable {
    case current = "Glance Weather"
    case forecast = "Glance Weather Forecast"

    private static let versions: [String: Int] = {
        guard let url = Bundle.module.url(forResource: "WeatherShortcutVersions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return values
    }()
    var version: Int { Self.versions[rawValue] ?? 1 }

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
            .init(name: BundledWeatherShortcut.current.rawValue, addLabel: .settingsWeatherAddCurrent, resource: BundledWeatherShortcut.current.url, version: BundledWeatherShortcut.current.version),
            .init(name: BundledWeatherShortcut.forecast.rawValue, addLabel: .settingsWeatherAddForecast, resource: BundledWeatherShortcut.forecast.url, version: BundledWeatherShortcut.forecast.version)
        ], purpose: purpose)
    }
}
