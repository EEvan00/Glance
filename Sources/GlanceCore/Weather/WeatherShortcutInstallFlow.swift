import Combine

/// Survives closing the popover; opening an importer never counts as installation.
@MainActor
final class WeatherShortcutInstallFlow: ObservableObject {
    static let shared = WeatherShortcutInstallFlow()
    @Published private(set) var pending: [BundledWeatherShortcut] = []
    var isInProgress: Bool { !pending.isEmpty }

    func reconcile(installed: Set<String>) {
        let remaining = pending.filter { !installed.contains($0.rawValue) }
        if remaining != pending { pending = remaining }
    }

    func nextToOpen(installed: Set<String>) -> BundledWeatherShortcut? {
        reconcile(installed: installed)
        if pending.isEmpty {
            pending = BundledWeatherShortcut.allCases.filter { !installed.contains($0.rawValue) }
        }
        return pending.first
    }
}
