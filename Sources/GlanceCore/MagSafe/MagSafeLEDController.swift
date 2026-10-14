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
    var hasPreviouslyEnabledRegistration: Bool { get }
    func install() async throws
    func uninstall() async throws
    func openSystemSettings()
    func recoverRegistration() async throws -> Bool
    func retireBundledRegistration() async throws
}

extension MagSafeLEDHelperManaging {
    var hasPreviouslyEnabledRegistration: Bool { false }
    func recoverRegistration() async throws -> Bool { false }
    func retireBundledRegistration() async throws {}
}

protocol MagSafeLEDCommandWriting: Sendable {
    func write(_ mode: MagSafeLEDMode) async throws
    func renewOffLease() async throws
}

extension MagSafeLEDCommandWriting {
    func renewOffLease() async throws { try await write(.off) }
}

@MainActor
final class MagSafeLEDController: ObservableObject {
    static let defaultsKey = "magSafeLEDLightEnabled"
    static let helperEnabledKey = "magSafeHelperPreviouslyEnabled"
    static var isUninstalling = false

    @Published private(set) var isLightEnabled: Bool
    @Published private(set) var availability: MagSafeLEDAvailability
    @Published private(set) var error: MagSafeLEDError?
    @Published private(set) var isBusy = false
    @Published private(set) var needsHelperRecovery = false

    private let defaults: UserDefaults
    private let hardwareProbe: any MagSafeLEDHardwareProbing
    private let helperManager: any MagSafeLEDHelperManaging
    private let commandWriter: any MagSafeLEDCommandWriting
    private let isApplicationPresent: @Sendable () -> Bool
    private var monitoringTask: Task<Void, Never>?
    private var retired = false
    private var attemptedRecovery = false
    private var checkedConnection = false

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
        commandWriter: any MagSafeLEDCommandWriting,
        isApplicationPresent: @escaping @Sendable () -> Bool = { true }
    ) {
        self.defaults = defaults
        self.hardwareProbe = hardwareProbe
        self.helperManager = helperManager
        self.commandWriter = commandWriter
        self.isApplicationPresent = isApplicationPresent
        self.isLightEnabled = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true
        self.availability = Self.availability(
            hardwareProbe: hardwareProbe,
            helperManager: helperManager
        )
    }

    deinit { monitoringTask?.cancel() }

    func startMonitoring() {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.maintenanceTick()
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
    }

    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    func prepareForTermination() async {
        retired = true
        stopMonitoring()
        if availability == .ready { try? await commandWriter.write(.system) }
        // An already-sent off request may finish late. Without renewals its
        // helper lease still expires; normal termination does not erase choice.
    }

    func maintenanceTick() async {
        guard !isBusy, !retired, !Self.isUninstalling else { return }
        isBusy = true
        defer { isBusy = false }
        if !isApplicationPresent() {
            retired = true
            // Stop renewal even if IPC/registration cleanup fails. The helper's
            // independent lease remains the crash and deletion fallback.
            if availability == .ready { try? await commandWriter.write(.system) }
            try? await helperManager.retireBundledRegistration()
            availability = .needsInstallation
            return
        }
        availability = Self.availability(hardwareProbe: hardwareProbe, helperManager: helperManager)
        if availability == .ready || helperManager.hasPreviouslyEnabledRegistration {
            defaults.set(true, forKey: Self.helperEnabledKey)
        }
        if (availability == .needsInstallation || needsHelperRecovery),
           defaults.bool(forKey: Self.helperEnabledKey), !attemptedRecovery {
            attemptedRecovery = true
            do {
                if try await helperManager.recoverRegistration() {
                    guard !Self.isUninstalling, isApplicationPresent() else {
                        try? await helperManager.retireBundledRegistration()
                        return
                    }
                    availability = Self.availability(hardwareProbe: hardwareProbe, helperManager: helperManager)
                    if availability == .ready {
                        try await commandWriter.write(isLightEnabled ? .system : .off)
                        error = nil
                        needsHelperRecovery = false
                        checkedConnection = true
                    } else if availability == .requiresApproval {
                        error = nil
                        needsHelperRecovery = false
                    }
                }
            } catch {
                availability = Self.availability(hardwareProbe: hardwareProbe, helperManager: helperManager)
                self.error = availability == .requiresApproval ? nil : .installFailed
            }
            return
        }
        guard availability == .ready, error == nil else { return }
        do {
            if !isLightEnabled { try await commandWriter.renewOffLease() }
            else if !checkedConnection { try await commandWriter.write(.system) }
            checkedConnection = true
        } catch {
            needsHelperRecovery = true
            self.error = .writeFailed
        }
    }

    func setLightEnabled(_ enabled: Bool) {
        guard availability == .ready, !isBusy, !retired, !Self.isUninstalling, isApplicationPresent() else { return }
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
        guard availability == .ready, !isLightEnabled, !isBusy, error == nil,
              !retired, !Self.isUninstalling, isApplicationPresent() else { return }
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
        guard availability == .needsInstallation, !isBusy, !retired, !Self.isUninstalling, isApplicationPresent() else { return }
        isBusy = true
        error = nil
        Task { [weak self, helperManager, commandWriter] in
            do {
                try await helperManager.install()
                guard let self else { return }
                self.defaults.set(true, forKey: Self.helperEnabledKey)
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
                self.defaults.set(false, forKey: Self.helperEnabledKey)
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
                self.defaults.set(false, forKey: Self.helperEnabledKey)
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
