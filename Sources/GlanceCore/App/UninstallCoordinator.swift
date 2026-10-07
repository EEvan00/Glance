import AppKit

/// Stops at the first failure so the app remains available to explain the error.
@MainActor
struct UninstallCoordinator {
    let removeHelper: () async throws -> Void
    let removeLoginItem: () throws -> Void
    var removeIntegrations: () throws -> Void = {}
    let moveApplicationToTrash: () throws -> Void
    let quit: () -> Void

    func uninstall() async throws {
        try await removeHelper()
        try removeLoginItem()
        try removeIntegrations()
        try moveApplicationToTrash()
        quit()
    }

    static var supportsCurrentApplication: Bool {
        Bundle.main.bundleURL.pathExtension == "app" &&
        Bundle.main.bundleIdentifier == "io.github.EEvan00.Glance"
    }

    static var live: UninstallCoordinator {
        UninstallCoordinator(
            removeHelper: {
                guard supportsCurrentApplication else { throw CocoaError(.fileWriteNoPermission) }
                let helper = SystemMagSafeLEDHelperManager()
                if helper.hasInstalledHelper { try await helper.uninstall() }
            },
            removeLoginItem: {
                let login = SystemLaunchAtLoginService()
                if login.status != .notRegistered { try login.unregister() }
            },
            removeIntegrations: { try ClaudeUsageIntegration.uninstall() },
            moveApplicationToTrash: {
                guard supportsCurrentApplication else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
            },
            quit: { NSApp.terminate(nil) }
        )
    }
}
