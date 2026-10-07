import Combine
import Foundation

/// Records only versions reported by a successfully executed shortcut, never installer clicks.
@MainActor
final class WeatherShortcutVersions: ObservableObject {
    static let shared = WeatherShortcutVersions()
    private static let defaultsKey = "weatherShortcutObservedVersions"
    @Published private(set) var observed: [String: Int]
    private(set) var pendingVerification: Set<String> = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observed = (defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:])
            .filter { $0.value >= 0 }
    }

    func record(name: String, version: Int?) {
        guard let shortcut = BundledWeatherShortcut(rawValue: name) else { return }
        let revision = max(0, version ?? 0) // Legacy shortcuts have no version marker.
        if revision >= shortcut.version { pendingVerification.remove(name) }
        guard observed[name] != revision else { return }
        observed[name] = revision
        defaults.set(observed, forKey: Self.defaultsKey)
    }

    func requestVerification(name: String) {
        guard BundledWeatherShortcut(rawValue: name) != nil else { return }
        pendingVerification.insert(name)
    }

    func needsUpdate(name: String, bundledVersion: Int) -> Bool {
        guard let installedVersion = observed[name] else { return false }
        return installedVersion < bundledVersion
    }
}
