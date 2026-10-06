import Foundation

enum ScreenshotMode: String, CaseIterable, Identifiable, Sendable {
    case toolbar, region
    var id: String { rawValue }
    var labelKey: LocalizationKey { self == .toolbar ? .settingsScreenshotToolbar : .settingsScreenshotRegion }
}

enum ScreenshotDestination: String, CaseIterable, Identifiable, Sendable {
    case desktop, clipboard
    var id: String { rawValue }
    var labelKey: LocalizationKey { self == .desktop ? .settingsScreenshotDesktop : .settingsScreenshotClipboard }
}

struct ScreenshotRequest: Sendable {
    let mode: ScreenshotMode
    let destination: ScreenshotDestination

    func arguments(fileURL: URL) -> [String] {
        var arguments = ["-i"]
        arguments += mode == .toolbar ? ["-U"] : ["-s"]
        if destination == .clipboard { arguments += ["-c"] }
        else { arguments += ["-t", "png", fileURL.path] }
        return arguments
    }
}
