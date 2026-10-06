import AppKit

@MainActor
final class ScreenshotController {
    private var isOpening = false

    func capture(localization: Localization) {
        guard !isOpening else { return }
        isOpening = true
        // Let the popup disappear before the system presents its capture toolbar.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                Task { @MainActor [weak self] in
                    self?.isOpening = false
                    guard error != nil else { return }
                    let alert = NSAlert()
                    alert.messageText = localization.string(.compactScreenshot)
                    alert.informativeText = localization.string(.screenshotFailed)
                    alert.runModal()
                }
            }
        }
    }
}
