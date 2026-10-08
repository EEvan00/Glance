import Combine
import Foundation

enum MagSafeLEDMode: String, Equatable, Sendable {
    case system
    case off

    var isLightEnabled: Bool { self == .system }
}

enum MagSafeLEDAvailability: Equatable, Sendable {
    case unsupported
    case needsInstallation
    case requiresApproval
    case ready
}

enum MagSafeLEDHelperStatus: Equatable, Sendable {
    case notRegistered
    case requiresApproval
    case enabled
}

enum MagSafeLEDError: Equatable, Sendable {
    case installFailed
    case uninstallFailed
    case writeFailed
}

protocol MagSafeLEDHardwareProbing: Sendable {
    func supportsLEDControl() -> Bool
}

protocol MagSafeLEDHelperManaging: Sendable {
    var status: MagSafeLEDHelperStatus { get }
    func install() async throws
    func uninstall() async throws
    func openSystemSettings()
}

protocol MagSafeLEDCommandWriting: Sendable {
    func write(_ mode: MagSafeLEDMode) async throws
}

@MainActor
final class MagSafeLEDController: ObservableObject {
    static let defaultsKey = "magSafeLEDLightEnabled"

    @Published private(set) var isLightEnabled: Bool
    @Published private(set) var availability: MagSafeLEDAvailability
    @Published private(set) var error: MagSafeLEDError?
    @Published private(set) var isBusy = false
    @Published private(set) var needsHelperRecovery = false

    private let defaults: UserDefaults
    private let hardwareProbe: any MagSafeLEDHardwareProbing
    private let helperManager: any MagSafeLEDHelperManaging
    private let commandWriter: any MagSafeLEDCommandWriting

    static func unavailable(defaults: UserDefaults = .standard) -> MagSafeLEDController {
        MagSafeLEDController(
            defaults: defaults,
            hardwareProbe: UnavailableMagSafeLEDHardwareProbe(),
            helperManager: UnavailableMagSafeLEDHelperManager(),
            commandWriter: UnavailableMagSafeLEDCommandWriter()
        )
    }

    init(
        defaults: UserDefaults = .standard,
        hardwareProbe: any MagSafeLEDHardwareProbing,
        helperManager: any MagSafeLEDHelperManaging,
        commandWriter: any MagSafeLEDCommandWriting
    ) {
        self.defaults = defaults
        self.hardwareProbe = hardwareProbe
        self.helperManager = helperManager
        self.commandWriter = commandWriter
        self.isLightEnabled = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
        self.availability = Self.availability(
            hardwareProbe: hardwareProbe,
            helperManager: helperManager
        )
    }

    func setLightEnabled(_ enabled: Bool) {
        guard availability == .ready, !isBusy else { return }
        let mode: MagSafeLEDMode = enabled ? .system : .off
        isBusy = true
        Task { [weak self, commandWriter] in
            do {
                try await commandWriter.write(mode)
                guard let self else { return }
                self.isLightEnabled = enabled
                self.defaults.set(enabled, forKey: Self.defaultsKey)
                self.error = nil
                self.needsHelperRecovery = false
                self.isBusy = false
            } catch {
                guard let self else { return }
                self.needsHelperRecovery = true
                self.error = .writeFailed
                self.isBusy = false
            }
        }
    }

    func reapplyIfNeeded() {
        guard availability == .ready, !isLightEnabled, !isBusy, error == nil else { return }
        isBusy = true
        Task { [weak self, commandWriter] in
            do {
                try await commandWriter.write(.off)
                guard let self else { return }
                self.error = nil
                self.needsHelperRecovery = false
                self.isBusy = false
            } catch {
                guard let self else { return }
                self.needsHelperRecovery = true
                self.error = .writeFailed
                self.isBusy = false
            }
        }
    }

    func installHelper() {
        guard availability == .needsInstallation, !isBusy else { return }
        isBusy = true
        error = nil
        Task { [weak self, helperManager, commandWriter] in
            do {
                try await helperManager.install()
                guard let self else { return }
                self.availability = Self.availability(
                    hardwareProbe: self.hardwareProbe,
                    helperManager: helperManager
                )
                if self.availability == .ready {
                    try await commandWriter.write(self.isLightEnabled ? .system : .off)
                    self.needsHelperRecovery = false
                }
                self.isBusy = false
            } catch {
                guard let self else { return }
                self.availability = Self.availability(
                    hardwareProbe: self.hardwareProbe,
                    helperManager: helperManager
                )
                if self.availability == .requiresApproval || (error as? CocoaError)?.code == .userCancelled || error is CancellationError {
                    self.error = nil
                } else {
                    self.needsHelperRecovery = self.availability == .ready
                    self.error = .installFailed
                }
                self.isBusy = false
            }
        }
    }

    func uninstallHelper() {
        guard availability == .ready, !isBusy else { return }
        isBusy = true
        error = nil
        Task { [weak self, helperManager] in
            do {
                guard let self else { return }
                try await self.commandWriter.write(.system)
                try await helperManager.uninstall()
                self.isLightEnabled = true
                self.defaults.set(true, forKey: Self.defaultsKey)
                self.needsHelperRecovery = false
                self.availability = .needsInstallation
                self.isBusy = false
            } catch {
                guard let self else { return }
                self.error = .uninstallFailed
                self.isBusy = false
            }
        }
    }

    func removeUnresponsiveHelper() {
        // Explicit recovery after a failed command: another reset write would
        // just wait on the same unavailable service. Preserve the stored choice.
        guard availability == .ready, !isBusy, needsHelperRecovery else { return }
        isBusy = true
        Task { [weak self, helperManager] in
            do {
                try await helperManager.uninstall()
                guard let self else { return }
                self.error = nil
                self.needsHelperRecovery = false
                self.availability = .needsInstallation
                self.isBusy = false
            } catch {
                guard let self else { return }
                self.error = .uninstallFailed
                self.isBusy = false
            }
        }
    }

    func clearError() {
        error = nil
    }

    func refreshAvailability() {
        let previousAvailability = availability
        availability = Self.availability(
            hardwareProbe: hardwareProbe,
            helperManager: helperManager
        )
        if previousAvailability != .ready, availability == .ready {
            reapplyIfNeeded()
        }
    }

    func openHelperSettings() {
        helperManager.openSystemSettings()
    }

    private static func availability(
        hardwareProbe: any MagSafeLEDHardwareProbing,
        helperManager: any MagSafeLEDHelperManaging
    ) -> MagSafeLEDAvailability {
        guard hardwareProbe.supportsLEDControl() else { return .unsupported }
        switch helperManager.status {
        case .notRegistered: return .needsInstallation
        case .requiresApproval: return .requiresApproval
        case .enabled: return .ready
        }
    }
}

private struct UnavailableMagSafeLEDHardwareProbe: MagSafeLEDHardwareProbing {
    func supportsLEDControl() -> Bool { false }
}

private struct UnavailableMagSafeLEDHelperManager: MagSafeLEDHelperManaging {
    var status: MagSafeLEDHelperStatus { .notRegistered }
    func install() async throws {}
    func uninstall() async throws {}
    func openSystemSettings() {}
}

private struct UnavailableMagSafeLEDCommandWriter: MagSafeLEDCommandWriting {
    func write(_ mode: MagSafeLEDMode) async throws {}
}
