import AppKit
import Foundation
import MagSafeSMC

struct LegacyMagSafeHelperManager: Sendable {
    static var hasInstalledFiles: Bool {
        [MagSafeHelperInstallation.configurationPath, MagSafeHelperInstallation.binaryPath, MagSafeHelperInstallation.plistPath]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    var isCurrent: Bool {
        guard FileManager.default.fileExists(atPath: MagSafeHelperInstallation.directory + "/ready"),
              let installation = MagSafeHelperInstallation.read(),
              FileManager.default.fileExists(atPath: MagSafeHelperInstallation.binaryPath),
              FileManager.default.fileExists(atPath: MagSafeHelperInstallation.plistPath) else { return false }
        return installation.matches(app: Bundle.main.bundleURL, build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
    }

    @MainActor
    func install() async throws {
        guard Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/Glance.app" else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await runPackage(name: "GlanceHelperInstall") { isCurrent }
    }

    @MainActor
    func uninstall() async throws {
        guard Self.hasInstalledFiles else { return }
        try await runPackage(name: "GlanceHelperUninstall") { !Self.hasInstalledFiles }
    }

    @MainActor
    private func runPackage(name: String, completed: () -> Bool) async throws {
        let started = Date()
        guard let package = Bundle.main.url(forResource: name, withExtension: "pkg"),
              NSWorkspace.shared.open(package) else { throw CocoaError(.fileNoSuchFile) }
        // Installer owns the administrator prompt; no password is handled by Glance.
        for _ in 0..<300 {
            try Task.checkCancellation()
            if completed() { return }
            if name == "GlanceHelperInstall",
               let attributes = try? FileManager.default.attributesOfItem(atPath: MagSafeHelperInstallation.directory + "/ready"),
               let modified = attributes[.modificationDate] as? Date, modified >= started,
               MagSafeHelperInstallation.read() == nil {
                throw CocoaError(.fileReadCorruptFile)
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw CocoaError(.userCancelled)
    }
}
