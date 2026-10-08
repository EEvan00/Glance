import AppKit
import CoreGraphics
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
        guard let package = Bundle.main.url(forResource: name, withExtension: "pkg") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Keep this package's window separate from unrelated Installer sessions.
        configuration.createsNewApplicationInstance = true
        let installer = try await NSWorkspace.shared.open(
            [package],
            withApplicationAt: URL(fileURLWithPath: "/System/Library/CoreServices/Installer.app"),
            configuration: configuration
        )
        var session = MagSafeInstallerSessionState(startedAt: Date())
        // Installer owns the administrator prompt; no password is handled by Glance.
        try await MagSafeInstallerWaiter.waitForCompletion(
            completed: completed,
            isInstallerRunning: {
                // Closing the package window may leave the process alive.
                // Window metadata needs no screen recording or accessibility access.
                let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
                let hasWindow = windows.contains {
                    ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == installer.processIdentifier
                        && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
                }
                return session.isActive(processTerminated: installer.isTerminated, hasWindow: hasWindow, now: Date())
            },
            isCorrupt: {
                guard name == "GlanceHelperInstall",
                      let attributes = try? FileManager.default.attributesOfItem(atPath: MagSafeHelperInstallation.directory + "/ready"),
                      let modified = attributes[.modificationDate] as? Date, modified >= started else { return false }
                return MagSafeHelperInstallation.read() == nil
            }
        )
    }
}
