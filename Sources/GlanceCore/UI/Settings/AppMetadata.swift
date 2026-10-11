// Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
import Foundation

enum AppMetadata {
    static let defaultName = "Glance"
    private static let nameKeys = ["CFBundleDisplayName", "CFBundleName"]

    static var name: String {
        for key in nameKeys {
            if let value = validName(Bundle.main.object(forInfoDictionaryKey: key)) {
                return value
            }
        }
        return defaultName
    }

    static func name(from infoDictionary: [String: Any]) -> String {
        for key in nameKeys {
            if let value = validName(infoDictionary[key]) {
                return value
            }
        }
        return defaultName
    }

    private static func validName(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    static let repositoryDisplayName = "github.com/EEvan00/Glance"
    static let repositoryURL = URL(string: "https://github.com/EEvan00/Glance")!
    static let projectHomepageURL = URL(string: "https://github.com/EEvan00/Glance")!
    static let authorName = "EEvan00"
    static let authorURL = repositoryURL
    static let upstreamURL = URL(string: "https://github.com/lingyired/status-trio")!
    static let donateURL = URL(string: "https://glance.gadels.com/donate")!
    static let repositoryIsAvailable = true

    static var versionDisplayString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return version
    }
}
