import AppKit

@MainActor
final class ScreenshotController {
    private var process: Process?

    func capture(mode: ScreenshotMode, destination: ScreenshotDestination, localization: Localization) {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Glance \(formatter.string(from: Date())) \(UUID().uuidString.prefix(6)).png"
        process.arguments = ScreenshotRequest(mode: mode, destination: destination)
            .arguments(fileURL: desktop.appendingPathComponent(name))
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.process = nil }
        }
        self.process = process
        // Wait for the popup to disappear before presenting the system capture UI.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            do {
                try process.run()
            } catch {
                self?.process = nil
                let alert = NSAlert()
                alert.messageText = localization.string(.compactScreenshot)
                alert.informativeText = localization.string(.screenshotFailed)
                alert.runModal()
            }
        }
    }
}
