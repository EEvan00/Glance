import Darwin
import Foundation
import IOKit.ps
import MagSafeSMC
import ServiceManagement

struct SMCMagSafeLEDHardwareProbe: MagSafeLEDHardwareProbing {
    func supportsLEDControl() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        return sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                    as? [String: Any] else {
                return false
            }
            return description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }
}

protocol MagSafeLEDXPCTransporting: Sendable {
    func setLEDMode(rawValue: UInt8) async throws -> Bool
    func renewOffLease() async throws -> Bool
}

extension MagSafeLEDXPCTransporting {
    func renewOffLease() async throws -> Bool { false }
}

struct XPCMagSafeLEDCommandWriter: MagSafeLEDCommandWriting {
    private let transport: any MagSafeLEDXPCTransporting

    init(transport: any MagSafeLEDXPCTransporting = SystemMagSafeLEDXPCTransport()) {
        self.transport = transport
    }

    func write(_ mode: MagSafeLEDMode) async throws {
        let command: MagSafeLEDCommand = mode == .system ? .system : .off
        guard try await transport.setLEDMode(rawValue: command.rawValue) else {
            throw MagSafeLEDCommandError.rejected
        }
    }

    func renewOffLease() async throws {
        if try await !transport.renewOffLease() { try await write(.off) }
    }
}

private final class SystemMagSafeLEDXPCTransport: MagSafeLEDXPCTransporting, @unchecked Sendable {
    private let serviceName: String

    init(
        serviceName: String = MagSafeLEDXPC.serviceName(
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    ) {
        self.serviceName = serviceName
    }

    func setLEDMode(rawValue: UInt8) async throws -> Bool {
        try await request(rawValue: rawValue)
    }

    func renewOffLease() async throws -> Bool {
        try await request(rawValue: nil)
    }

    private func request(rawValue: UInt8?) async throws -> Bool {
        let coordinator = MagSafeLEDXPCRequestCoordinator()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let connection = NSXPCConnection(
                    machServiceName: serviceName,
                    options: .privileged
                )
                let request = MagSafeLEDXPCRequest(
                    connection: connection,
                    continuation: continuation
                )
                coordinator.install(request)
                connection.remoteObjectInterface = NSXPCInterface(with: MagSafeLEDXPCProtocol.self)
                connection.interruptionHandler = {
                    request.finish(.failure(MagSafeLEDCommandError.connectionInterrupted))
                }
                connection.invalidationHandler = {
                    request.finish(.failure(MagSafeLEDCommandError.connectionInvalidated))
                }
                coordinator.sendIfNotCancelled {
                    connection.resume()

                    guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                        request.finish(.failure(error))
                    }) as? MagSafeLEDXPCProtocol else {
                        request.finish(.failure(MagSafeLEDCommandError.invalidProxy))
                        return
                    }
                    if let rawValue {
                        proxy.setLEDMode(rawValue) { succeeded in
                            request.finish(.success(succeeded))
                        }
                    } else {
                        proxy.renewOffLease { succeeded in
                            request.finish(.success(succeeded))
                        }
                    }
                }
            }
        } onCancel: {
            coordinator.cancel()
        }
    }
}

final class MagSafeLEDXPCRequestCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var request: MagSafeLEDXPCRequest?
    private var isCancelled = false
    private var hasSent = false

    fileprivate func install(_ request: MagSafeLEDXPCRequest) {
        lock.lock()
        self.request = request
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel {
            request.finish(.failure(CancellationError()))
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let request = hasSent ? nil : request
        lock.unlock()
        request?.finish(.failure(CancellationError()))
    }

    func sendIfNotCancelled(_ send: () -> Void) {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        hasSent = true
        send()
        lock.unlock()
    }
}

final class MagSafeLEDXPCRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var continuation: CheckedContinuation<Bool, Error>?
    private var timeoutWorkItem: DispatchWorkItem?

    init(
        connection: NSXPCConnection,
        continuation: CheckedContinuation<Bool, Error>,
        timeout: TimeInterval = 5
    ) {
        self.connection = connection
        self.continuation = continuation
        let deadline = DispatchWorkItem { [weak self] in
            self?.finish(.failure(MagSafeLEDCommandError.timedOut))
        }
        timeoutWorkItem = deadline
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
    }

    func finish(_ result: Result<Bool, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        let deadline = timeoutWorkItem
        timeoutWorkItem = nil
        lock.unlock()

        deadline?.cancel()
        continuation.resume(with: result)
        connection?.invalidate()
    }
}

private enum MagSafeLEDCommandError: Error {
    case timedOut
    case rejected
    case invalidProxy
    case connectionInterrupted
    case connectionInvalidated
}

enum MagSafeHelperStrategy: String, Sendable {
    case legacyPackage
    case bundledService
    case unavailable

    init(configuration: String?) {
        // SwiftPM/unpackaged builds retain the ad-hoc default. A malformed explicit
        // value fails closed instead of selecting an unexpected installer.
        self = configuration.map { Self(rawValue: $0) ?? .unavailable } ?? .legacyPackage
    }
}

struct SystemMagSafeLEDHelperManager: MagSafeLEDHelperManaging {
    static let plistName = "io.github.EEvan00.Glance.magsafe-helper.plist"
    static let legacyPlistName = "io.github.EEvan00.Glance.legacy-magsafe-helper.plist"

    private var service: SMAppService {
        SMAppService.daemon(plistName: Self.plistName)
    }

    var hasInstalledHelper: Bool {
        let oldStatus = SMAppService.daemon(plistName: Self.legacyPlistName).status
        return LegacyMagSafeHelperManager.hasInstalledFiles
            || service.status == .enabled || service.status == .requiresApproval
            || oldStatus == .enabled || oldStatus == .requiresApproval
    }

    private var strategy: MagSafeHelperStrategy {
        MagSafeHelperStrategy(configuration: Bundle.main.object(forInfoDictionaryKey: "GlanceMagSafeHelperStrategy") as? String)
    }

    var hasPreviouslyEnabledRegistration: Bool {
        guard strategy == .bundledService else { return false }
        return service.status == .enabled || SMAppService.daemon(plistName: Self.legacyPlistName).status == .enabled
    }

    @MainActor
    private func unregisterOldBundledService() async throws {
        let path = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchDaemons/\(Self.legacyPlistName)").path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let old = SMAppService.daemon(plistName: Self.legacyPlistName)
        if old.status == .enabled || old.status == .requiresApproval {
            try await Self.unregisterService(old)
        }
    }

    @MainActor
    func recoverRegistration() async throws -> Bool {
        // Never open Installer or silently migrate privileged legacy files.
        guard strategy == .bundledService, !LegacyMagSafeHelperManager.hasInstalledFiles else { return false }
        try await unregisterOldBundledService()
        let current = service
        try await Self.unregisterForPackage(
            status: { current.status },
            unregister: { try await Self.unregisterService(current) }
        )
        try current.register()
        return true
    }

    @MainActor
    func retireBundledRegistration() async throws {
        guard strategy == .bundledService else { return }
        let current = service
        if current.status == .enabled || current.status == .requiresApproval {
            try await Self.unregisterService(current)
        }
        try await unregisterOldBundledService()
    }

    var status: MagSafeLEDHelperStatus {
        Self.helperStatus(
            strategy: strategy,
            legacyInstalled: LegacyMagSafeHelperManager.hasInstalledFiles,
            legacyCurrent: LegacyMagSafeHelperManager().isCurrent,
            serviceStatus: service.status
        )
    }

    static func helperStatus(
        strategy: MagSafeHelperStrategy,
        legacyInstalled: Bool,
        legacyCurrent: Bool,
        serviceStatus: SMAppService.Status
    ) -> MagSafeLEDHelperStatus {
        switch strategy {
        case .legacyPackage:
            return legacyInstalled && legacyCurrent ? .enabled : .notRegistered
        case .unavailable:
            return .notRegistered
        case .bundledService:
            // Even a valid old helper must be migrated explicitly. Reporting it
            // as enabled would prevent the UI from offering the authorized install.
            guard !legacyInstalled else { return .notRegistered }
            return switch serviceStatus {
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notRegistered, .notFound: .notRegistered
            @unknown default: .notRegistered
            }
        }
    }

    @MainActor
    static func installBundled(
        hasLegacyFiles: () -> Bool,
        uninstallLegacy: () async throws -> Void,
        register: () throws -> Void
    ) async throws {
        if hasLegacyFiles() {
            // Installer owns administrator authorization, including cancellation.
            // Never register a conflicting Mach service after a failed removal.
            try await uninstallLegacy()
            guard !hasLegacyFiles() else { throw CocoaError(.fileWriteUnknown) }
        }
        try Task.checkCancellation()
        try register()
    }

    @MainActor
    private static func unregisterService(_ service: SMAppService) async throws {
        // Invoke the callback API on the main actor. Swift 6.1's imported async
        // variant sends the non-Sendable service across an isolation boundary.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            service.unregister { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    @MainActor
    static func unregisterForPackage(
        status: () -> SMAppService.Status,
        unregister: () async throws -> Void
    ) async throws {
        do {
            try await unregister()
        } catch {
            // Service Management may report a stale-registration error after
            // completing removal. Only proceed if the service is actually gone.
            guard status() == .notRegistered || status() == .notFound else { throw error }
        }
    }

    @MainActor
    func install() async throws {
        switch strategy {
        case .legacyPackage:
            if service.status == .enabled || service.status == .requiresApproval {
                let existingService = service
                try await Self.unregisterForPackage(
                    status: { existingService.status },
                    unregister: { try await Self.unregisterService(existingService) }
                )
            }
            try await LegacyMagSafeHelperManager().install()
        case .bundledService:
            try await unregisterOldBundledService()
            let bundledService = service
            try await Self.installBundled(
                hasLegacyFiles: { LegacyMagSafeHelperManager.hasInstalledFiles },
                uninstallLegacy: { try await LegacyMagSafeHelperManager().uninstall() },
                register: {
                    if bundledService.status != .enabled && bundledService.status != .requiresApproval {
                        try bundledService.register()
                    }
                }
            )
        case .unavailable:
            throw CocoaError(.featureUnsupported)
        }
    }

    func uninstall() async throws {
        if LegacyMagSafeHelperManager.hasInstalledFiles { try await LegacyMagSafeHelperManager().uninstall() }
        if service.status == .enabled || service.status == .requiresApproval { try await Self.unregisterService(service) }
        try await unregisterOldBundledService()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
